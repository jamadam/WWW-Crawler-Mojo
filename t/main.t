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
use Test::More tests => 33;

{
    my $html = <<EOF;
<html>
<head>
    <link rel="stylesheet" type="text/css" href="css1.css" />
    <link rel="stylesheet" type="text/css" href="css2.css" />
    <script type="text/javascript" src="js1.js"></script>
    <script type="text/javascript" src="js2.js"></script>
    <script type="text/javascript" src="//example.com/js3.js"></script>
</head>
<body>
<a href="index1.html">A</a>
<a href="index2.html">B</a>
<a href="mailto:a\@example.com">C</a>
<a href="tel:0000">D</a>
<map name="m_map" id="m_map">
    <area href="index3.html" coords="" title="E" />
</map>
<a href="foo://example.com/foo"></a>
<a href="index1.html ">duplication</a>
<a href=" index1.html ">duplication</a>
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
    is $job->literal_uri, 'index1.html', 'right url';
    is $job->resolved_uri, 'http://example.com/index1.html', 'right url';
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, 'index2.html', 'right url';
    is $job->resolved_uri, 'http://example.com/index2.html', 'right url';
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, 'index3.html', 'right url';
    is $job->resolved_uri, 'http://example.com/index3.html', 'right url';
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, 'css1.css', 'right url';
    is $job->resolved_uri, 'http://example.com/css1.css', 'right url';
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, 'css2.css', 'right url';
    is $job->resolved_uri, 'http://example.com/css2.css', 'right url';
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, 'js1.js', 'right url';
    is $job->resolved_uri, 'http://example.com/js1.js', 'right url';
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, 'js2.js', 'right url';
    is $job->resolved_uri, 'http://example.com/js2.js', 'right url';
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, '//example.com/js3.js', 'right url';
    is $job->resolved_uri, 'http://example.com/js3.js', 'right url';
    $job = shift @{$bot->{queue}};
    is $job, undef, 'no more urls';
    
    my $bot2 = WWW::Crawler::Mojo->new;
    $bot2->init;
    $bot2->scrape($res, WWW::Crawler::Mojo::Job->new(resolved_uri => 'http://example.com/a/a'));
    
    $job = shift @{$bot2->{queue}};
    $job = shift @{$bot2->{queue}};
    $job = shift @{$bot2->{queue}};
    $job = shift @{$bot2->{queue}};
    is $job->literal_uri, 'css1.css', 'right url';
    is $job->resolved_uri, 'http://example.com/a/css1.css', 'right url';
    
    my $bot3 = WWW::Crawler::Mojo->new;
    $bot3->init;
    $bot3->scrape($res, WWW::Crawler::Mojo::Job->new(resolved_uri => 'https://example.com/'));
    
    $job = shift @{$bot3->{queue}};
    $job = shift @{$bot3->{queue}};
    $job = shift @{$bot3->{queue}};
    $job = shift @{$bot3->{queue}};
    is $job->literal_uri, 'css1.css', 'right url';
    is $job->resolved_uri, 'https://example.com/css1.css', 'right url';
    $job = shift @{$bot3->{queue}};
    $job = shift @{$bot3->{queue}};
    $job = shift @{$bot3->{queue}};
    $job = shift @{$bot3->{queue}};
    is $job->literal_uri, '//example.com/js3.js', 'right url';
    is $job->resolved_uri, 'https://example.com/js3.js', 'right url';
}
{
    my $html = <<EOF;
<html>
<head>
    <base href="http://example2.com/">
    <link rel="stylesheet" type="text/css" href="css1.css" />
</head>
<body>
</body>
</html>
EOF
    
    my $tx = Mojo::Transaction::HTTP->new;
    $tx->req->url(Mojo::URL->new('http://example.com/'));
    $tx->res->code(200);
    $tx->res->body($html);
    $tx->res->headers->content_type('text/html');
    
    my $bot = WWW::Crawler::Mojo->new;
    $bot->init;
    $bot->scrape($tx->res, WWW::Crawler::Mojo::Job->new(resolved_uri => 'http://example.com/'));
    
    my $job;
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, 'css1.css', 'right url';
    is $job->resolved_uri, 'http://example2.com/css1.css', 'right url';
    
    $bot = WWW::Crawler::Mojo->new;
    $bot->init;
    $bot->scrape($tx->res, WWW::Crawler::Mojo::Job->new(resolved_uri => 'http://example.com/a/'));
    
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, 'css1.css', 'right url';
    is $job->resolved_uri, 'http://example2.com/css1.css', 'right url';
}
{
    my $html = <<EOF;
<html>
<head>
    <base href="/">
    <link rel="stylesheet" type="text/css" href="css1.css" />
</head>
<body>
</body>
</html>
EOF
    
    my $tx = Mojo::Transaction::HTTP->new;
    $tx->req->url(Mojo::URL->new('http://example.com/'));
    $tx->res->code(200);
    $tx->res->body($html);
    $tx->res->headers->content_type('text/html');
    
    my $bot = WWW::Crawler::Mojo->new;
    $bot->init;
    $bot->scrape($tx->res, WWW::Crawler::Mojo::Job->new(resolved_uri => 'http://example.com/'));
    
    my $job;
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, 'css1.css', 'right url';
    is $job->resolved_uri, 'http://example.com/css1.css', 'right url';
    
    $bot = WWW::Crawler::Mojo->new;
    $bot->init;
    $bot->scrape($tx->res, WWW::Crawler::Mojo::Job->new(resolved_uri => 'http://example.com/a/'));
    
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, 'css1.css', 'right url';
    is $job->resolved_uri, 'http://example.com/css1.css', 'right url';
}
{
    my $html = <<EOF;
<html>
<head>
    <base>
    <link rel="stylesheet" type="text/css" href="css1.css" />
</head>
<body>
</body>
</html>
EOF
    
    my $tx = Mojo::Transaction::HTTP->new;
    $tx->req->url(Mojo::URL->new('http://example.com/'));
    $tx->res->code(200);
    $tx->res->body($html);
    $tx->res->headers->content_type('text/html');
    
    my $bot = WWW::Crawler::Mojo->new;
    $bot->init;
    $bot->scrape($tx->res, WWW::Crawler::Mojo::Job->new(resolved_uri => 'http://example.com/'));
    
    my $job;
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, 'css1.css', 'right url';
    is $job->resolved_uri, 'http://example.com/css1.css', 'right url';
}
