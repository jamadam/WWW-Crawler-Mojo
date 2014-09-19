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
    $| = 1;
    
    my ($bot, $discover, $job, $res) = @_;
    
    $count{$res->code}++;
    
    if ($res->code =~ qr{[54]..}) {
        say sprintf($res->code. ' occured! : %s referred by %s',
                        $job->resolved_uri, $job->referrer->resolved_uri);
    }
    
    my @disp_seed;
    push(@disp_seed, sprintf('%s:%s', $_, $count{$_})) for (keys %count);
    
    print(join(' / ', @disp_seed), ' ' x 30);
    print("\r");
    
    $discover->();
});

$bot->on(refer => sub {
    my ($bot, $enqueue, $job, $context) = @_;
    if ($job->referrer->resolved_uri->host eq 'example.com') {
        $enqueue->();
    }
});

$bot->enqueue('http://example.com/');
$bot->peeping_port(3001);
$bot->crawl;
