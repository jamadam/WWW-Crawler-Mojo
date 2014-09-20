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
use Test::More tests => 28;

my $html = <<EOF;
<html>
<head>
    <link rel="stylesheet" type="text/css" href="css1.css" />
    <link rel="stylesheet" type="text/css" href="css2.css" />
    <script type="text/javascript" src="js1.js"></script>
    <script type="text/javascript" src="js2.js"></script>
</head>
<body>
<a href="index1.html">A</a>
<a href="index2.html">B</a>
<a href="mailto:a\@example.com">C</a>
<a href="tel:0000">D</a>
<map name="m_map" id="m_map">
    <area href="index3.html" coords="" title="E" />
</map>
<script>
    var a = "<a href='hoge'>F</a>";
</script>
<a href="escaped?foo=bar&amp;baz=yada">G</a>
</body>
</html>
EOF

my @array;
WWW::Crawler::Mojo::collect_urls_html(Mojo::DOM->new($html), sub {
    push(@array, shift);
    push(@array, shift);
});
is shift @array, 'css1.css', 'right url';
is shift(@array)->type, 'link', 'right type';
is shift @array, 'css2.css', 'right url';
is shift( @array)->type, 'link', 'right type';
is shift @array, 'js1.js', 'right url';
is shift(@array)->type, 'script', 'right type';
is shift @array, 'js2.js', 'right url';
is shift(@array)->type, 'script', 'right type';
is shift @array, 'index1.html', 'right url';
is shift(@array)->type, 'a', 'right type';
is shift @array, 'index2.html', 'right url';
is shift(@array)->type, 'a', 'right type';
is shift @array, 'mailto:a@example.com','right url';
is shift(@array)->type, 'a', 'right type';
is shift @array, 'tel:0000', 'right url';
is shift(@array)->type, 'a', 'right type';
is shift @array, 'index3.html', 'right url';
is shift(@array)->type, 'area', 'right type';
is shift @array, 'escaped?foo=bar&baz=yada', 'right url';
is shift(@array)->type, 'a', 'right type';
is shift @array, undef, 'no more urls';

{
    my $css = <<EOF;
body {
    background-image:url('/image/a.png');
}
div {
    background-image:url('/image/b.png');
}
div {
    background: #fff url('/image/c.png');
}
EOF

    my @array;
    WWW::Crawler::Mojo::collect_urls_css($css, sub {
        push(@array, shift);
        push(@array, shift);
    });
    is shift @array, '/image/a.png', 'right url';
    is shift @array, undef, 'empty';
    is shift @array, '/image/b.png', 'right url';
    is shift @array, undef, 'empty';
    is shift @array, '/image/c.png', 'right url';
    is shift @array, undef, 'empty';
}

my $xhtml = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">
<head>
</head>
<body>
    <script>
        var a = "<a href='hoge'>a</a>";
    </script>
</body>
</html>
EOF

@array = ();
WWW::Crawler::Mojo::collect_urls_html(Mojo::DOM->new($xhtml), sub {
    push(@array, shift);
    push(@array, shift);
});
is(scalar @array, 0, 'right length');

1;

__END__

