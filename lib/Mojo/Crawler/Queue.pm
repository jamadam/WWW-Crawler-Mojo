package Mojo::Crawler::Queue;
use strict;
use warnings;
use utf8;
use Mojo::Base -base;

has 'literal_uri' => '';
has 'resolved_uri' => '';
has 'referrer' => '';
has 'depth' => 0;
has 'additional_props' => sub { {} };

sub child {
    my $self = shift;
    my $child = __PACKAGE__->new(@_);
    $child->{referrer} = $self->{resolved_uri};
    $child->{depth} = $self->{depth} + 1;
    return $child;
}

sub add_props {
    my $self = shift;
    my %hash = scalar $_[0] == 1 ? %{$_[0]} : @_;
    for (keys %hash) {
        $self->additional_props->{$_} = $hash{$_};
    }
}

1;
