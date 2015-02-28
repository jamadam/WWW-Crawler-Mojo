package WWW::Crawler::Mojo::Queue::Memory;
use strict;
use warnings;
use utf8;
use Mojo::Base 'WWW::Crawler::Mojo::Queue';
use List::Util;

has jobs => sub { [] };
has redundancy => sub {
    my %fix;
    return sub {
        my $d = $_[0]->digest;
        return 1 if $fix{$d};
        $fix{$d} = 1;
        return;
    };
};

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
    return if (!$requeue && $self->redundancy->($job));
    push(@{$self->jobs}, $job);
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

=head2 redundancy

An subroutine reference called on enqueue process for avoiding redundant
requests. It marks the job 'done' and returns 0, and next time returns 1.

    if (!$queue->redundancy->($job)) {
        $queue->enqueue($job);
    }

Defaults to a code that uses "no cleanup" storage. By replacing this you can
control the memory usage.

    $queue->redundancy(sub {
        my $d = $_[0]->digest;
        return 1 if $your_storage{$d};
        $your_storage{$d} = 1;
        return;
    });

=head2 jobs

jobs.

=head1 METHODS

This class inherits all methods from L<WWW::Crawler::Mojo::Queue> class and
implements following new ones.

=head2 dequeue

Implementation for L<WWW::Crawler::Mojo::Queue> interface.

=head2 enqueue

Implementation for L<WWW::Crawler::Mojo::Queue> interface.

=head2 length

Implementation for L<WWW::Crawler::Mojo::Queue> interface.

=head2 next

Implementation for L<WWW::Crawler::Mojo::Queue> interface.

=head2 requeue

Implementation for L<WWW::Crawler::Mojo::Queue> interface.

=head2 shuffle

Implementation for L<WWW::Crawler::Mojo::Queue> interface.

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) Sugama Keita.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
