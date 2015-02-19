package WWW::Crawler::Mojo::ScraperUtil;
use strict;
use warnings;
use Mojo::Base -base;
use Encode qw(find_encoding);
use Exporter 'import';

our @EXPORT_OK = qw(resolve_href guess_encoding encoder decoded_body);

my $charset_re = qr{\bcharset\s*=\s*['"]?([a-zA-Z0-9_\-]+)['"]?}i;

sub decoded_body {
    my $res     = shift;
    return encoder(guess_encoding($res))->decode($res->body);
}

sub encoder {
    for (shift || 'utf-8', 'utf-8') {
        if (my $enc = find_encoding($_)) {
            return $enc;
        }
    }
}

sub guess_encoding {
    my $res     = shift;
    my $type    = $res->headers->content_type;
    return unless ($type);
    my $charset = ($type =~ $charset_re)[0];
    return $charset if ($charset);
    return _guess_encoding_html($res->body) if ($type =~ qr{text/(html|xml)});
    return _guess_encoding_css($res->body) if ($type =~ qr{text/css});
}

sub resolve_href {
    my ($base, $href) = @_;
    $href =~ s{\s}{}g;
    $href = ref $href ? $href : Mojo::URL->new($href);
    $base = ref $base ? $base : Mojo::URL->new($base);
    my $abs = $href->to_abs($base)->fragment(undef);
    while ($abs->path->parts->[0] && $abs->path->parts->[0] =~ /^\./) {
        shift @{$abs->path->parts};
    }
    $abs->path->trailing_slash($base->path->trailing_slash) if (!$href->path->to_string);
    return $abs;
}

sub _guess_encoding_css {
    return (shift =~ qr{^\s*\@charset ['"](.+?)['"];}is)[0];
}

sub _guess_encoding_html {
    my $head = (shift =~ qr{<head>(.+)</head>}is)[0] or return;
    my $charset;
    Mojo::DOM->new($head)->find('meta[http\-equiv=Content-Type]')->each(sub{
        $charset = (shift->{content} =~ $charset_re)[0];
    });
    return $charset;
}

use 5.010;

1;

=head1 NAME

WWW::Crawler::Mojo::ScraperUtil - Scraper utitlities

=head1 SYNOPSIS

=head1 DESCRIPTION

This class inherits L<Mojo::UserAgent> and override start method for storing
user info

=head1 ATTRIBUTES

WWW::Crawler::Mojo::UserAgent inherits all attributes from L<Mojo::UserAgent>.

=head1 METHODS

WWW::Crawler::Mojo::UserAgent inherits all methods from L<Mojo::UserAgent>.

=head2 decoded_body

Returns decoded response body for given L<Mojo::Message::Request> using
guess_encoding and encoder.

=head2 encoder

Generates L<Encode> instance for given name. Defaults to L<Encode::utf8>.

=head2 resolve_href

Resolves URLs with a base URL.

    WWW::Crawler::Mojo::resolve_href($base, $uri);

=head2 guess_encoding

Guesses encoding of HTML or CSS with given L<Mojo::Message::Response> instance.

    $encode = WWW::Crawler::Mojo::guess_encoding($res) || 'utf-8'

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) Sugama Keita.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
