use strict;
use warnings;
use utf8;
use File::Basename 'dirname';
use File::Spec::Functions qw{catdir splitdir rel2abs canonpath};
use lib catdir(dirname(__FILE__), '../lib');
use lib catdir(dirname(__FILE__), 'lib');
use Test::More;
use WWW::Crawler::Mojo;
use WWW::Crawler::Mojo::Job;

use Test::More tests => 11;

my $job = WWW::Crawler::Mojo::Job->new(resolved_uri => 'foo');
$job->add_props(add_baz => 'add_baz_value');
my $job2 = $job->clone;
is $job2->resolved_uri, 'foo', 'right result';
is $job2->additional_props->{add_baz}, 'add_baz_value', 'right prop';
isnt $job->additional_props, $job2->additional_props, 'deep cloned';

my $bot = WWW::Crawler::Mojo->new;
$bot->enqueue('http://example.com/');
is ref $bot->queue->[0], 'WWW::Crawler::Mojo::Job';
is $bot->queue->[0]->resolved_uri, 'http://example.com/';
is @{$bot->queue}, 1, 'right number';
$bot->enqueue(Mojo::URL->new('http://example.com/2'));
is ref $bot->queue->[1], 'WWW::Crawler::Mojo::Job';
is $bot->queue->[1]->resolved_uri, 'http://example.com/2';
is @{$bot->queue}, 2, 'right number';

my $job3 = shift @{$bot->queue};
$bot->enqueue($job3);
is @{$bot->queue}, 1, 'right number';
$bot->requeue($job3);
is @{$bot->queue}, 2, 'right number';

1;

__END__

