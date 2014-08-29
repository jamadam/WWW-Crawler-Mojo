use strict;
use warnings;
use Test::More;
use Test::Mojo;
use utf8;
use Data::Dumper;
use Mojo::IOLoop;
use Mojo::Crawler;

use Test::More tests => 12;

{
    package MockServer;
    use Mojo::Base 'Mojolicious';
    
    sub startup {
        my $self = shift;
        $self->log->level('fatal');
        unshift @{$self->static->paths}, $self->home->rel_dir('public');
    }
}

my $daemon = Mojo::Server::Daemon->new(
    app    => MockServer->new,
    ioloop => Mojo::IOLoop->singleton,
    silent => 1
);

$daemon->listen(['http://127.0.0.1'])->start;

my $port = Mojo::IOLoop->acceptor($daemon->acceptors->[0])->handle->sockport;
my $base = Mojo::URL->new("http://127.0.0.1:$port");
my $bot = Mojo::Crawler->new;
$bot->enqueue(Mojo::Crawler::resolve_href($base, '/index.html'));

my %urls;

$bot->on('res' => sub {
    my ($bot, $discover, $queue, $res) = @_;
    $discover->();
    $urls{$queue->resolved_uri} = $queue;
    Mojo::IOLoop->stop if (! scalar @{$bot->queues});
});

$bot->init;

Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

my $q;
$q = $urls{Mojo::Crawler::resolve_href($base, '/index.html')};
is $q->depth, 0;
is $q->referrer, '';
my $parent = $q;
$q = $urls{Mojo::Crawler::resolve_href($base, '/js/js1.js')};
is $q->depth, 1;
is $q->referrer, $parent;
$q = $urls{Mojo::Crawler::resolve_href($base, '/css/css1.css')};
is $q->depth, 1;
is $q->referrer, $parent;
my $parent2 = $q;
$q = $urls{Mojo::Crawler::resolve_href($base, '/img/png1.png')};
is $q->depth, 1;
is $q->referrer, $parent;
$q = $urls{Mojo::Crawler::resolve_href($base, '/img/png2.png')};
is $q->depth, 2;
is $q->referrer, $parent2;
$q = $urls{Mojo::Crawler::resolve_href($base, '/img/png3.png')};
is $q->depth, 1;
is $q->referrer, $parent;

__END__

