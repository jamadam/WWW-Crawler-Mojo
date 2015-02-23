package WWW::Crawler::Mojo;
use strict;
use warnings;
use 5.010;
use Mojo::Base 'Mojo::EventEmitter';
use WWW::Crawler::Mojo::Job;
use WWW::Crawler::Mojo::Queue::Memory;
use WWW::Crawler::Mojo::UserAgent;
use WWW::Crawler::Mojo::ScraperUtil qw{resolve_href decoded_body};
use Mojo::Message::Request;
use Mojo::Util qw{xml_escape dumper};
our $VERSION = '0.12';

has clock_speed => 0.25;
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
        
        return [$dom->{action} || '',
                    uc ($dom->{method} || 'GET'), Mojo::Parameters->new(%seed)];
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
    },
    'urlset[xmlns^=http://www.sitemaps.org/schemas/sitemap/]' => sub {
        @{$_->find('url loc')->map(sub {$_->content})->to_array};
    }
} };
has max_conn => 1;
has max_conn_per_host => 1;
has queue => sub { WWW::Crawler::Mojo::Queue::Memory->new };
has 'shuffle';
has ua => sub { WWW::Crawler::Mojo::UserAgent->new };
has ua_name =>
    "www-crawler-mojo/$VERSION (+https://github.com/jamadam/www-crawler-mojo)";

sub crawl {
    my ($self) = @_;
    
    $self->init;
    
    die 'No job is given' if (! $self->queue->length);
    
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
    
    $self->ua->transactor->name($self->ua_name);
    $self->ua->max_redirects(5);
    
    Mojo::IOLoop->recurring($self->clock_speed => sub {
        $self->process_job(@_);
    });
    
    if ($self->shuffle) {
        Mojo::IOLoop->recurring($self->shuffle => sub {
            $self->queue->shuffle;
        });
    }
}

sub process_job {
    my $self = shift;
    
    if (!$self->queue->length) {
        $self->emit('empty') if (!$self->ua->active_conn);
        return;
    }
    if ($self->ua->active_conn >= $self->max_conn ||
        $self->ua->active_host($self->queue->next->url) >= $self->max_conn_per_host) {
        return;
    }
    
    my $job = $self->queue->dequeue;
    my $url = $job->url;
    my $ua = $self->ua;
    my $tx = $ua->build_tx($job->method || 'get' => $url => $job->tx_params);
    
    $ua->start($tx, sub {
        my ($ua, $tx) = @_;
        
        $job->redirect(_urls_redirect($tx));
        
        my $res = $tx->res;
        
        if (!$res->code) {
            $self->emit('error',
                ($res->error) ? $res->error->{message} : 'Unknown error', $job);
            return;
        }
        
        $self->emit('res', sub {
            $self->scrape($res, $job, $_[0]);
        }, $job, $res);
        
        $job->close;
    });
}

sub say_start {
    my $self = shift;
    
    print <<"EOF";
----------------------------------------
Crawling is starting with @{[ $self->queue->next->url ]}
Max Connection  : @{[ $self->max_conn ]}
User Agent      : @{[ $self->ua_name ]}
----------------------------------------
EOF
}

sub scrape {
    my ($self, $res, $job, $cb) = @_;
    
    return unless $res->headers->content_length && $res->body;
    
    my $base = $job->url;
    my $type = $res->headers->content_type;
    
    if ($type && $type =~ qr{^(text|application)/(html|xml|xhtml)}) {
        if ((my $base_tag = $res->dom->at('base[href]'))) {
            $base = resolve_href($base, $base_tag->attr('href'));
        }
        my $dom = Mojo::DOM->new(decoded_body($res));
        for my $selector (sort keys %{$self->element_handlers}) {
            $dom->find($selector)->each(sub {
                my $dom = shift;
                return if ($dom->xml && _wrong_dom_detection($dom));
                for ($self->element_handlers->{$selector}->($dom)) {
                    $self->_delegate_enqueue($_, $dom, $job, $base, $cb);
                }
            });
        }
    }
    
    if ($type && $type =~ qr{text/css}) {
        for (collect_urls_css(decoded_body($res))) {
            $self->_delegate_enqueue($_, $job->url, $job, $base, $cb);
        }
    }
};

