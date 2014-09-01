package Mojo::Crawler;
use strict;
use warnings;
use 5.010;
use Mojo::Base 'Mojo::EventEmitter';
use Mojo::Crawler::Queue;
use Mojo::Crawler::UserAgent;
use Mojo::Message::Request;
use Mojo::Util qw{md5_sum xml_escape dumper};
use List::Util;
our $VERSION = '0.01';

has active_conn => 0;
has 'crawler_loop_id';
has depth => 10;
has fix => sub { {} };
has host_busyness => sub { {} };
has max_conn => 1;
has 'peeping';
has 'peeping_port';
has peeping_max_length => 30000;
has queues => sub { [] };
has 'ua' => sub { Mojo::Crawler::UserAgent->new };
has 'ua_name' => "mojo-crawler/$VERSION (+https://github.com/jamadam/mojo-crawler)";
has wait_per_host => 1;
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
    
    if ($self->wait_per_host) {
        # clean up access log per host
        Mojo::IOLoop->recurring(30 => sub {
            for (keys %{$self->host_busyness}) {
                delete $self->host_busyness->{$_}
                    if (time() -
                            $self->host_busyness->{$_} > $self->wait_per_host);
            }
        });
    }
    
    if ($self->peeping || $self->peeping_port) {
        # peeping API server
        my $id = Mojo::IOLoop->server({port => $self->peeping_port}, sub {
            $self->peeping_handler(@_);
        });
        $self->peeping_port(Mojo::IOLoop->acceptor($id)->handle->sockport);
    }
    
    if (my $second = $self->shuffle) {
        Mojo::IOLoop->recurring($self->shuffle => sub {
            @{$self->{queues}} = List::Util::shuffle @{$self->{queues}};
        });
    }
}

sub process_queue {
    my $self = shift;
    
    return if ($self->active_conn >= $self->max_conn);
    
    my $queue = shift @{$self->{queues}};
    
    return if (!$queue);
    
    if ($self->wait_per_host && $self->host_busy($queue->resolved_uri)) {
        unshift(@{$self->{queues}}, $queue);
        return;
    }
    
    ++$self->{active_conn};
    
    $self->ua->get($queue->resolved_uri, sub {
        --$self->{active_conn};
        
        my ($ua, $tx) = @_;
        
        $queue->redirect(urls_redirect($tx));
        
        my $res = $tx->res;
        
        if (!$res->code) {
            my $msg = ($res->error) ? $res->error->{message} : 'Unknown error';
            my $url = $queue->resolved_uri;
            $self->emit('error',
                        "An error occured during crawling $url: $msg", $queue);
        } else {
            $self->emit('res', sub {
                $self->discover($res, $queue);
            }, $queue, $res);
        }
    });
}

sub urls_redirect {
    my $tx = shift;
    my @urls;
    @urls = urls_redirect($tx->previous) if ($tx->previous);
    unshift(@urls, $tx->req->url->userinfo(undef)->to_string);
    return @urls;
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
        
        if ($url =~ qr{^(\w+):} &&! grep {$_ eq $1} qw(http https ftp ws wss)) {
            return;
        }
        
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
        unless (ref $_ && ref $_ eq 'Mojo::Crawler::Queue') {
            $_ = Mojo::Crawler::Queue->new(resolved_uri => $_);
        }
        my $md5 = md5_sum($_->resolved_uri);
        
        if (!exists $self->fix->{$md5}) {
            $self->fix->{$md5} = undef;
            push(@{$self->{queues}}, $_);
        }
    }
}

### ---
### Collect URLs
### ---
sub collect_urls_html {
    my ($dom, $cb) = @_;
    
    $dom->find('script, link, a, img, area, embed, frame, iframe, input,
                                    meta[http\-equiv=Refresh]')->each(sub {
        my $dom = shift;
        if (my $href = $dom->{href} || $dom->{src} ||
            $dom->{content} && ($dom->{content} =~ qr{URL=(.+)}i)[0]) {
            $cb->($href, $dom);
        }
    });
    $dom->find('form')->each(sub {
        my $dom = shift;
        if (my $href = $dom->{action}) {
            $cb->($href, $dom);
        }
    });
    $dom->find('style')->each(sub {
        my $dom = shift;
        collect_urls_css($dom->content || '', sub {
            my $href = shift;
            $cb->($href, $dom);
        });
    });
    $dom->find('*[style]')->each(sub {
        my $dom = shift;
        collect_urls_css($dom->{style}, sub {
            my $href = shift;
            $cb->($href, $dom);
        });
    });
}

