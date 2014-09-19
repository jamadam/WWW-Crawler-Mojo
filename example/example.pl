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
    my ($bot, $discover, $job, $res) = @_;
    say sprintf('fetching %s resulted status %s',
                                    $job->resolved_uri, $res->code);
    $discover->();
});

$bot->on(refer => sub {
    my ($bot, $enqueue, $job, $context) = @_;
    $enqueue->();
});

$bot->on(error => sub {
    my ($msg, $job) = @_;
    say $msg;
    say "Re-scheduled";
    $bot->requeue($job);
});

$bot->enqueue('http://example.com/');
$bot->crawl;
