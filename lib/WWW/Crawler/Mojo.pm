package WWW::Crawler::Mojo;
use strict;
use warnings;
use 5.010;
use Mojo::Base 'Mojo::EventEmitter';
use WWW::Crawler::Mojo::Job;
use WWW::Crawler::Mojo::UserAgent;
use Mojo::Message::Request;
use Mojo::Util qw{md5_sum xml_escape dumper};
use List::Util;
our $VERSION = '0.10';

has active_conn => 0;
has fix => sub { {} };
has active_conns_per_host => sub { {} };
has max_conn => 1;
has max_conn_per_host => 1;
has 'peeping_port';
has peeping_max_length => 30000;
has queue => sub { [] };
has 'ua' => sub { WWW::Crawler::Mojo::UserAgent->new };
has 'ua_name' =>
    "www-crawler-mojo/$VERSION (+https://github.com/jamadam/www-crawler-mojo)";
has 'shuffle';
has element_handlers => sub { {
    'script[src]'   => sub { $_[0]->{src} },
    'link[href]'    => sub { $_[0]->{href} },
    'a[href]'       => sub { $_[0]->{href} },
    'img[src]'      => sub { $_[0]->{src} },
    'area'          => sub { $_[0]->{href}, $_[0]->{ping} },
    'embed[src]'    => sub { $_[0]->{src} },
    'frame[src]'    => sub { $_[0]->{src} },
    'iframe[src]'   => sub { $_[0]->{src} },
    'input[src]'    => sub { $_[0]->{src} },
    'object[data]'  => sub { $_[0]->{data} },
    'form'          => sub {
        my $dom = shift;
        my (%seed, $submit);
        
        $dom->find("[name]")->each(sub {
            my $e = shift;
            $seed{my $name = $e->{name}} ||= [];
            
            if ($e->type eq 'select') {
                $e->find('option[selected]')->each(sub {
                    push(@{$seed{$name}}, shift->{value});
                });
            } elsif ($e->type eq 'textarea') {
                push(@{$seed{$name}}, $e->text);
            }
            
            return unless (my $type = $e->{type});
            
            if (!$submit && grep{$_ eq $type} qw{submit image}) {
                $submit = 1;
                push(@{$seed{$name}}, $e->{value});
            } elsif (grep {$_ eq $type} qw{text hidden number}) {
                push(@{$seed{$name}}, $e->{value});
            } elsif (grep {$_ eq $type} qw{checkbox}) {
                push(@{$seed{$name}}, $e->{value}) if (exists $e->{checked});
            } elsif (grep {$_ eq $type} qw{radio}) {
                push(@{$seed{$name}}, $e->{value}) if (exists $e->{checked});
            }
        });
        
        return [$dom->{action},
            $dom, uc ($dom->{method} || 'GET'), Mojo::Parameters->new(%seed),
        ];
    },
    'meta[content]' => sub {
        return $1 if ($_[0] =~ qr{http\-equiv="?Refresh"?}i &&
                                (($_[0]->{content} || '') =~ qr{URL=(.+)}i)[0]);
    },
    'style' => sub {
        my $dom = shift;
        return collect_urls_css($dom->content);
    },
    '[style]' => sub {
        collect_urls_css(shift->{style});
    }
} };

