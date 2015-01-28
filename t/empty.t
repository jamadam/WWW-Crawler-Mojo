use strict;
use warnings;
use Test::More;
use Test::Mojo;
use utf8;
use Data::Dumper;
use Mojo::IOLoop;
use WWW::Crawler::Mojo;

use Test::More tests => 1;

{
    package MockServer;
    use Mojo::Base 'Mojolicious';
    
    sub startup {
        my $self = shift;
        unshift @{$self->static->paths}, $self->home->rel_dir('public2');
        
        # slow application
        $self->hook(after_build_tx => sub {
            my ($tx, $app) = @_;
            sleep(1);
        });
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

$bot->on('res' => sub {
    my ($bot, $scrape, $job, $res) = @_;
    $scrape->();
    $urls{$job->resolved_uri} = $job;
});
$bot->on('refer' => sub {
    my ($bot, $enqueue, $job, $context) = @_;
    $enqueue->();
});

$bot->init;

Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

is((scalar keys %urls), 3, 'right length');

__END__
