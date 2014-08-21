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

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    if ($self->{parent}) {
        $self->{referrer} = $self->{parent}->{resolved_uri};
        $self->{depth} = $self->{parent}->{depth} + 1;
        delete $self->{parent};
    }
    return $self;
}

sub add_props {
    my $self = shift;
    my %hash = scalar $_[0] == 1 ? %{$_[0]} : @_;
    for (keys %hash) {
        $self->additional_props->{$_} = $hash{$_};
    }
}

1;
