package WWW::Crawler::Mojo::Queue;
use strict;
use warnings;
use utf8;
use Mojo::Base -base;

sub dequeue { die 'Must be implemented by sub classes' }
sub enqueue { die 'Must be implemented by sub classes' }
sub length { die 'Must be implemented by sub classes' }
sub next { die 'Must be implemented by sub classes' }
sub requeue { die 'Must be implemented by sub classes' }
sub shuffle { die 'Must be implemented by sub classes' }
sub _enqueue { die 'Must be implemented by sub classes' }

1;

=head1 NAME

WWW::Crawler::Mojo::Queue - Crawler queue base class

=head1 SYNOPSIS

    my $queue = WWW::Crawler::Mojo::Queue::Memory->new;
    $queue->enqueue($job1);
    $queue->enqueue($job2);
    say $queue->length          # 2
    $job3 = $queue->next();     # $job3 = $job1
    $job4 = $queue->dequeue();  # $job4 = $job1
    say $queue->length          # 1

=head1 DESCRIPTION

This class represents a FIFO queue.

=head1 ATTRIBUTES

=head2 fix

A hash whoes keys are md5 hashes of enqueued URLs.

=head2 jobs

jobs.

=head1 METHODS

=head2 dequeue

Shift the oldest job and returns it. 

=head2 enqueue

Pushes a job.

=head2 next

Returns the oldest job.

=head2 length

Returns queue length

=head2 requeue

Pushes a job wether the job has been enqueued once or not.

=head2 shuffle

Shuffle the queue array.

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) Sugama Keita.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
