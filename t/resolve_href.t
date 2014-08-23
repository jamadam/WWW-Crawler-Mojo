use strict;
use warnings;
use utf8;
use File::Basename 'dirname';
use File::Spec::Functions qw{catdir splitdir rel2abs canonpath};
use lib catdir(dirname(__FILE__), '../lib');
use lib catdir(dirname(__FILE__), 'lib');
use Test::More;
use Mojo::Crawler;

use Test::More tests => 50;

my $base;
my $tmp;
$base = Mojo::URL->new('http://example.com');
$tmp = Mojo::Crawler::resolve_href($base, '/hoge.html');
is $tmp, 'http://example.com/hoge.html', 'right url';
$tmp = Mojo::Crawler::resolve_href($base, './hoge.html');
is $tmp, 'http://example.com/hoge.html', 'right url';

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

