use strict;
use warnings;
use utf8;
use File::Basename 'dirname';
use File::Spec::Functions qw{catdir splitdir rel2abs canonpath};
use lib catdir(dirname(__FILE__), '../lib');
use lib catdir(dirname(__FILE__), 'lib');
use Test::More;
use Mojo::Crawler;

use Test::More tests => 70;

my $base;
my $tmp;

# Resolve RFC 1808 examples
$base = Mojo::URL->new('http://a/b/c/d?q#f');
$tmp = Mojo::Crawler::resolve_href($base, 'g');
is $tmp, 'http://a/b/c/g', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, './g');
is $tmp, 'http://a/b/c/g', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, 'g/');
is $tmp, 'http://a/b/c/g/', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '//g');
is $tmp, 'http://g', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '?y');
is $tmp, 'http://a/b/c/d?y', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, 'g?y');
is $tmp, 'http://a/b/c/g?y', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, 'g?y/./x');
is $tmp, 'http://a/b/c/g?y/./x', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '#s');
is $tmp, 'http://a/b/c/d?q', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, 'g#s');
is $tmp, 'http://a/b/c/g', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, 'g#s/./x');
is $tmp, 'http://a/b/c/g', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, 'g?y#s');
is $tmp, 'http://a/b/c/g?y', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '.');
is $tmp, 'http://a/b/c', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, './');
is $tmp, 'http://a/b/c/', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '..');
is $tmp, 'http://a/b', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../');
is $tmp, 'http://a/b/', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../g');
is $tmp, 'http://a/b/g', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../..');
is $tmp, 'http://a/', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../../');
is $tmp, 'http://a/', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../../g');
is $tmp, 'http://a/g', 'right url';

$base = Mojo::URL->new('http://example.com');
$tmp = Mojo::Crawler::resolve_href($base, '/hoge.html');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, './hoge.html');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '#a');
is $tmp, 'http://example.com', 'right url';

$base = Mojo::URL->new('http://example.com');
$tmp = Mojo::Crawler::resolve_href($base, 'http://example2.com/hoge.html');
is $tmp, 'http://example2.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, 'http://example2.com//hoge.html');
is $tmp, 'http://example2.com//hoge.html', 'right url';

$base = Mojo::URL->new('http://example.com/dir/');
$tmp = Mojo::Crawler::resolve_href($base, './hoge.html');
is $tmp, 'http://example.com/dir/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../hoge.html');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../../hoge.html');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '/hoge.html');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '/');
is $tmp, 'http://example.com/', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '');
is $tmp, 'http://example.com/dir/', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, 'foo');
is $tmp, 'http://example.com/dir/foo', 'right url';

$base = Mojo::URL->new('http://example.com/dir/');
$tmp = Mojo::Crawler::resolve_href($base, './hoge.html/?a=b');
is $tmp, 'http://example.com/dir/hoge.html/?a=b', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../hoge.html/?a=b');
is $tmp, 'http://example.com/hoge.html/?a=b', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../../hoge.html/?a=b');
is $tmp, 'http://example.com/hoge.html/?a=b', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '/hoge.html/?a=b');
is $tmp, 'http://example.com/hoge.html/?a=b', 'right url';

$base = Mojo::URL->new('http://example.com/dir/');
$tmp = Mojo::Crawler::resolve_href($base, './hoge.html#fragment');
is $tmp, 'http://example.com/dir/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../hoge.html#fragment');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../../hoge.html#fragment');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '/hoge.html#fragment');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '/#fragment');
is $tmp, 'http://example.com/', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, './#fragment');
is $tmp, 'http://example.com/dir/', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '#fragment');
is $tmp, 'http://example.com/dir/', 'right url';

$base = Mojo::URL->new('https://example.com/');
$tmp = Mojo::Crawler::resolve_href($base, '//example2.com/hoge.html');
is $tmp, 'https://example2.com/hoge.html', 'right url';
$base = Mojo::URL->new('https://example.com/');
$tmp = Mojo::Crawler::resolve_href($base, '//example2.com:8080/hoge.html');
is $tmp, 'https://example2.com:8080/hoge.html', 'right url';

$base = Mojo::URL->new('http://example.com/org');
$tmp = Mojo::Crawler::resolve_href($base, '/hoge.html');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, './hoge.html');
is $tmp, 'http://example.com/hoge.html', 'right url';

$base = Mojo::URL->new('http://example.com/org');
$tmp = Mojo::Crawler::resolve_href($base, 'http://example2.com/hoge.html');
is $tmp, 'http://example2.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, 'http://example2.com//hoge.html');
is $tmp, 'http://example2.com//hoge.html', 'right url';

$base = Mojo::URL->new('http://example.com/dir/org');
$tmp = Mojo::Crawler::resolve_href($base, './hoge.html');
is $tmp, 'http://example.com/dir/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../hoge.html');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../../hoge.html');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '/hoge.html');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '/');
is $tmp, 'http://example.com/', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '');
is $tmp, 'http://example.com/dir/org', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, 'foo');
is $tmp, 'http://example.com/dir/foo', 'right url';

$base = Mojo::URL->new('http://example.com/dir/org');
$tmp = Mojo::Crawler::resolve_href($base, './hoge.html/?a=b');
is $tmp, 'http://example.com/dir/hoge.html/?a=b', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../hoge.html/?a=b');
is $tmp, 'http://example.com/hoge.html/?a=b', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../../hoge.html/?a=b');
is $tmp, 'http://example.com/hoge.html/?a=b', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '/hoge.html/?a=b');
is $tmp, 'http://example.com/hoge.html/?a=b', 'right url';

$base = Mojo::URL->new('http://example.com/dir/org');
$tmp = Mojo::Crawler::resolve_href($base, './hoge.html#fragment');
is $tmp, 'http://example.com/dir/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../hoge.html#fragment');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '../../hoge.html#fragment');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '/hoge.html#fragment');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '/#fragment');
is $tmp, 'http://example.com/', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, './#fragment');
is $tmp, 'http://example.com/dir/', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, '#fragment');
is $tmp, 'http://example.com/dir/org', 'right url';

$base = Mojo::URL->new('https://example.com/org');
$tmp = Mojo::Crawler::resolve_href($base, '//example2.com/hoge.html');
is $tmp, 'https://example2.com/hoge.html', 'right url';
$base = Mojo::URL->new('https://example.com/org');
$tmp = Mojo::Crawler::resolve_href($base, '//example2.com:8080/hoge.html');
is $tmp, 'https://example2.com:8080/hoge.html', 'right url';

$tmp = Mojo::Crawler::resolve_href('http://www.eclipse.org/forums/index.php/f/48/', '//www.eclipse.org/forums/');
is $tmp, 'http://www.eclipse.org/forums/', 'right url';
$tmp = Mojo::Crawler::resolve_href('https://www.eclipse.org/forums/index.php/f/48/', '//www.eclipse.org/forums/');
is $tmp, 'https://www.eclipse.org/forums/', 'right url';

1;

__END__

