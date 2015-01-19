#!/usr/bin/env perl
use Mojo::Base -strict;
use File::Basename 'dirname';
use File::Spec;
use lib join '/', File::Spec->splitdir(dirname(__FILE__)), '../extlib';
use lib join '/', File::Spec->splitdir(dirname(__FILE__)), '../lib';
use Mojo::IOLoop;
use WWW::Crawler::Mojo::UserAgent;
use Test::More;
use Test::Mojo;

use Test::More tests => 5;

my $ua = WWW::Crawler::Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);

{
    my $id1 = Mojo::IOLoop->server({address => '127.0.0.1'}, sub {
        my ($loop, $stream) = @_;
        $stream->on(read => sub {
            my ($stream, $chunk) = @_;
            like $chunk, qr{Authorization: Basic YTpi}, 'right Authorization header';
            $stream->write(
                "HTTP/1.1 200 OK\x0d\x0a"
                    . "Content-Type: text/html\x0d\x0a\x0d\x0a",
            );
            $stream->close
        });
    });
    
    my $port = Mojo::IOLoop->acceptor($id1)->handle->sockport;
    
    $ua->credentials->{"http://localhost:$port"} = "a:b";
    $ua->get("http://localhost:$port/file1");

    my $id2 = Mojo::IOLoop->server({address => '127.0.0.1'}, sub {
        my ($loop, $stream) = @_;
        $stream->on(read => sub {
            my ($stream, $chunk) = @_;
            unlike $chunk, qr{Authorization: Basic YTpi}, 'right Authorization header';
            $stream->write(
                "HTTP/1.1 200 OK\x0d\x0a"
                    . "Content-Type: text/html\x0d\x0a\x0d\x0a",
            );
            $stream->close;
        });
    });
    
    my $port2 = Mojo::IOLoop->acceptor($id2)->handle->sockport;
    
    $ua->get("http://localhost:$port2/file2");
    $ua->get("http://localhost:$port/file3");

    my $id3 = Mojo::IOLoop->server({address => '127.0.0.1'}, sub {
        my ($loop, $stream) = @_;
        $stream->on(read => sub {
            my ($stream, $chunk) = @_;
            like $chunk, qr{Authorization: Basic YTpi}, 'right Authorization header';
            $stream->write(
                "HTTP/1.1 200 OK\x0d\x0a"
                    . "Content-Type: text/html\x0d\x0a\x0d\x0a",
            );
            $stream->close;
        });
    });
    
    my $port3 = Mojo::IOLoop->acceptor($id3)->handle->sockport;
    
    my $url = Mojo::URL->new("http://localhost:$port3/file2")->userinfo('a:b');
    $ua->get($url);
    $ua->get($url);
}
