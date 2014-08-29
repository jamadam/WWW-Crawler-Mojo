use strict;
use warnings;
use Test::More;
use Test::Mojo;
use utf8;
use Data::Dumper;
use Mojo::IOLoop;
use Mojo::Crawler;

use Test::More tests => 23;

{
    package MockServer;
    use Mojo::Base 'Mojolicious';
    
    sub startup {
        my $self = shift;
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
$bot->on('refer' => sub {
    my ($bot, $enqueue, $queue, $context) = @_;
    $enqueue->();
    $queue->add_props(
        context => $context,
    );
});

$bot->init;

Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

my $q;
$q = $urls{Mojo::Crawler::resolve_href($base, '/index.html')};
is $q->depth, 0;
is $q->referrer, '';
is $q->additional_props->{context}, undef;
my $parent = $q;
$q = $urls{Mojo::Crawler::resolve_href($base, '/js/js1.js')};
is $q->depth, 1;
is $q->referrer, $parent;
is ref $q->additional_props->{context}, 'Mojo::DOM';
is $q->additional_props->{context},
    qq{<script src="./js/js1.js" type="text/javascript"></script>};
$q = $urls{Mojo::Crawler::resolve_href($base, '/css/css1.css')};
is $q->depth, 1;
is $q->referrer, $parent;
is ref $q->additional_props->{context}, 'Mojo::DOM';
is $q->additional_props->{context},
    qq{<link href="./css/css1.css" rel="stylesheet" type="text/css">};
my $parent2 = $q;
$q = $urls{Mojo::Crawler::resolve_href($base, '/img/png1.png')};
is $q->depth, 1;
is $q->referrer, $parent;
is ref $q->additional_props->{context}, 'Mojo::DOM';
is $q->additional_props->{context},
    qq{<img alt="png1" src="./img/png1.png">};
$q = $urls{Mojo::Crawler::resolve_href($base, '/img/png2.png')};
is $q->depth, 2;
is $q->referrer, $parent2;
is ref $q->additional_props->{context}, '';
is $q->additional_props->{context},
    qq{http://127.0.0.1:$port/css/css1.css};
$q = $urls{Mojo::Crawler::resolve_href($base, '/img/png3.png')};
is $q->depth, 1;
is $q->referrer, $parent;
is ref $q->additional_props->{context}, 'Mojo::DOM';
like $q->additional_props->{context},
    qr{<div style="background-image:url\(\./img/png3.png\)">.+</div>}s;

__END__
