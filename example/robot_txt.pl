use strict;
use warnings;
use utf8;
use Mojo::Crawler;
use WWW::RobotRules::Extended;
use 5.10.0;

my $bot = Mojo::Crawler->new;

$bot->on(res => sub {
    my ($bot, $discover, $queue, $res) = @_;
    $discover->();
});

$bot->on(refer => sub {
    my ($bot, $enqueue, $queue, $context) = @_;
    return unless ($self->allowed_url_on_robot_rule($queue->resolved_uri));
    $enqueue->();
});

$bot->enqueue('http://example.com/');
$bot->peeping_port(3001);
$bot->crawl;


sub allowed_url_on_robot_rule {
    my $url = shift;
    
    state $ua = Mojo::UserAgent->new;
    state $rules = WWW::RobotRules::Extended->new('MOMspider/1.0');
    
    if (! $rules->rules($url)) {
        my $res = $ua->get($url->clone->path('/robot.txt'))->res;
        $rules->parse($url, $res->body) if ($res->code == 200);
    }
    
    return $rules->allowed($url);
}
