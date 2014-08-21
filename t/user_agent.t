use strict;
use warnings;
use lib './lib', './extlib';
use Test::More;
use Test::Mojo;
use utf8;
use Data::Dumper;
use Mojo::IOLoop;
use Mojolicious::Lite;
use MojoCheckbot;

use Test::More tests => 1;

my $loop = Mojo::IOLoop->new;
my $ua = Mojo::UserAgent->new(ioloop => $loop);
$ua->inactivity_timeout(1);
my $port1 = Mojo::IOLoop::Server->generate_port;
$loop->server(port => $port1, sub {
    my ($loop, $stream) = @_;
    $stream->on(read => sub {
        my ($stream, $chunk) = @_;
        $stream->write(
            "HTTP/1.1 200 OK\x0d\x0a"
                . "Content-Type: text/html\x0d\x0a\x0d\x0abody1",
            sub {shift->close }
        );
    });
});
my $port2 = Mojo::IOLoop::Server->generate_port;
$loop->server(port => $port2, sub {
    my ($loop, $stream) = @_;
    $stream->on(read => sub {
        my ($stream, $chunk) = @_;
        $stream->write(
            "HTTP/1.1 202 OK\x0d\x0a"
                . "Content-Type: text/html\x0d\x0a\x0d\x0abody2",
            sub {shift->close }
        );
    });
});

my $tx = $ua->get("http://127.0.0.1:$port1");
warn $tx->res->code;
warn $tx->res->body;
$tx = $ua->get("http://127.0.0.1:$port2");
warn $tx->res->code;
warn $tx->res->body;
$tx = $ua->get("http://127.0.0.1:$port1");
warn $tx->res->code;
warn $tx->res->body;
use Data::Dumper;
warn Dumper($tx->res);
1;

__END__

