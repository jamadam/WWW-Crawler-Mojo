use strict;
use warnings;
use utf8;
use File::Basename 'dirname';
use File::Spec::Functions qw{catdir splitdir rel2abs canonpath};
use lib catdir(dirname(__FILE__), '../lib');
use lib catdir(dirname(__FILE__), 'lib');
use Test::More;
use WWW::Crawler::Mojo::Queue;

use Test::More tests => 3;

my $queue = WWW::Crawler::Mojo::Queue->new(resolved_uri => 'foo');
$queue->add_props(add_baz => 'add_baz_value');
my $queue2 = $queue->clone;
is $queue2->resolved_uri, 'foo', 'right result';
is $queue2->additional_props->{add_baz}, 'add_baz_value', 'right prop';
isnt $queue->additional_props, $queue2->additional_props, 'deep cloned';

1;

__END__

