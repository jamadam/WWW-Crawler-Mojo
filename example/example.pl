use strict;
use warnings;
use utf8;
use WWW::Crawler::Mojo;
use 5.10.0;

my $bot = WWW::Crawler::Mojo->new;

$bot->on(start => sub {
    shift->say_start;
});

$bot->on(res => sub {
    my ($bot, $discover, $queue, $res) = @_;
    say sprintf('fetching %s resulted status %s',
                                    $queue->resolved_uri, $res->code);
    $discover->();
});

$bot->on(refer => sub {
    my ($bot, $enqueue, $queue, $context) = @_;
    $enqueue->();
});

$bot->on(error => sub {
    my ($msg, $queue) = @_;
    say $msg;
    say "Re-scheduled";
    $bot->enqueue($queue);
});

$bot->enqueue('http://example.com/');
$bot->crawl;