sub collect_urls_css {
    map { s/^(['"])// && s/$1$//; $_ } (shift || '') =~ m{url\((.+?)\)}ig;
}

sub _delegate_enqueue {
    my ($self, $url, $context, $job, $base, $cb) = @_;
    my $method, my $params;
    
    return unless $url;
    ($url, $method, $params) = @$url if (ref $url);
    
    my $resolved = resolve_href($base, $url);
    
    return unless ($resolved->scheme =~ qr{http|https|ftp|ws|wss});
    
    my $child = $job->child(url => $resolved, literal_uri => $url);
    
    $child->method($method) if $method;
    
    if ($params) {
        if ($method eq 'GET') {
            $child->url->query->append($params);
        } else {
            $child->tx_params($params);
        }
    }
    
    $cb ||= sub { $_[1]->() };
    $cb->($self, sub { $self->enqueue($_[0] || $child) }, $child, $context);
}

sub enqueue {
    my ($self, @jobs) = @_;
    $self->queue->enqueue(WWW::Crawler::Mojo::Job->upgrade($_)) for @jobs;
}

sub requeue {
    my ($self, @jobs) = @_;
    $self->queue->requeue(WWW::Crawler::Mojo::Job->upgrade($_)) for @jobs;
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

=head2 clock_speed

A number of millisecond for main event loop interval. Defaults to 0.25.

    $bot->clock_speed(2);
    my $clock = $bot->clock_speed; # 2

=head2 max_conn

A number of max connections.

    $bot->max_conn(5);
    say $bot->max_conn; # 5

=head2 max_conn_per_host

A number of max connections per host.

    $bot->max_conn_per_host(5);
    say $bot->max_conn_per_host; # 5

=head2 queue

L<WWW::Crawler::Mojo::Queue::Memory> object for default.

    $bot->queue(WWW::Crawler::Mojo::Queue::Memory->new);
    $bot->queue->enqueue($job);

=head2 shuffle

An interval in seconds to shuffle the job queue. It also evalutated as boolean
for disabling/enabling the feature. Defaults to undef, meaning disable.

    $bot->shuffle(5);
    say $bot->shuffle; # 5

=head2 ua

A L<Mojo::UserAgent> instance.

    my $ua = $bot->ua;
    $bot->ua(Mojo::UserAgent->new);

=head2 ua_name

Name of crawler for User-Agent header.

    $bot->ua_name('my-bot/0.01 (+https://example.com/)');
    say $bot->ua_name; # 'my-bot/0.01 (+https://example.com/)'

=head1 EVENTS

L<WWW::Crawler::Mojo> inherits all events from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 res

Emitted when crawler got response from server. The callback takes 4 arguments.

    $bot->on(res => sub {
        my ($bot, $scrape, $job, $res) = @_;
        if (...) {
            $scrape->(sub {
                # called when URL found
            });
        } else {
            # DO NOTHING
        }
    });

=head3 $bot

L<WWW::Crawler::Mojo> instance.

=head3 $scrape

Scraper code reference for current document. The code takes a callback for
argument in case a URL found.

    $scrape(sub {
        my ($bot, $enqueue, $job, $context) = @_;
        ...
    });

=over

=item $bot

L<WWW::Crawler::Mojo> instance.

=item $enqueue

Enqueue code reference for current URL. This is a shorthand of..

    $bot->enqueue($job)

=item $job

L<WWW::Crawler::Mojo::Job> instance.

=item $context

Either L<Mojo::DOM> or L<Mojo::URL> instance.

=back

=head3 $job

L<WWW::Crawler::Mojo::Job> instance.

=head3 $res

L<Mojo::Message::Response> instance.

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

=head2 scrape

Parses and discovers links in a web page. Each links are appended to FIFO array.
This performs scraping.

    $bot->scrape($res, $job, $cb);

=head2 enqueue

Append one or more URLs or L<WWW::Crawler::Mojo::Job> objects.

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

=head1 EXAMPLE

L<https://github.com/jamadam/WWW-Flatten>

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) jamadam

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
