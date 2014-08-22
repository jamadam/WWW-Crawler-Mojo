package Mojo::Crawler;
use strict;
use warnings;
use 5.010;
use Mojo::Base 'Mojo::IOLoop';
use Mojo::Crawler::Queue;
use Mojo::UserAgent;
use Mojo::Message::Request;
use Mojo::Util qw{md5_sum xml_escape dumper};
use Socket qw(inet_ntoa inet_aton);
our $VERSION = '0.01';

has conn_max => 4;
has conn_active => 0;
has 'crawler_loop_id';
has credentials => sub { {} };
has depth => 10;
has fix => sub { {} };
has host_busyness => sub { {} };
has wait_per_host => 1;
has keep_credentials => 1;
has on_refer => sub { sub { shift->() } };
has on_res => sub { sub { shift->() } };
has on_empty => sub {
    sub {
        say "Queue is drained out.";
    }
};
has on_error => sub {
    sub {
        say shift;
    }
};
has 'peeking_port';
has queues => sub { [] };
has 'ua';
has 'ua_name' => "mojo-crawler/$VERSION (+https://github.com/jamadam/mojo-crawler)";

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    
    my $ua = Mojo::UserAgent->new;
    $self->ua($ua);
    $ua->transactor->name($self->ua_name);
    $ua->max_redirects(5);
    
    if ($self->keep_credentials) {
        $ua->on(start => sub {
            my ($ua, $tx) = @_;
            my $url = $tx->req->url;
            if ($url->is_abs) {
                my $key = $url->scheme. '://'. $url->host. ':'. ($url->port || 80);
                if ($url->userinfo) {
                    $self->credentials->{$key} = $url->userinfo;
                } else {
                    $url->userinfo($self->credentials->{$key});
                }
            }
        });
    }
    
    return $self;
}

sub crawl {
    my ($self) = @_;
    
    my $loop_id = Mojo::IOLoop->recurring(0 => sub {
        
        for ($self->conn_active + 1 .. $self->conn_max) {
            
            my $queue = shift @{$self->{queues}};
            
            return if (!$queue);
            
            if ($self->host_busy($queue->resolved_uri)) {
                unshift(@{$self->{queues}}, $queue);
                return;
            }
            
            ++$self->{conn_active};
            
            $self->ua->get($queue->resolved_uri, sub {
                --$self->{conn_active};
                
                my ($ua, $tx) = @_;
                if ($tx->res->error) {
                    my $msg = $tx->res->error->{message};
                    my $url = $queue->resolved_uri;
                    $self->on_error->("An error occured during crawling $url: $msg");
                } else {
                    $self->on_res->(sub {
                        $self->discover($tx, $queue);
                    }, $queue, $tx);
                }
            });
        }
    });
    
    $self->crawler_loop_id($loop_id);
    
    Mojo::IOLoop->recurring(5 => sub {
        if (! scalar @{$self->{queues}}) {
            $self->on_empty->();
        }
    });
    
    if ($self->peeking_port) {
        Mojo::IOLoop->server({port => $self->peeking_port} => sub {
            $self->peeking_handler(@_);
        });
    }
    
    Mojo::IOLoop->start;
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
            $stream->write("HTTP/1.1 200 OK\n\n");
            $stream->write(dumper($self->{$1}), sub {shift->close});
            return;
        }
        
        $stream->write("HTTP/1.1 404 OK\n\nNOT FOUND", sub {shift->close});
    });
}

sub discover {
    my ($self, $tx, $queue) = @_;
    
    return if ($tx->res->code != 200);
    return if ($self->depth && $queue->depth >= $self->depth);
    
    my $base;
    my $type = $tx->res->headers->content_type;
    
    if ($type && $type =~ qr{text/(html|xml)} &&
                                (my $base_tag = $tx->res->dom->at('base'))) {
        $base = $base_tag->attr('href');
    } else {
        # TODO Is this OK for redirected urls?
        $base = $tx->req->url->userinfo(undef);
    }
    
    collect_urls($tx, sub {
        my ($newurl, $dom) = @_;
        
        if ($newurl =~ qr{^(\w+):} &&
                    ! grep {$_ eq $1} qw(http https ftp ws wss)) {
            return;
        }
        
        $newurl = resolve_href($base, $newurl);
        
        my $new_queue = Mojo::Crawler::Queue->new(
            resolved_uri    => $newurl,
            literal_uri     => $newurl,
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
            $_ = Mojo::Crawler::Queue->new(literal_uri => $_, resolved_uri => $_);
        }
        my $md5 = md5_sum($_->resolved_uri);
        
        if (! exists $self->fix->{$md5}) {
            
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
        my $dom = Mojo::DOM->new($body);
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

### ---
### Guess encoding for CSS
### ---
sub guess_encoding_css {
    my $res     = shift;
    my $type    = $res->headers->content_type;
    my $charset = ($type =~ qr{; ?charset=([^;\$]+)})[0];
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
    my $charset = ($type =~ qr{; ?charset=([^;\$]+)})[0];
    if (! $charset && (my $head = ($res->body =~ qr{<head>(.+)</head>}is)[0])) {
        my $dom = Mojo::DOM->new($head);
        $dom->find('meta[http\-equiv=Content-Type]')->each(sub{
            my $meta_dom = shift;
            $charset = ($meta_dom->{content} =~ qr{; ?charset=([^;\$]+)})[0];
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
    my $key = inet_ntoa(inet_aton($host)) || $host;
    my $now = time();
    my $last = $self->host_busyness->{$key};
    return 1 if ($last && $now - $last < $self->wait_per_host);
    $self->host_busyness->{$key} = $now;
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
