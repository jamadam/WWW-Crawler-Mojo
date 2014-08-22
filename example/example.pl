use strict;
use warnings;
use utf8;
use Mojo::Crawler;
use 5.10.0;

my $bot = Mojo::Crawler->new(
    on_res => sub {
        my ($discover, $queue, $tx) = @_;
        say sprintf('fetching %s resulted status %s',
                                        $queue->resolved_uri, $tx->res->code);
        $discover->();
    },
    on_refer => sub {
        my ($enqueue, $queue, $parent_queue, $context) = @_;
        $enqueue->();
    },
);

$bot->enqueue('http://example.com/');
$bot->crawl;
