use strict;
use warnings;
use utf8;
use File::Basename 'dirname';
use File::Spec::Functions qw{catdir splitdir rel2abs canonpath};
use lib catdir(dirname(__FILE__), '../lib');
use lib catdir(dirname(__FILE__), 'lib');
use Test::More;
use Mojo::DOM;
use WWW::Crawler::Mojo;
use WWW::Crawler::Mojo::Job;
use Mojo::Message::Response;
use Test::More tests => 5;

{
    my $html = <<EOF;
<html>
<body>
<form action="/index1.html">
    <input type="text" value="default">
    <input type="submit" value="submit">
</form>
<form action="/index2.html">
    <textarea>foo</textarea>
    <input type="submit" value="submit">
</form>
</body>
</html>
EOF
    
    my $res = Mojo::Message::Response->new;
    $res->code(200);
    $res->body($html);
    $res->headers->content_type('text/html');
    
    my $bot = WWW::Crawler::Mojo->new;
    $bot->init;
    $bot->scrape($res, WWW::Crawler::Mojo::Job->new(resolved_uri => 'http://example.com/'));
    
    my $job;
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, '/index1.html', 'right url';
    is $job->resolved_uri, 'http://example.com/index1.html', 'right url';
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, '/index2.html', 'right url';
    is $job->resolved_uri, 'http://example.com/index2.html', 'right url';
    $job = shift @{$bot->{queue}};
    is $job, undef, 'no more urls';
}

