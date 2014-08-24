package Mojo::Crawler;
use strict;
use warnings;
use 5.010;
use Mojo::Base -base;
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
has on_refer => sub { sub { shift->() } };
has on_res => sub { sub { shift->() } };
has on_empty => sub { sub { say "Queue is drained out." } };
has on_error => sub { sub { say shift } };
has 'peeking';
has 'peeking_port';
has peeking_max_length => 30000;
has queues => sub { [] };
has 'ua' => sub { Mojo::Crawler::UserAgent->new };
has 'ua_name' => "mojo-crawler/$VERSION (+https://github.com/jamadam/mojo-crawler)";
has wait_per_host => 1;
has 'shuffle';

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->ua->transactor->name($self->ua_name);
    $self->ua->max_redirects(5);
    return $self;
}

sub crawl {
    my ($self) = @_;
    
    my $loop_id = Mojo::IOLoop->recurring(0.25 => sub {
        $self->process_queue(@_);
    });
    
    $self->crawler_loop_id($loop_id);
    
    # notify queue is drained out
    Mojo::IOLoop->recurring(5 => sub {
        if (! scalar @{$self->{queues}}) {
            $self->on_empty->();
        }
    });
    
    # clean up access log per host
    Mojo::IOLoop->recurring(30 => sub {
        for (keys %{$self->host_busyness}) {
            delete $self->host_busyness->{$_}
                if (time() - $self->host_busyness->{$_} > $self->wait_per_host);
        }
    });
    
    if ($self->peeking || $self->peeking_port) {
        # peeking API server
        my $id = Mojo::IOLoop->server({port => $self->peeking_port}, sub {
            $self->peeking_handler(@_);
        });
        $self->peeking_port(Mojo::IOLoop->acceptor($id)->handle->sockport);
    }
    
    if (my $second = $self->shuffle) {
        Mojo::IOLoop->recurring($self->shuffle => sub {
            @{$self->{queues}} = List::Util::shuffle @{$self->{queues}};
        });
    }
    
    $self->say_start;
    
    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

sub process_queue {
    my $self = shift;
    
    return if ($self->active_conn >= $self->max_conn);
    
    my $queue = shift @{$self->{queues}};
    
    return if (!$queue);
    
    if ($self->host_busy($queue->resolved_uri)) {
        unshift(@{$self->{queues}}, $queue);
        return;
    }
    
    ++$self->{active_conn};
    
    $self->ua->get($queue->resolved_uri, sub {
        --$self->{active_conn};
        
        my ($ua, $tx) = @_;
        if (!$tx->res->code) {
            my $msg = ($tx->res->error)
                        ? $tx->res->error->{message} : 'Unknown error';
            my $url = $queue->resolved_uri;
            $self->on_error->("An error occured during crawling $url: $msg");
        } else {
            $self->on_res->(sub {
                $self->discover($tx, $queue);
            }, $queue, $tx);
        }
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

    print <<"EOF" if ($self->peeking_port);
Peeking API is available at following URL
    http://127.0.0.1:@{[ $self->peeking_port ]}/
EOF
    
    print <<"EOF";
----------------------------------------
EOF
}

sub peeking_handler {
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
        
        if ($path =~ qr{^/dumper/(\w+)} && $self->{$1}) {
            my $res = substr(dumper($self->{$1}), 0, $self->peeking_max_length);
            $stream->write("HTTP/1.1 200 OK\n\n");
            $stream->write($res, sub {shift->close});
            return;
        }
        
        $stream->write("HTTP/1.1 404 NOT FOUND\n\nNOT FOUND", sub {shift->close});
    });
}

sub discover {
    my ($self, $tx, $queue) = @_;
    
    return if ($tx->res->code != 200);
    return if ($self->depth && $queue->depth >= $self->depth);
    
    my $base = $tx->req->url->userinfo(undef);;
    my $type = $tx->res->headers->content_type;
    
    if ($type && $type =~ qr{text/(html|xml)} &&
                                (my $base_tag = $tx->res->dom->at('base'))) {
        $base = resolve_href($base, $base_tag->attr('href'));
    }
    
    collect_urls($tx, sub {
        my ($url, $dom) = @_;
        
        return if ($url !~ qr{^(http|https|ftp|ws|wss):});
        
        my $new_queue = Mojo::Crawler::Queue->new(
            resolved_uri    => resolve_href($base, $url),
            literal_uri     => $url,
            parent          => $queue,
        );
        
        $self->on_refer->(sub {
            $self->enqueue($_[0] || $new_queue);
        }, $new_queue, $queue, $dom || $queue->resolved_uri);
    });
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

sub collect_urls {
    my ($tx, $cb) = @_;
    my $res     = $tx->res;
    my $type    = $res->headers->content_type;
    
    if ($type && $type =~ qr{text/(html|xml)}) {
        my $body = Encode::decode(guess_encoding($res) || 'utf-8', $res->body);
        collect_urls_html(Mojo::DOM->new($body), $cb);
    }
    
    if ($type && $type =~ qr{text/css}) {
        my $encode  = guess_encoding_css($res) || 'utf-8';
        my $body    = Encode::decode($encode, $res->body);
        collect_urls_css($body, $cb);
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
    if (! $charset) {
        $charset = ($res->body =~ qr{^\s*\@charset ['"](.+?)['"];}is)[0];
    }
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
    if (! ref $base) {
        $base = Mojo::URL->new($base);
    }
    my $new = $base->clone;
    my $temp = Mojo::URL->new($href);
    
    $temp->fragment(undef);
    if ($temp->scheme) {
        return $temp->to_string;
    }
    
    if ($temp->path->to_string) {
        $new->path($temp->path->to_string);
        $new->path->canonicalize;
    }
    
    if ($temp->host) {
        $new->host($temp->host);
    }
    if ($temp->port) {
        $new->port($temp->port);
    }
    $new->query($temp->query);
    while ($new->path->parts->[0] && $new->path->parts->[0] =~ /^\./) {
        shift @{$new->path->parts};
    }
    return $new->to_string;
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

Mojo::Crawler - 

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) jamadam

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