sub crawl {
    my ($self) = @_;
    
    $self->init;
    
    die 'No job is given' if (! scalar @{$self->queue});
    
    $self->emit('start');
    
    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

sub init {
    my ($self) = @_;
    
    $self->on('empty', sub { say "Queue is drained out."; Mojo::IOLoop->reset })
                                        unless $self->has_subscribers('empty');
    $self->on('error', sub { say "An error occured during crawling $_[0]: $_[1]" })
                                        unless $self->has_subscribers('error');
    $self->on('res', sub { $_[1]->() })
                                        unless $self->has_subscribers('res');
    $self->on('refer', sub { $_[1]->() })
                                        unless $self->has_subscribers('refer');
    
    $self->ua->transactor->name($self->ua_name);
    $self->ua->max_redirects(5);
    
    Mojo::IOLoop->recurring(0.25 => sub {
        $self->process_job(@_);
    });
    
    if ($self->peeping_port) {
        Mojo::IOLoop->server({port => $self->peeping_port}, sub {
            $self->peeping_handler(@_);
        });
    }
    
    if ($self->shuffle) {
        Mojo::IOLoop->recurring($self->shuffle => sub {
            @{$self->{queue}} = List::Util::shuffle @{$self->{queue}};
        });
    }
}

sub process_job {
    my $self = shift;
    
    if (!$self->{queue}->[0]) {
        $self->emit('empty') if (!$self->active_conn);
        return;
    } elsif (!($self->_mod_busyness($self->{queue}->[0]->resolved_uri, 1))) {
        return;
    }
    
    my $job = shift @{$self->{queue}};
    my $uri = $job->resolved_uri;
    my $ua = $self->ua;
    my $tx = $ua->build_tx($job->method || 'get' => $uri => $job->tx_params);
    
    $ua->start($tx, sub {
        $self->_mod_busyness($uri, -1);
        
        my ($ua, $tx) = @_;
        
        $job->redirect(_urls_redirect($tx));
        
        my $res = $tx->res;
        
        if (!$res->code) {
            $self->emit('error',
                ($res->error) ? $res->error->{message} : 'Unknown error', $job);
            return;
        }
        
        $self->emit('res', sub { $self->scrape($res, $job) }, $job, $res);
    });
}

sub say_start {
    my $self = shift;
    
    print <<"EOF";
----------------------------------------
Crawling is starting with @{[ $self->queue->[0]->resolved_uri ]}
Max Connection  : @{[ $self->max_conn ]}
User Agent      : @{[ $self->ua_name ]}
EOF

    print <<"EOF" if ($self->peeping_port);
Peeping API is available at following URL
    http://127.0.0.1:@{[ $self->peeping_port ]}/
EOF
    
    print <<"EOF";
----------------------------------------
EOF
}

sub peeping_handler {
    my ($self, $loop, $stream) = @_;
    $stream->on(read => sub {
        my ($stream, $bytes) = @_;
        
        my $path = Mojo::Message::Request->new->parse($bytes)->url->path;
        
        if ($path =~ qr{^/queue}) {
            my $res = sprintf('%s jobs are left.', scalar @{$self->queue});
            $stream->write("HTTP/1.1 200 OK\n\n");
            $stream->write($res, sub {shift->close});
            return;
        }
        
        if ($path =~ qr{^/dumper/(\w+)} && defined $self->{$1}) {
            my $res = substr(dumper($self->{$1}), 0, $self->peeping_max_length);
            $stream->write("HTTP/1.1 200 OK\n\n");
            $stream->write($res, sub {shift->close});
            return;
        }
        
        $stream->write(
                    "HTTP/1.1 404 NOT FOUND\n\nNOT FOUND", sub {shift->close});
    });
}

sub scrape {
    my ($self, $res, $job) = @_;
    
    return if ($res->code != 200);
    
    my $base = $job->resolved_uri;
    my $type = $res->headers->content_type;
    
    if ($type && $type =~ qr{text/(html|xml)} &&
                                (my $base_tag = $res->dom->at('base'))) {
        $base = resolve_href($base, $base_tag->attr('href'));
    }
    
    my $cb = sub {
        my ($url, $dom, $method, $params) = @_;
        
        $url = _clean_url_obj($url);
        my $resolved = resolve_href($base, $url);
        
        return unless ($resolved->scheme =~ qr{http|https|ftp|ws|wss});
        
        my $child = $job->child(resolved_uri => $resolved, literal_uri => $url);
        
        $child->method($method) if $method;
        
        if ($params) {
            if ($method eq 'GET') {
                $child->resolved_uri->query->append($params);
            } else {
                $child->tx_params($params);
            }
        }
        
        $self->emit('refer', sub {
            $self->enqueue($_[0] || $child);
        }, $child, $dom || $job->resolved_uri);
    };
    
    if ($type && $type =~ qr{text/(html|xml)}) {
        my $encode = guess_encoding($res) || 'utf-8';
        my $body = Encode::decode($encode, $res->body);
        $self->collect_urls_html(Mojo::DOM->new($body), $cb);
    }
    
    if ($type && $type =~ qr{text/css}) {
        my $encode  = guess_encoding($res) || 'utf-8';
        my $body    = Encode::decode($encode, $res->body);
        for (collect_urls_css($body)) {
            $cb->($_);
        }
    }
};

sub enqueue {
    shift->_enqueue([@_]);
}

sub requeue {
    shift->_enqueue([@_], 1);
}

sub _enqueue {
    my ($self, $jobs, $requeue) = @_;
    
    for my $job (@$jobs) {
        if (! ref $job || ref $job ne 'WWW::Crawler::Mojo::Job') {
            my $url = !ref $job ? Mojo::URL->new($job) : $job;
            $job = WWW::Crawler::Mojo::Job->new(resolved_uri => $url);
        }
        
        my $md5_seed = $job->resolved_uri->to_string. ($job->method || '');
        $md5_seed .= $job->tx_params->to_string if ($job->tx_params);
        my $md5 = md5_sum($md5_seed);
        if ($requeue || !exists $self->fix->{$md5}) {
            $self->fix->{$md5} = undef;
            push(@{$self->{queue}}, $job);
        }
    }
}

sub collect_urls_html {
    my ($self, $dom, $cb) = @_;
    
    for my $selector (sort keys %{$self->element_handlers}) {
        $dom->find($selector)->each(sub {
            my $dom = shift;
            return if ($dom->xml && _wrong_dom_detection($dom));
            for ($self->element_handlers->{$selector}->($dom)) {
                next unless ($_);
                (ref $_) ? $cb->(@$_) : $cb->($_, $dom);
            }
        });
    }
}

sub collect_urls_css {
    my ($str) = shift || return;
    $str =~ s{/\*.+?\*/}{}gs;
    my @urls = ($str =~ m{url\(['"]?(.+?)['"]?\)}g);
    return @urls;
}

my $charset_re = qr{\bcharset\s*=\s*['"]?([a-zA-Z0-9_\-]+)['"]?}i;

sub guess_encoding {
    my $res     = shift;
    my $type    = $res->headers->content_type;
    return unless ($type);
    my $charset = ($type =~ $charset_re)[0];
    return $charset if ($charset);
    return _guess_encoding_html($res->body) if ($type =~ qr{text/(html|xml)});
    return _guess_encoding_css($res->body) if ($type =~ qr{text/css});
}

sub resolve_href {
    my ($base, $href) = @_;
    $href = ref $href ? $href : Mojo::URL->new($href);
    $base = ref $base ? $base : Mojo::URL->new($base);
    my $abs = $href->to_abs($base)->fragment(undef);
    while ($abs->path->parts->[0] && $abs->path->parts->[0] =~ /^\./) {
        shift @{$abs->path->parts};
    }
    $abs->path->trailing_slash($base->path->trailing_slash) if (!$href->path->to_string);
    return $abs;
}

sub _urls_redirect {
    my $tx = shift;
    my @urls;
    @urls = _urls_redirect($tx->previous) if ($tx->previous);
    unshift(@urls, $tx->req->url->userinfo(undef));
    return @urls;
}

sub _wrong_dom_detection {
    my $dom = shift;
    while ($dom = $dom->parent) {
        return 1 if ($dom->type && $dom->type eq 'script');
    }
    return;
}

sub _clean_url_obj {
    my $url = shift;
    $url =~ s{^\s*}{}g;
    $url =~ s{\s*$}{}g;
    return Mojo::URL->new($url);
}

sub _guess_encoding_css {
    return (shift =~ qr{^\s*\@charset ['"](.+?)['"];}is)[0];
}

sub _guess_encoding_html {
    my $head = (shift =~ qr{<head>(.+)</head>}is)[0] or return;
    my $charset;
    Mojo::DOM->new($head)->find('meta[http\-equiv=Content-Type]')->each(sub{
        $charset = (shift->{content} =~ $charset_re)[0];
    });
    return $charset;
}

sub _mod_busyness {
    my ($self, $uri, $inc) = @_;
    my $key = _host_key($uri);
    my $hosts = $self->active_conns_per_host;
    
    return if ($inc > 0 && ($self->active_conn >= $self->max_conn ||
                        ($hosts->{$key} || 0) >= $self->max_conn_per_host));
    
    $self->{active_conn} += $inc;
    $hosts->{$key} += $inc;
    delete($hosts->{$key}) unless ($hosts->{$key});
    return 1;
}

sub _host_key {
    state $well_known_ports = {http => 80, https => 443};
    
    my $uri = ref $_[0] ? $_[0] : Mojo::URL->new($_[0]);
    my $key = $uri->scheme. '://'. $uri->ihost;
    
    if (my $port = $uri->port) {
        if ($port ne $well_known_ports->{$uri->scheme}) {
            $key .= ':'. $port;
        }
    }
    
    return $key;
}

1;

=head1 NAME

WWW::Crawler::Mojo - A web crawling framework for Perl

=head1 SYNOPSIS

    use strict;
    use warnings;
    use WWW::Crawler::Mojo;
    
    my $bot = WWW::Crawler::Mojo->new;
    
    $bot->on(res => sub {
        my ($bot, $scrape, $job, $res) = @_;
        
        $scrape->();
    });
    
    $bot->on(refer => sub {
        my ($bot, $enqueue, $job, $context) = @_;
        
        $enqueue->();
    });
    
    $bot->enqueue('http://example.com/');
    $bot->crawl;

=head1 DESCRIPTION

L<WWW::Crawler::Mojo> is a web crawling framework for those who familier with
L<Mojo>::* APIs.

Note that the module is aimed at trivial use cases of crawling within a
moderate range of web pages so DO NOT use it for persistent crawler jobs.

=head1 ATTRIBUTES

L<WWW::Crawler::Mojo> inherits all attributes from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 element_handlers

HTML element handler on scraping.

    my $handlers = $bot->element_handlers;
    $bot->element_handlers->{img} = sub {
        my $dom = shift;
        return $dom->{src};
    };

=head2 ua

A L<Mojo::UserAgent> instance.

    my $ua = $bot->ua;
    $bot->ua(Mojo::UserAgent->new);

=head2 ua_name

Name of crawler for User-Agent header.

    $bot->ua_name('my-bot/0.01 (+https://example.com/)');
    say $bot->ua_name; # 'my-bot/0.01 (+https://example.com/)'

=head2 active_conn

A number of current connections.

    $bot->active_conn($bot->active_conn + 1);
    say $bot->active_conn;

=head2 active_conns_per_host

A number of current connections per host.

    $bot->active_conns_per_host($bot->active_conns_per_host + 1);
    say $bot->active_conns_per_host;

=head2 fix

A hash whoes keys are md5 hashes of enqueued URLs.

=head2 max_conn

A number of max connections.

    $bot->max_conn(5);
    say $bot->max_conn; # 5

=head2 max_conn_per_host

A number of max connections per host.

    $bot->max_conn_per_host(5);
    say $bot->max_conn_per_host; # 5

=head2 peeping_port

An port number for providing peeping monitor. It also evalutated as boolean for
disabling/enabling the feature. Defaults to undef, meaning disable.

    $bot->peeping_port(3001);
    say $bot->peeping_port; # 3000

=head2 peeping_max_length

Max length of peeping monitor content.

    $bot->peeping_max_length(100000);
    say $bot->peeping_max_length; # 100000

=head2 queue

FIFO array contains L<WWW::Crawler::Mojo::Job> objects.

    push(@{$bot->queue}, WWW::Crawler::Mojo::Job->new(...));
    my $job = shift @{$bot->queue};

=head2 shuffle

An interval in seconds to shuffle the job queue. It also evalutated as boolean
for disabling/enabling the feature. Defaults to undef, meaning disable.

    $bot->shuffle(5);
    say $bot->shuffle; # 5

=head1 EVENTS

L<WWW::Crawler::Mojo> inherits all events from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 res

Emitted when crawler got response from server. The callback takes 4 arguments.

    $bot->on(res => sub {
        my ($bot, $scrape, $job, $res) = @_;
        if (...) {
            $scrape->();
        } else {
            # DO NOTHING
        }
    });

=over

=item $bot

L<WWW::Crawler::Mojo> instance.

=item $scrape

Scrape URLs out of the document. this is a shorthand of $bot->scrape($job)

=item $job

L<WWW::Crawler::Mojo::Job> instance.

=item $res

L<Mojo::Message::Response> instance.

=back

=head2 refer

Emitted when new URI is found. You can enqueue the URI conditionally with
the callback.

    $bot->on(refer => sub {
        my ($bot, $enqueue, $job, $context) = @_;
        if (...) {
            $enqueue->();
        } elseif (...) {
            $enqueue->(...); # maybe different url
        } else {
            # DO NOTHING
        }
    });

=over

=item $bot

L<WWW::Crawler::Mojo> instance.

=item $enqueue

Scrape URLs out of the document. this is a shorthand of $bot->enqueue($job)

=item $job

L<WWW::Crawler::Mojo::Job> instance.

=item $context

Either L<Mojo::DOM> or L<Mojo::URL> instance.

=back

=head2 empty

Emitted when queue length got zero. The length is checked every 5 seconds.

    $bot->on(empty => sub {
        my ($bot) = @_;
        say "Queue is drained out.";
    });

=head2 error

Emitted when user agent returns no status code for request. Possibly caused by
network errors or un-responsible servers.

    $bot->on(error => sub {
        my ($bot, $error, $job) = @_;
        say "error: $_[1]";
        if (...) { # until failur occures 3 times
            $bot->requeue($job);
        }
    });

Note that server errors such as 404 or 500 cannot be catched with the event.
Consider res event for the use case instead of this.

=head2 start

Emitted right before crawl is started.

    $bot->on(start => sub {
        my $self = shift;
        ...
    });

=head1 METHODS

L<WWW::Crawler::Mojo> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 crawl

Start crawling loop.

    $bot->crawl;

=head2 init

Initialize crawler settings.

    $bot->init;

=head2 process_job

Process a job.

    $bot->process_job;

=head2 say_start

Displays starting messages to STDOUT

    $bot->say_start;

=head2 peeping_handler

peeping API dispatcher.

    $bot->peeping_handler($loop, $stream);

=head2 scrape

Parses and discovers links in a web page. Each links are appended to FIFO array.

    $bot->scrape($res, $job);

=head2 enqueue

Append one or more URIs or L<WWW::Crawler::Mojo::Job> objects.

    $bot->enqueue('http://example.com/index1.html');

OR

    $bot->enqueue($job1, $job2);

OR

    $bot->enqueue(
        'http://example.com/index1.html',
        'http://example.com/index2.html',
        'http://example.com/index3.html',
    );

=head2 requeue

Append one or more URLs or jobs for re-try. This accepts same arguments as
enqueue method.

    $self->on(error => sub {
        my ($self, $msg, $job) = @_;
        if (...) { # until failur occures 3 times
            $bot->requeue($job);
        }
    });

=head2 collect_urls_html

Collects URLs out of HTML.

    $bot->collect_urls_html($dom, sub {
        my ($uri, $dom) = @_;
    });

=head2 collect_urls_css

Collects URLs out of CSS.

    @urls = collect_urls_css($dom);

=head2 guess_encoding

Guesses encoding of HTML or CSS with given L<Mojo::Message::Response> instance.

    $encode = WWW::Crawler::Mojo::guess_encoding($res) || 'utf-8'

=head2 resolve_href

Resolves URLs with a base URL.

    WWW::Crawler::Mojo::resolve_href($base, $uri);

=head1 EXAMPLE

L<https://github.com/jamadam/WWW-Flatten>

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) jamadam

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
