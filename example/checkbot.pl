use strict;
use warnings;
use utf8;
use Mojo::Crawler;
use 5.10.0;

my $bot = Mojo::Crawler->new;
$bot->on(refer => sub {
    my ($bot, $discover, $queue, $tx) = @_;
    if ($tx->res->code == 404) {
        say sprintf('404 occured! : %s referred by %s',
                                    $queue->resolved_uri);
    } else {
        say sprintf('fetching %s resulted status %s',
                                    $queue->resolved_uri, $tx->res->code);
    }
    
    $discover->();
});
$bot->on(refer => sub {
    my ($bot, $enqueue, $queue, $parent_queue, $context) = @_;
    $enqueue->();
});

$bot->enqueue('http://google.com/');
$bot->peeping_port(3001);
$bot->crawl;
