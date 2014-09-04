use strict;
use warnings;
use utf8;
use File::Basename 'dirname';
use File::Spec::Functions qw{catdir splitdir rel2abs canonpath};
use lib catdir(dirname(__FILE__), '../lib');
use lib catdir(dirname(__FILE__), 'lib');
use Test::More;
use WWW::Crawler::Mojo;
use Mojo::Message::Response;

use Test::More tests => 4;

my $html = <<EOF;
<html>
<body>
日本
</body>
</html>
EOF

utf8::encode($html);

my $html2 = <<EOF;
<html>
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=cp932" />
</head>
<body>
日本
</body>
</html>
EOF

utf8::encode($html2);

{
    my $res = Mojo::Message::Response->new;
    $res->body($html);
    $res->headers->content_type('text/html');
    is WWW::Crawler::Mojo::guess_encoding($res), undef, 'right encoding';
}

{
    my $res = Mojo::Message::Response->new;
    $res->body($html2);
    $res->headers->content_type('text/html');
    is WWW::Crawler::Mojo::guess_encoding($res), 'cp932', 'right encoding';
}

{
    my $res = Mojo::Message::Response->new;
    $res->body($html);
    $res->headers->content_type('text/html; charset=cp932');
    is WWW::Crawler::Mojo::guess_encoding($res), 'cp932', 'right encoding';
}

{
    my $res = Mojo::Message::Response->new;
    $res->body($html);
    $res->headers->content_type('text/html; charset=cp932; hoge');
    is WWW::Crawler::Mojo::guess_encoding($res), 'cp932', 'right encoding';
}

1;

__END__

