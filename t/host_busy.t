use strict;
use warnings;
use utf8;
use File::Basename 'dirname';
use File::Spec::Functions qw{catdir};
use lib catdir(dirname(__FILE__), '../lib');
use lib catdir(dirname(__FILE__), 'lib');
use Test::More;
use Mojo::Crawler;

use Test::More tests => 20;

my $uri;
my $bot = Mojo::Crawler->new;

$uri = Mojo::URL->new('http://example.com/');
is $bot->host_busy($uri), undef, 'right result';
is $bot->host_busy($uri), 1, 'right result';
is $bot->host_busy($uri), 1, 'right result';
$uri = Mojo::URL->new('http://example.com:80/');
is $bot->host_busy($uri), 1, 'right result';
$uri = Mojo::URL->new('https://example.com/');
is $bot->host_busy($uri), undef, 'right result';
is $bot->host_busy($uri), 1, 'right result';
$uri = Mojo::URL->new('https://example.com:8080/');
is $bot->host_busy($uri), undef, 'right result';
is $bot->host_busy($uri), 1, 'right result';
$uri = Mojo::URL->new('http://☃.net');
is $bot->host_busy($uri), undef, 'right result';
$uri = Mojo::URL->new('http://xn--n3h.net');
is $bot->host_busy($uri), 1, 'right result';

sleep 1;

$uri = Mojo::URL->new('http://example.com/');
is $bot->host_busy($uri), undef, 'right result';
is $bot->host_busy($uri), 1, 'right result';
is $bot->host_busy($uri), 1, 'right result';
$uri = Mojo::URL->new('http://example.com:80/');
is $bot->host_busy($uri), 1, 'right result';
$uri = Mojo::URL->new('https://example.com/');
is $bot->host_busy($uri), undef, 'right result';
is $bot->host_busy($uri), 1, 'right result';
$uri = Mojo::URL->new('https://example.com:8080/');
is $bot->host_busy($uri), undef, 'right result';
is $bot->host_busy($uri), 1, 'right result';
$uri = Mojo::URL->new('http://☃.net');
is $bot->host_busy($uri), undef, 'right result';
$uri = Mojo::URL->new('http://xn--n3h.net');
is $bot->host_busy($uri), 1, 'right result';

1;

__END__

