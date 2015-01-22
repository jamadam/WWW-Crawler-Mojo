package WWW::Crawler::Mojo::Job;
use strict;
use warnings;
use utf8;
use Mojo::Base -base;

has 'literal_uri' => '';
has 'resolved_uri' => '';
has 'referrer' => '';
has 'depth' => 0;
has 'redirect_history' => sub { [] };
has 'method' => 'get';
has 'tx_params';

sub clone {
    my $self = shift;
    return __PACKAGE__->new(%$self);
}

sub child {
    my $self = shift;
    my $child = __PACKAGE__->new(@_,
                                referrer => $self, depth => $self->{depth} + 1);
    return $child;
}

sub redirect {
    my ($self, $last, @history) = @_;
    $self->resolved_uri($last);
    $self->redirect_history(\@history);
}

sub original_uri {
    my $self = shift;
    my @histry = @{$self->redirect_history};
    return $self->resolved_uri unless (@histry);
    return $histry[$#histry];
}

1;

=head1 NAME

WWW::Crawler::Mojo::Job - Single crawler job

=head1 SYNOPSIS

    my $job = WWW::Crawler::Mojo::Job->new;

=head1 DESCRIPTION

This class represents a single crawler job.

=head1 ATTRIBUTES

=head2 literal_uri

=head2 resolved_uri

=head2 referrer

=head2 depth

=head2 redirect_history

=head1 METHODS

=head2 child

Initiate a child job by parent job. The parent uri is set to child referrer.

    my $job1 = WWW::Crawler::Mojo::Job->new(resolved_uri => 'http://a/1');
    my $job2 = $job1->child(resolved_uri => 'http://a/2');
    say $job2->referrer # 'http://a/1'

=head2 add_props

=head2 redirect

Replaces the resolved URI and history at once.

    my $job = WWW::Crawler::Mojo::Job->new;
    $job->resolved_uri($url1);
    $job->redirect($url2, $url3);
    say $job->resolved_uri # $url2
    say $job->redirect_history # [$url1, $url3]

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) Sugama Keita.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
