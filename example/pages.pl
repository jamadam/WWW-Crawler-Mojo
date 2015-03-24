#
# Collect hyper links and outputs tab separated values.
#

use strict;
use warnings;
use utf8;
use WWW::Crawler::Mojo;
use 5.10.0;
use Mojo::URL;

@ARGV || die 'Starting URL must given';
my @start = map {Mojo::URL->new($_)} @ARGV;
my @hosts = map {$_->host} @start;

my $bot = WWW::Crawler::Mojo->new;

$bot->on(start => sub {
    shift->say_start;
});

$bot->on(error => sub {
    my ($bot, $msg, $job) = @_;
    $bot->requeue->($job);
});

$bot->on(res => sub {
    $| = 1;
    
    my ($bot, $scrape, $job, $res) = @_;
    
    return if ($res->code !~ qr{[2]..});
    return unless grep {$_ eq $job->url->host} @hosts;
    
    if ($job->url =~ /product/) {
        $scrape->(sub {
            my ($bot, $enqueue, $job2, $context) = @_;
            return unless (ref $context eq 'Mojo::DOM' && $context->tag eq 'a');
            say qq!"@{[ $job->url ]}"\t"@{[ $job2->url ]}"!;
        });
    }
    
    $scrape->(sub {
        my ($bot, $enqueue, $job2, $context) = @_;
        return unless (ref $context eq 'Mojo::DOM' && $context->tag eq 'a');
        return unless grep {$_ eq $job2->url->host} @hosts;
        $enqueue->();
    });
});

$bot->enqueue(@start);
$bot->crawl;