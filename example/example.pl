use strict;
use warnings;
use utf8;
use Mojo::Crawler;
use 5.10.0;

my $bot = Mojo::Crawler->new;
$bot->on_res(sub {
    my ($discover, $queue, $tx) = @_;
    say sprintf('fetching %s resulted status %s',
                                    $queue->resolved_uri, $tx->res->code);
    $discover->();
});
$bot->on_refer(sub {
    my ($enqueue, $queue, $parent_queue, $context) = @_;
    $enqueue->();
});
$bot->on_error(sub {
    my ($msg, $queue) = @_;
    say $msg;
    say "Re-scheduled";
    $bot->enqueue($queue);
});
$bot->enqueue('http://example.com/');
$bot->crawl;
