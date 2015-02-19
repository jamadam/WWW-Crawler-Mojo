package WWW::Crawler::Mojo::Job;
use strict;
use warnings;
use utf8;
use Mojo::Base -base;
use Mojo::Util qw(md5_sum deprecated);

has 'closed';
has depth => 0;
has 'literal_uri';
has 'method';
has 'referrer';
has 'referrer_url';
has redirect_history => sub { [] };
has 'tx_params';
has 'url';

sub upgrade {
    my ($class, $job) = @_;
    
    if (! ref $job || ref $job ne __PACKAGE__) {
        my $url = !ref $job ? Mojo::URL->new($job) : $job;
        $job = $class->new(url => $url);
    }
    
    return $job;
}

sub clone {
    my $self = shift;
    return __PACKAGE__->new(%$self);
}

sub close {
    my $self = shift;
    $self->{closed} = 1;
    $self->{referrer} = undef;
}

sub child {
    my $self = shift;
    return __PACKAGE__->new(@_, referrer => $self, referrer_url => $self->url,
                                                    depth => $self->depth + 1);
}

sub digest {
    my $self = shift;
    my $md5_seed = $self->url->to_string. ($self->method || '');
    $md5_seed .= $self->tx_params->to_string if ($self->tx_params);
    return md5_sum($md5_seed);
}

sub redirect {
    my ($self, $last, @history) = @_;
    $self->url($last);
    $self->redirect_history(\@history);
}

sub resolved_uri {
    deprecated 'resolved_uri is DEPRECATED in favor of url';
    return $_[0]->{resolved_uri} = $_[1] if (scalar @_ == 2);
    return $_[0]->{resolved_uri} //= '';
}

sub original_uri {
    deprecated 'original_uri is DEPRECATED in favor of original_url';
    return shift->original_url(@_);
}

sub original_url {
    my $self = shift;
    my @histry = @{$self->redirect_history};
    return $self->url unless (@histry);
    return $histry[$#histry];
}

1;

=head1 NAME

WWW::Crawler::Mojo::Job - Single crawler job

=head1 SYNOPSIS

    my $job1 = WWW::Crawler::Mojo::Job->new;
    $job1->url('http://example.com/');
    my $job2 = $job1->child;

=head1 DESCRIPTION

This class represents a single crawler job.

=head1 ATTRIBUTES

=head2 closed

A flag that the job has been closed or not.

    $job->closed(1);
    say $job->closed;

=head2 depth

The depth of job in referrer series.

    my $job1 = WWW::Crawler::Mojo::Job->new;
    my $job2 = $job1->child;
    my $job3 = $job2->child;
    say $job1->depth; # 0
    say $job2->depth; # 1
    say $job3->depth; # 2

=head2 literal_uri

A L<Mojo::URL> instance of the literal URL that has appeared in the referrer
document.

    $job1->literal_uri('./index.html');
    say $job1->literal_uri; # './index.html'

=head2 resolved_uri [DEPRECATED]

A L<Mojo::URL> instance of the resolved URL. Use url instead.

    $job1->resolved_uri('http://example.com/');
    say $job1->resolved_uri; # 'http://example.com/'

=head2 referrer

A job instance that has referred the URL.

    $job1->referrer($job);
    my $job2 = $job1->referrer;

=head2 redirect_history

An array reference that contains URLs of redirect history.

    $job1->redirect_history([$url1, $url2, $url3]);
    my $history = $job1->redirect_history;

=head2 url [DEPRECATED]

A L<Mojo::URL> instance of the resolved URL.

    $job1->url('http://example.com/');
    say $job1->url; # 'http://example.com/'

=head2 method

HTTP request method such as get or post.

    $job1->method('GET');
    say $job1->method; # GET

=head2 tx_params

A hash reference that contains params for L<Mojo::Transaction>.

    $job1->tx_params({foo => 'bar'});
    $params = $job1->tx_params;

=head1 METHODS

=head2 clone

Clones the job.

    my $job2 = $job1->clone;

=head2 close

Close the job and cut the referrer series.

    $job->close;

=head2 child

Instantiate a child job by parent job. The parent uri is set to child referrer.

    my $job1 = WWW::Crawler::Mojo::Job->new(url => 'http://a/1');
    my $job2 = $job1->child(url => 'http://a/2');
    say $job2->referrer->url # 'http://a/1'

=head2 redirect

Replaces the resolved URL and history at once.

    my $job = WWW::Crawler::Mojo::Job->new;
    $job->url($url1);
    $job->redirect($url2, $url3);
    say $job->url # $url2
    say $job->redirect_history # [$url1, $url3]

=head2 original_uri [DEPRECATED]

An alias for original_url.

=head2 original_url

Returns the original URL of redirected job. If redirected, returns last element
of redirect_histroy attribute, otherwise returns url attribute.

    $job1->redirect_history([$url1, $url2, $url3]);
    my $url4 = $job1->original_url; # $url4 is $url3

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) Sugama Keita.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
