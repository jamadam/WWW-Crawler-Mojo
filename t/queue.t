use strict;
use warnings;
use utf8;
use File::Basename 'dirname';
use File::Spec::Functions qw{catdir splitdir rel2abs canonpath};
use lib catdir(dirname(__FILE__), '../lib');
use lib catdir(dirname(__FILE__), 'lib');
use Test::More;
use WWW::Crawler::Mojo;

use Test::More tests => 8;

my $bot = WWW::Crawler::Mojo->new;
$bot->enqueue('http://example.com/');
is ref $bot->queue->next, 'WWW::Crawler::Mojo::Job';
is $bot->queue->next->url, 'http://example.com/';
is $bot->queue->length, 1, 'right number';
$bot->enqueue(Mojo::URL->new('http://example.com/2'));
is ref $bot->queue->next(1), 'WWW::Crawler::Mojo::Job';
is $bot->queue->next(1)->url, 'http://example.com/2';
is $bot->queue->length, 2, 'right number';

my $job = $bot->queue->dequeue;
$bot->enqueue($job);
is $bot->queue->length, 1, 'right number';
$bot->requeue($job);
is $bot->queue->length, 2, 'right number';
