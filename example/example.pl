use strict;
use warnings;
use utf8;
use Mojo::Crawler;

my $bot = Mojo::Crawler->new(
    on_res => sub {
        my ($crawl, $queue, $tx) = @_;
        $crawl->();
    },
    on_refer => sub {
        my ($append, $queue, $parent_queue, $context) = @_;
        $append->();
    },
    after_crawl => sub {
        my ($queue, $tx) = @_;
    }
);

$bot->append_queue('http://example.com/');
$bot->depth(2);
$bot->crawl;
