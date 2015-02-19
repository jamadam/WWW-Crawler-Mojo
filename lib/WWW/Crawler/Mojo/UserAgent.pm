package WWW::Crawler::Mojo::UserAgent;
use strict;
use warnings;
use Mojo::Base 'Mojo::UserAgent';
use Mojo::URL;
use 5.010;

has active_conn => 0;
has active_conns_per_host => sub { {} };
has credentials => sub {{}};
has keep_credentials => 1;

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    
    if ($self->keep_credentials) {
        $self->on(start => sub {
            my ($self, $tx) = @_;
            my $url = $tx->req->url;
            my $host_key = _host_key($url) or return;
            if ($url->userinfo) {
                $self->credentials->{$host_key} = $url->userinfo;
            } else {
                $url->userinfo($self->credentials->{$host_key});
            }
        });
    }
    
    $self->on(start => sub {
        my ($self, $tx) = @_;
        my $url = $tx->req->url;
        $self->active_host($url, 1);
        $tx->on(finish => sub { $self->active_host($url, -1) });
    });
    
    return $self;
}

sub active_host {
    my ($self, $url, $inc) = @_;
    my $key = _host_key($url);
    my $hosts = $self->active_conns_per_host;
    if ($inc) {
        $self->{active_conn} += $inc;
        $hosts->{$key} += $inc;
        delete($hosts->{$key}) unless ($hosts->{$key});
    }
    return $hosts->{$key} || 0;
}

sub _host_key {
    state $well_known_ports = {http => 80, https => 443};
    my $url = shift;
    $url = Mojo::URL->new($url) unless ref $url;
    return unless $url->is_abs && (my $wkp = $well_known_ports->{$url->scheme});
    my $key = $url->scheme. '://'. $url->ihost;
    return $key unless (my $port = $url->port);
    $key .= ':'. $port if $port != $wkp;
    return $key;
}

1;

=head1 NAME

WWW::Crawler::Mojo::UserAgent - Mojo::UserAgent sub class for userinfo storage

=head1 SYNOPSIS

    my $ua = WWW::Crawler::Mojo::UserAgent->new;
    $ua->keep_credentials(1);
    $ua->credentials->{'http://example.com:80'} = 'jamadam:password';
    my $tx = $ua->get('http://example.com/');
    say $tx->req->url # http://jamadam:passowrd@example.com/

=head1 DESCRIPTION

This class inherits Mojo::UserAgent and override start method for storing user
info

=head1 ATTRIBUTES

WWW::Crawler::Mojo::UserAgent inherits all attributes from Mojo::UserAgent.

=head2 active_conn

A number of current connections.

    $bot->active_conn($bot->active_conn + 1);
    say $bot->active_conn;

=head2 active_conns_per_host

A number of current connections per host.

    $bot->active_conns_per_host($bot->active_conns_per_host + 1);
    say $bot->active_conns_per_host;

=head2 keep_credentials

Set true to set the feature on, defaults to 1.

    $ua->keep_credentials(1);

=head2 credentials

Storage for credentials.

    $ua->credentials->{'http://example.com:80'} = 'jamadam:password';

=head1 METHODS

WWW::Crawler::Mojo::UserAgent inherits all methods from Mojo::UserAgent.

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) Sugama Keita.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
