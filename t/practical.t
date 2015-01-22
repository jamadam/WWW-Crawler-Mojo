use strict;
use warnings;
use Test::More;
use Test::Mojo;
use utf8;
use Data::Dumper;
use Mojo::IOLoop;
use WWW::Crawler::Mojo;

use Test::More tests => 29;

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
my $bot = WWW::Crawler::Mojo->new;
$bot->enqueue(WWW::Crawler::Mojo::resolve_href($base, '/index.html'));

my %urls;
my %contexts;

$bot->on('res' => sub {
    my ($bot, $browse, $job, $res) = @_;
    $browse->();
    $urls{$job->resolved_uri} = $job;
    Mojo::IOLoop->stop if (! scalar @{$bot->queue});
});
$bot->on('refer' => sub {
    my ($bot, $enqueue, $job, $context) = @_;
    $enqueue->();
    $contexts{$job} = $context;
});

$bot->init;

Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

is((scalar keys %urls), 8, 'right length');

my $q;
$q = $urls{WWW::Crawler::Mojo::resolve_href($base, '/index.html')};
is $q->depth, 0;
is $q->referrer, '';
is $contexts{$q}, undef;
my $parent = $q;
$q = $urls{WWW::Crawler::Mojo::resolve_href($base, '/js/js1.js')};
is $q->depth, 1;
is $q->referrer, $parent;
is ref $contexts{$q}, 'Mojo::DOM';
is $contexts{$q},
    qq{<script src="./js/js1.js" type="text/javascript"></script>};
$q = $urls{WWW::Crawler::Mojo::resolve_href($base, '/css/css1.css')};
is $q->depth, 1;
is $q->referrer, $parent;
is ref $contexts{$q}, 'Mojo::DOM';
is $contexts{$q},
    qq{<link href="./css/css1.css" rel="stylesheet" type="text/css">};
my $parent2 = $q;
$q = $urls{WWW::Crawler::Mojo::resolve_href($base, '/img/png1.png')};
is $q->depth, 1;
is $q->referrer, $parent;
is ref $contexts{$q}, 'Mojo::DOM';
is $contexts{$q}, qq{<img alt="png1" src="./img/png1.png">};
$q = $urls{WWW::Crawler::Mojo::resolve_href($base, '/img/png2.png')};
is $q->depth, 2;
is $q->referrer, $parent2;
is ref $contexts{$q}, 'Mojo::URL';
is $contexts{$q}, qq{http://127.0.0.1:$port/css/css1.css};
$q = $urls{WWW::Crawler::Mojo::resolve_href($base, '/img/png3.png')};
is $q->depth, 1;
is $q->referrer, $parent;
is ref $contexts{$q}, 'Mojo::DOM';
like $contexts{$q},
    qr{<div style="background-image:url\(\./img/png3.png\)">.+</div>}s;
$q = $urls{WWW::Crawler::Mojo::resolve_href($base, '/space.txt')};
is $q->depth, 1;
is $q->referrer, $parent;
is ref $contexts{$q}, 'Mojo::DOM';
like $contexts{$q}, qr{<a href=" ./space.txt ">foo</a>}s;

$daemon->stop;
$base = Mojo::URL->new("http://127.0.0.1:$port");
$bot = WWW::Crawler::Mojo->new;
$bot->ua->request_timeout(0.1);
$bot->enqueue(WWW::Crawler::Mojo::resolve_href($base, '/'));
my $timeout;
$bot->on('error' => sub { $timeout = 1; Mojo::IOLoop->stop });
$bot->init;
Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
is $timeout, 1, 'error event fired';

__END__
