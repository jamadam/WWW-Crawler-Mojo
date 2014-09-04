use strict;
use warnings;
use utf8;
use WWW::Crawler::Mojo;
use 5.10.0;

my $bot = WWW::Crawler::Mojo->new;
my %count;

$bot->on(start => sub {
    shift->say_start;
});

$bot->on(res => sub {
    my ($bot, $discover, $queue, $res) = @_;
    
    $count{$res->code}++;
    
    if ($res->code == 404) {
        say sprintf('404 occured! : %s referred by %s',
                                    $queue->resolved_uri, $queue->referrer);
    }
    
    my @disp_seed;
    push(@disp_seed, sprintf('%s:%s', $_, $count{$_})) for (keys %count);
    
    $| = 1;
    print(join(' / ', @disp_seed), ' ' x 30);
    print("\r");
    
    $discover->();
});

$bot->on(refer => sub {
    my ($bot, $enqueue, $queue, $context) = @_;
    $enqueue->();
});

$bot->enqueue('http://example.com/');
$bot->peeping_port(3001);
$bot->crawl;
