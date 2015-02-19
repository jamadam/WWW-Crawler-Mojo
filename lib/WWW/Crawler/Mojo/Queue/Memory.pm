package WWW::Crawler::Mojo::Queue::Memory;
use strict;
use warnings;
use utf8;
use Mojo::Base 'WWW::Crawler::Mojo::Queue';
use List::Util;

has fix => sub { {} };
has jobs => sub { [] };

sub dequeue {
    return shift(@{shift->jobs});
}

sub enqueue {
    shift->_enqueue(@_);
}

sub length {
    return scalar(@{shift->jobs});
}

sub next {
    return shift->jobs->[shift || 0];
}

sub requeue {
    shift->_enqueue(@_, 1);
}

sub shuffle {
    my $self = shift;
    @{$self->jobs} = List::Util::shuffle @{$self->jobs};
}

sub _enqueue {
    my ($self, $job, $requeue) = @_;
    
    my $digest = $job->digest;
    
    return if (!$requeue && exists($self->fix->{$digest}));
    
    push(@{$self->jobs}, $job);
    
    $self->fix->{$digest} = undef;
    
    return $self;
}

1;

=head1 NAME

WWW::Crawler::Mojo::Queue::Memory - Crawler queue with memory

=head1 SYNOPSIS

=head1 DESCRIPTION

Crawler queue with memory.

=head1 ATTRIBUTES

This class inherits all methods from L<WWW::Crawler::Mojo::Queue> and implements
following new ones.

=head2 fix

A hash whoes keys are md5 hashes of enqueued URLs.

=head2 jobs

jobs.

=head1 METHODS

This class inherits all methods from L<WWW::Crawler::Mojo::Queue>.

=head2 dequeue

Implement for L<WWW::Crawler::Mojo::Queue> interface.

=head2 enqueue

Implement for L<WWW::Crawler::Mojo::Queue> interface.

=head2 length

Implement for L<WWW::Crawler::Mojo::Queue> interface.

=head2 next

Implement for L<WWW::Crawler::Mojo::Queue> interface.

=head2 requeue

Implement for L<WWW::Crawler::Mojo::Queue> interface.

=head2 shuffle

Implement for L<WWW::Crawler::Mojo::Queue> interface.

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) Sugama Keita.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
