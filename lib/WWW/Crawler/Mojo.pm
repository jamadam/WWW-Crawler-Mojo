package WWW::Crawler::Mojo;
use strict;
use warnings;
use 5.010;
use Mojo::Base 'Mojo::EventEmitter';
use WWW::Crawler::Mojo::Queue;
use WWW::Crawler::Mojo::UserAgent;
use Mojo::Message::Request;
use Mojo::Util qw{md5_sum xml_escape dumper};
use List::Util;
our $VERSION = '0.01';

has active_conn => 0;
has 'crawler_loop_id';
has depth => 10;
has fix => sub { {} };
has active_conns_per_host => sub { {} };
has max_conn => 1;
has max_conn_per_host => 1;
has 'peeping';
has 'peeping_port';
has peeping_max_length => 30000;
has queues => sub { [] };
has 'ua' => sub { WWW::Crawler::Mojo::UserAgent->new };
has 'ua_name' =>
    "www-crawler-mojo/$VERSION (+https://github.com/jamadam/www-crawler-mojo)";
has 'shuffle';

sub crawl {
    my ($self) = @_;
    
    $self->init;
    
    die 'No queue is given' if (! scalar @{$self->queues});
    
    $self->emit('start');
    
    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

sub init {
    my ($self) = @_;
    
    $self->on('empty', sub { say "Queue is drained out." })
                                        unless $self->has_subscribers('empty');
    $self->on('error', sub { say $_[1] })
                                        unless $self->has_subscribers('error');
    $self->on('res', sub { $_[1]->() })
                                        unless $self->has_subscribers('res');
    $self->on('refer', sub { $_[1]->() })
                                        unless $self->has_subscribers('refer');
    
    $self->ua->transactor->name($self->ua_name);
    $self->ua->max_redirects(5);
    
    my $loop_id = Mojo::IOLoop->recurring(0.25 => sub {
        $self->process_queue(@_);
    });
    
    $self->crawler_loop_id($loop_id);
    
    # notify queue is drained out
    Mojo::IOLoop->recurring(5 => sub {
        $self->emit('empty') if (! scalar @{$self->{queues}});
    });
    
    if ($self->peeping || $self->peeping_port) {
        # peeping API server
        my $id = Mojo::IOLoop->server({port => $self->peeping_port}, sub {
            $self->peeping_handler(@_);
        });
        $self->peeping_port(Mojo::IOLoop->acceptor($id)->handle->sockport);
    }
    
    if ($self->shuffle) {
        Mojo::IOLoop->recurring($self->shuffle => sub {
            @{$self->{queues}} = List::Util::shuffle @{$self->{queues}};
        });
    }
}

sub process_queue {
    my $self = shift;
    
    return unless ($self->{queues}->[0] &&
                $self->_mod_busyness($self->{queues}->[0]->resolved_uri, 1));
    
    my $queue = shift @{$self->{queues}};
    my $uri = $queue->resolved_uri;
    my $ua = $self->ua;
    my $tx = $ua->build_tx($queue->method => $uri => $queue->tx_params);
    
    $ua->start($tx, sub {
        $self->_mod_busyness($uri, -1);
        
        my ($ua, $tx) = @_;
        
        $queue->redirect(_urls_redirect($tx));
        
        my $res = $tx->res;
        
        if (!$res->code) {
            my $msg = ($res->error) ? $res->error->{message} : 'Unknown error';
            my $url = $queue->resolved_uri;
            $self->emit('error',
                        "An error occured during crawling $url: $msg", $queue);
            return;
        }
        
        $self->emit('res', sub { $self->discover($res, $queue) }, $queue, $res);
    });
}

sub say_start {
    my $self = shift;
    
    print <<"EOF";
----------------------------------------
Crawling is starting with @{[ $self->queues->[0]->resolved_uri ]}
Max Connection  : @{[ $self->max_conn ]}
Depth           : @{[ $self->depth ]}
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
        
        if ($path =~ qr{^/queues}) {
            my $res = sprintf('%s Queues are left.', scalar @{$self->queues});
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

sub discover {
    my ($self, $res, $queue) = @_;
    
    return if ($res->code != 200);
    return if ($self->depth && $queue->depth >= $self->depth);
    
    my $base = $queue->resolved_uri;
    my $type = $res->headers->content_type;
    
    if ($type && $type =~ qr{text/(html|xml)} &&
                                (my $base_tag = $res->dom->at('base'))) {
        $base = resolve_href($base, $base_tag->attr('href'));
    }
    
    my $cb = sub {
        my ($url, $dom) = @_;
        
        $url = Mojo::URL->new($url);
        
        return unless
                (!$url->scheme || $url->scheme =~ qr{http|https|ftp|ws|wss});
        
        my $child = $queue->child(
            resolved_uri => resolve_href($base, $url), literal_uri => $url);
        
        $self->emit('refer', sub {
            $self->enqueue($_[0] || $child);
        }, $child, $dom || $queue->resolved_uri);
    };
    
    if ($type && $type =~ qr{text/(html|xml)}) {
        my $encode = guess_encoding($res) || 'utf-8';
        my $body = Encode::decode($encode, $res->body);
        collect_urls_html(Mojo::DOM->new($body), $cb);
    }
    
    if ($type && $type =~ qr{text/css}) {
        my $encode  = guess_encoding_css($res) || 'utf-8';
        my $body    = Encode::decode($encode, $res->body);
        collect_urls_css($body, $cb);
    }
};

sub enqueue {
    my ($self, @queues) = @_;
    
    for (@queues) {
        $_ = WWW::Crawler::Mojo::Queue->new(resolved_uri => $_)
                    unless (ref $_ && ref $_ eq 'WWW::Crawler::Mojo::Queue');
        
        my $md5 = md5_sum($_->resolved_uri);
        
        if (!exists $self->fix->{$md5}) {
            $self->fix->{$md5} = undef;
            push(@{$self->{queues}}, $_);
        }
    }
}

our %tag_attributes = (
    script  => ['src'],
    link    => ['href'],
    a       => ['href'],
    img     => ['src'],
    area    => ['href', 'ping'],
    embed   => ['src'],
    frame   => ['src'],
    iframe  => ['src'],
    input   => ['src'],
    object  => ['data'],
    form    => ['action'],
);

sub collect_urls_html {
    my ($dom, $cb) = @_;
    
    $dom->find(join(',', keys %tag_attributes))->each(sub {
        my $dom = shift;
        for (@{$tag_attributes{$dom->type}}) {
            $cb->($dom->{$_}, $dom) if ($dom->{$_});
        }
    });
    $dom->find('meta[http\-equiv=Refresh]')->each(sub {
        my $dom = shift;
        if (my $href = $dom->{content} && ($dom->{content} =~ qr{URL=(.+)}i)[0]) {
            $cb->($href, $dom);
        }
    });
    $dom->find('style')->each(sub {
        my $dom = shift;
        collect_urls_css($dom->content || '', sub { $cb->(shift, $dom) });
    });
    $dom->find('*[style]')->each(sub {
        my $dom = shift;
        collect_urls_css($dom->{style}, sub { $cb->(shift, $dom) });
    });
}

sub collect_urls_css {
    my ($str, $cb) = @_;
    $str =~ s{/\*.+?\*/}{}gs;
    my @urls = ($str =~ m{url\(['"]?(.+?)['"]?\)}g);
    $cb->($_) for (@urls);
}

my $charset_re = qr{\bcharset\s*=\s*['"]?([a-zA-Z0-9_\-]+)['"]?}i;

sub guess_encoding_css {
    my $res     = shift;
    my $type    = $res->headers->content_type;
    my $charset = ($type =~ $charset_re)[0];
    $charset =
        ($res->body =~ qr{^\s*\@charset ['"](.+?)['"];}is)[0] if (! $charset);
    return $charset;
}

sub guess_encoding {
    my $res     = shift;
    my $type    = $res->headers->content_type;
    my $charset = ($type =~ $charset_re)[0];
    if (! $charset && (my $head = ($res->body =~ qr{<head>(.+)</head>}is)[0])) {
        Mojo::DOM->new($head)->find('meta[http\-equiv=Content-Type]')->each(sub{
            $charset = (shift->{content} =~ $charset_re)[0];
        });
    }
    return $charset;
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
    unshift(@urls, $tx->req->url->userinfo(undef)->to_string);
    return @urls;
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
    my $uri = ref $_[0] ? $_[0] : Mojo::URL->new($_[0]);
    my $key = $uri->scheme. '://'. $uri->ihost;
    
    if (my $port = $uri->port) {
        if (($uri->scheme eq 'https' && $port != 443) ||
                                    ($uri->scheme eq 'http' && $port != 80)) {
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
    use utf8;
    use WWW::Crawler::Mojo;
    use 5.10.0;
    
    my $bot = WWW::Crawler::Mojo->new;
    my %count;
    
    $bot->on(res => sub {
        my ($bot, $discover, $queue, $res) = @_;
        
        $count{$res->code}++;
        
        if ($res->code == 404) {
            say sprintf('404 occured! : %s referred by %s',
                        $queue->resolved_uri, $queue->referrer->resolved_uri);
        }
        
        my @disp_seed;
        push(@disp_seed, sprintf('%s:%s', $_, $count{$_})) for (keys %count);
        
        $| = 1;
        print(join(' / ', @disp_seed), ' ' x 30);
        print("\r");
        
        $discover->();
    });
    
    $bot->on(refer => sub {
        my ($bot, $enqueue, $queue, $context) = @_;
        $enqueue->();
    });
    
    $bot->enqueue('http://example.com/');
    $bot->peeping_port(3001);
    $bot->crawl;

=head1 DESCRIPTION

WWW::Crawler::Mojo is a web crawling framework for those who familier with
Mojo::* APIs.

=head1 ATTRIBUTE

WWW::Crawler::Mojo inherits all attributes from Mojo::EventEmitter and
implements the following new ones.

=head2 ua

A Mojo::UserAgent instance.

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

=head2 depth

A number of max depth to crawl. Note that the depth is the number of HTTP
requests to get to URI starting with the first queue. This doesn't mean the
deepness of URI path detected with slash.

    $bot->depth(5);
    say $bot->depth; # 5

=head2 max_conn

A number of max connections.

    $bot->max_conn(5);
    say $bot->max_conn; # 5

=head2 max_conn_per_host

A number of max connections per host.

    $bot->max_conn_per_host(5);
    say $bot->max_conn_per_host; # 5

=head2 peeping_max_length

Max length of peeping API content.

    $bot->peeping_max_length(100000);
    say $bot->peeping_max_length; # 100000

=head2 queues

FIFO array contains WWW::Crawler::Mojo::Queue objects.

    push(@{$bot->queues}, WWW::Crawler::Mojo::Queue->new(...));
    my $queue = shift @{$bot->queues};

=head1 EVENTS

WWW::Crawler::Mojo inherits all events from Mojo::EventEmitter and implements
the following new ones.

=head2 res

Emitted when crawler got response from server.

    $bot->on(res => sub {
        my ($bot, $discover, $queue, $res) = @_;
        if (...) {
            $discover->();
        } else {
            # DO NOTHING
        }
    });

=head2 refer

Emitted when new URI is found. You can enqueue the URI conditionally with
the callback.

    $bot->on(refer => sub {
        my ($bot, $enqueue, $queue, $context) = @_;
        if (...) {
            $enqueue->();
        } elseif (...) {
            $enqueue->(...); # maybe different url
        } else {
            # DO NOTHING
        }
    });

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
        my ($bot, $error, $queue) = @_;
        say "error: $_[1]";
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

WWW::Crawler::Mojo inherits all methods from Mojo::EventEmitter and implements
the following new ones.

=head2 crawl

Start crawling loop.

    $bot->crawl;

=head2 init

Initialize crawler settings.

    $bot->init;

=head2 process_queue

Process a queue.

    $bot->process_queue;

=head2 say_start

Displays starting messages to STDOUT

    $bot->say_start;

=head2 peeping_handler

peeping API dispatcher.

    $bot->peeping_handler($loop, $stream);

=head2 discover

Parses and discovers links in a web page. Each links are appended to FIFO array.

    $bot->discover($res, $queue);

=head2 enqueue

Append a queue with a URI or WWW::Crawler::Mojo::Queue object.

    $bot->enqueue($queue);

=head2 collect_urls_html

Collects URLs out of HTML.

    WWW::Crawler::Mojo::collect_urls_html($dom, sub {
        my ($uri, $dom) = @_;
    });

=head2 collect_urls_css

Collects URLs out of CSS.

    WWW::Crawler::Mojo::collect_urls_css($dom, sub {
        my $uri = shift;
    });

=head2 guess_encoding_css

Guesses encoding of CSS

    WWW::Crawler::Mojo::guess_encoding_css($res)

=head2 guess_encoding

Guesses encoding of HTML

    WWW::Crawler::Mojo::guess_encoding($res)

=head2 resolve_href

Resolves URLs with a base URL.

    WWW::Crawler::Mojo::resolve_href($base, $uri);

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) jamadam

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
