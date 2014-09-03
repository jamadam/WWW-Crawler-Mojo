use strict;
use warnings;
use utf8;
use File::Basename 'dirname';
use File::Spec::Functions qw{catdir};
use lib catdir(dirname(__FILE__), '../lib');
use lib catdir(dirname(__FILE__), 'lib');
use Test::More;
use Mojo::Crawler;

use Test::More tests => 42;

my $bot = Mojo::Crawler->new;
$bot->max_conn(100);
$bot->max_conn_per_host(1);

my $uri1 = Mojo::URL->new('http://example.com/');
my $uri2 = Mojo::URL->new('http://example.com:80/');
my $uri3 = Mojo::URL->new('https://example.com/');
my $uri4 = Mojo::URL->new('https://example.com:8080/');
my $uri5 = Mojo::URL->new('http://☃.net');
my $uri6 = Mojo::URL->new('http://xn--n3h.net');

is $bot->mod_busyness($uri1, 1), 1, 'right result';
is $bot->mod_busyness($uri1, 1), undef, 'right result';
is $bot->mod_busyness($uri1, 1), undef, 'right result';
is $bot->mod_busyness($uri2, 1), undef, 'right result';
is $bot->mod_busyness($uri3, 1), 1, 'right result';
is $bot->mod_busyness($uri3, 1), undef, 'right result';
is $bot->mod_busyness($uri4, 1), 1, 'right result';
is $bot->mod_busyness($uri4, 1), undef, 'right result';
is $bot->mod_busyness($uri5, 1), 1, 'right result';
is $bot->mod_busyness($uri6, 1), undef, 'right result';
is $bot->active_conn, 4, 'right result';

is $bot->mod_busyness($uri1, -1), 1, 'right result';
is $bot->mod_busyness($uri3, -1), 1, 'right result';
is $bot->mod_busyness($uri4, -1), 1, 'right result';
is $bot->mod_busyness($uri5, -1), 1, 'right result';
is $bot->active_conn, 0, 'right result';

is $bot->mod_busyness($uri1, 1), 1, 'right result';
is $bot->mod_busyness($uri1, 1), undef, 'right result';
is $bot->mod_busyness($uri1, 1), undef, 'right result';
is $bot->mod_busyness($uri2, 1), undef, 'right result';
is $bot->mod_busyness($uri3, 1), 1, 'right result';
is $bot->mod_busyness($uri3, 1), undef, 'right result';
is $bot->mod_busyness($uri4, 1), 1, 'right result';
is $bot->mod_busyness($uri4, 1), undef, 'right result';
is $bot->mod_busyness($uri5, 1), 1, 'right result';
is $bot->mod_busyness($uri6, 1), undef, 'right result';
is $bot->active_conn, 4, 'right result';

is $bot->mod_busyness($uri1, -1), 1, 'right result';
is $bot->mod_busyness($uri3, -1), 1, 'right result';
is $bot->mod_busyness($uri4, -1), 1, 'right result';
is $bot->mod_busyness($uri5, -1), 1, 'right result';

$bot->max_conn(1);
$bot->max_conn_per_host(100);

is $bot->mod_busyness($uri1, 1), 1, 'right result';
is $bot->mod_busyness($uri1, 1), undef, 'right result';
is $bot->active_conn, 1, 'right result';

is $bot->mod_busyness($uri1, -1), 1, 'right result';

$bot->max_conn(100);
$bot->max_conn_per_host(2);

is $bot->mod_busyness($uri1, 1), 1, 'right result';
is $bot->mod_busyness($uri1, 1), 1, 'right result';
is $bot->mod_busyness($uri1, 1), undef, 'right result';
is $bot->active_conn, 2, 'right result';

is $bot->mod_busyness($uri1, -1), 1, 'right result';
is $bot->mod_busyness($uri1, -1), 1, 'right result';
is $bot->active_conn, 0, 'right result';

1;

__END__