### ---
### Collect URLs from CSS
### ---
sub collect_urls_css {
    my ($str, $cb) = @_;
    $str =~ s{/\*.+?\*/}{}gs;
    my @urls = ($str =~ m{url\(['"]?(.+?)['"]?\)}g);
    $cb->($_) for (@urls);
}

my $charset_re = qr{\bcharset\s*=\s*['"]?([a-zA-Z0-9_\-]+)['"]?}i;

### ---
### Guess encoding for CSS
### ---
sub guess_encoding_css {
    my $res     = shift;
    my $type    = $res->headers->content_type;
    my $charset = ($type =~ $charset_re)[0];
    $charset =
        ($res->body =~ qr{^\s*\@charset ['"](.+?)['"];}is)[0] if (! $charset);
    return $charset;
}

### ---
### Guess encoding
### ---
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

### ---
### Resolve href
### ---
sub resolve_href {
    my ($base, $href) = @_;
    $href = Mojo::URL->new(ref $href ? $href : Mojo::URL->new($href));
    $base = Mojo::URL->new(ref $base ? $base : Mojo::URL->new($base));
    my $abs = $href->to_abs($base)->fragment(undef);
    while ($abs->path->parts->[0] && $abs->path->parts->[0] =~ /^\./) {
        shift @{$abs->path->parts};
    }
    $abs->path->trailing_slash($base->path->trailing_slash) if (!$href->path->to_string);
    return $abs;
}

sub host_busy {
    my ($self, $uri) = @_;
    my $host = ($uri =~ qr{^\w+://([^/]+)})[0];
    my $now = time();
    my $last = $self->host_busyness->{$host};
    return 1 if ($last && $now - $last < $self->wait_per_host);
    $self->host_busyness->{$host} = $now;
    return;
}

1;

=head1 NAME

Mojo::Crawler - A web crawling framework for Perl

=head1 SYNOPSIS

    use strict;
    use warnings;
    use utf8;
    use Mojo::Crawler;
    use 5.10.0;
    
    my $bot = Mojo::Crawler->new;
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

Mojo-Crawler is a web crawling framework for Perl.

=head1 ATTRIBUTE

Mojo::Crawler inherits all attributes from Mojo::EventEmitter and implements the
following new ones.

=head2 active_conn

A number of current connections.

=head2 depth

A number of max depth to crawl.

=head2 fix

=head2 host_busyness

A hash contains host name for key and last requested timestamp for value.

=head2 max_conn

A number of Max connections.

=head2 peeping_max_length

Max length of peeping API content.

=head2 queues

FIFO array contains Mojo::Crawler::Queue objects.

=head2 wait_per_host

Interval in second of requests per hosts, not to rush the server.

=head1 EVENTS

Mojo::Crawler inherits all events from Mojo::EventEmitter and implements the
following new ones.

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

Emitted when new URI is found. You can enqueue new URIs conditionally with the callback.

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

Emitted when queue length got zero. The length is checked every 5 second.

    $bot->on(refer => sub {
        say "Queue is drained out.";
    });

=head2 error

Emitted when user agent returns no status code for request. Possibly causeed by
network errors or un-responsible servers.

    $bot->on(refer => sub {
        say "error: $_[1]";
    });

Note that server errors such as 404 or 500 cannot be catched with the event.
Consider res event for the use case instead of this.

=head1 METHODS

Mojo::Crawler inherits all methods from Mojo::EventEmitter and implements the
following new ones.

=head2 crawl

Start crawling loop.

=head2 init

Initialize crawler settings.

=head2 process_queue

Process a queue.

=head2 urls_redirect

Replace the resolved URI of queue and append redirect history into queue

=head2 say_start

Displays starting messages to STDOUT

=head2 peeping_handler

peeping API dispatcher.

=head2 discover

Parses and discovers lins in a web page.

=head2 enqueue

Append a queue with a URI or Mojo::Crawler::Queue object.

=head2 collect_urls_html

Collects URLs out of HTML.

=head2 collect_urls_css

Collects URLs out of CSS.

=head2 guess_encoding_css

Guesses encoding of CSS

=head2 guess_encoding

Guesses encoding of HTML

=head2 resolve_href

Resolves URLs with a base URL.

=head2 host_busy

Checks wether a host is ready or not for crawl.

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) jamadam

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
