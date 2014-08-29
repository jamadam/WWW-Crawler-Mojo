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
has 'redirect_history' => sub { [] };

sub child {
    my $self = shift;
    my $child = __PACKAGE__->new(@_,
                                referrer => $self, depth => $self->{depth} + 1);
    return $child;
}

sub add_props {
    my $self = shift;
    my %hash = scalar $_[0] == 1 ? %{$_[0]} : @_;
    for (keys %hash) {
        $self->additional_props->{$_} = $hash{$_};
    }
}

sub redirect {
    my ($self, $last, @history) = @_;
    $self->resolved_uri($last);
    $self->redirect_history(\@history);
}

1;

=head1 NAME

Mojo::Crawler::Queue - Single crawler queue

=head1 SYNOPSIS

    my $ua = Mojo::Crawler::Queue->new;

=head1 DESCRIPTION

This class represents a single crawler queue.

=head1 ATTRIBUTES

=head2 literal_uri

=head2 resolved_uri

=head2 referrer

=head2 depth

=head2 additional_props

Add propeties for queue.

    $queue->additional_props({key1 => $value1, key2 => $value2});

=head2 redirect_history

=head1 METHODS

=head2 child

Initiate a child queue by parent queue. The parent uri is set to child referrer.

    my $queue1 = Mojo::Crawler::Queue->new(resolved_uri => 'http://a/1');
    my $queue2 = $queue1->child(resolved_uri => 'http://a/2');
    say $queue2->referrer # 'http://a/1'

=head2 add_props

=head2 redirect

Replaces the resolved URI and history at once.

    my $queue = Mojo::Crawler::Queue->new;
    $queue->resolved_uri($url1);
    $queue->redirect($url2, $url3);
    say $queue->resolved_uri # $url2
    say $queue->redirect_history # [$url1, $url3]

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) Sugama Keita.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
