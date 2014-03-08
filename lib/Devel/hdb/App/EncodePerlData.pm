package Devel::hdb::App::EncodePerlData;

use strict;
use warnings;

use Scalar::Util;

use Exporter qw(import);
our @EXPORT_OK = qw( encode_perl_data );

sub encode_perl_data {
    my $value = shift;
    my $path_expr = shift;
    my $seen = shift;

    if (!ref($value)) {
        my $ref = ref(\$value);
        # perl 5.8 - ref() with a vstring returns SCALAR
        if ($ref eq 'GLOB' or $ref eq 'VSTRING' or Scalar::Util::isvstring($value)) {
            my $copy = $value;
            $value = \$copy;
        }
    }

    $path_expr ||= '$VAR';
    $seen ||= {};

    if (ref $value) {
        my $reftype     = Scalar::Util::reftype($value);
        my $refaddr     = Scalar::Util::refaddr($value);
        my $blesstype   = Scalar::Util::blessed($value);

        if ($seen->{$value}) {
            my $rv = {  __reftype => $reftype,
                        __refaddr => $refaddr,
                        __recursive => 1,
                        __value => $seen->{$value} };
            $rv->{__blessed} = $blesstype if $blesstype;
            return $rv;
        }
        $seen->{$value} = $path_expr;

        # Build a new path string for recursive calls
        my $_p = sub {
            return '$'.$path_expr if ($reftype eq 'SCALAR' or $reftype eq 'REF');

            my @bracket = $reftype eq 'ARRAY' ? ( '[', ']' ) : ( '{', '}' );
            return sprintf('%s->%s%s%s', $path_expr, $bracket[0], $_, $bracket[1]);
        };

        if (my $tied = _is_tied($value, $reftype)) {
            local $_ = 'tied';  # &$_p needs this
            my $rv = {  __reftype => $reftype,
                        __refaddr => $refaddr,
                        __tied    => 1,
                        __value   => encode_perl_data($tied, &$_p, $seen) };
            $rv->{__blessed} = $blesstype if $blesstype;
            return $rv;
        }

        if ($reftype eq 'HASH') {
            $value = { map { $_ => encode_perl_data($value->{$_}, &$_p, $seen) } keys(%$value) };

        } elsif ($reftype eq 'ARRAY') {
            $value = [ map { encode_perl_data($value->[$_], &$_p, $seen) } (0 .. $#$value) ];

        } elsif ($reftype eq 'GLOB') {
            my %tmpvalue = map { $_ => encode_perl_data(*{$value}{$_}, &$_p, $seen) }
                           grep { *{$value}{$_} }
                           qw(HASH ARRAY SCALAR);
            if (*{$value}{CODE}) {
                $tmpvalue{CODE} = *{$value}{CODE};
            }
            if (*{$value}{IO}) {
                $tmpvalue{IO} = encode_perl_data(fileno(*{$value}{IO}));
            }
            $value = \%tmpvalue;
        } elsif (($reftype eq 'REGEXP')
                    or ($reftype eq 'SCALAR' and defined($blesstype) and $blesstype eq 'Regexp')
        ) {
            $value = $value . '';
        } elsif ($reftype eq 'CODE') {
            (my $copy = $value.'') =~ s/^(\w+)\=//;  # Hack to change CodeClass=CODE(0x123) to CODE=(0x123)
            $value = $copy;
        } elsif ($reftype eq 'REF') {
            $value = encode_perl_data($$value, &$_p, $seen );
        } elsif (($reftype eq 'VSTRING') or Scalar::Util::isvstring($$value)) {
            $reftype = 'VSTRING';
            $value = [ unpack('c*', $$value) ];
        } elsif ($reftype eq 'SCALAR') {
            $value = encode_perl_data($$value, &$_p, $seen);
        }

        $value = { __reftype => $reftype, __refaddr => $refaddr, __value => $value };
        $value->{__blessed} = $blesstype if $blesstype;
    }

    return $value;
}

sub _is_tied {
    my($ref, $reftype) = @_;

    my $tied;
    if    ($reftype eq 'HASH')   { $tied = tied %$ref }
    elsif ($reftype eq 'ARRAY')  { $tied = tied @$ref }
    elsif ($reftype eq 'SCALAR') { $tied = tied $$ref }
    elsif ($reftype eq 'GLOB')   { $tied = tied *$ref }

    return $tied;
}

1;

=pod

=head1 NAME

Devel::hdb::App::EncodePerlData - Encode Perl values in a -friendly way

=head1 SYNOPSIS

  use Devel::hdb::App::EncodePerlData qw(encode_perl_data);

  my $val = encode_perl_data($some_data_structure);
  $io->print( JSON::encode_json( $val ));

=head1 DESCRIPTION

This utility module is used to take an arbitrarily nested data structure, and
return a value that may be safely JSON-encoded.

=head2 Functions

=over 4

=item encode_perl_data

Accepts a single value and returns a value that may be safely passed to
JSON::encode_json().  encode_json() cannot handle Perl-specific data like
blessed references or typeglobs.  Non-reference scalar values like numbers
and strings are returned unchanged.  For all references, encode_perl_data()
returns a hashref with these keys
  __reftype     String indicating the type of reference, as returned
                by Scalar::Util::reftype()
  __refaddr     Memory address of the reference, as returned by
                Scalar::Util::refaddr()
  __blessed     Package this reference is blessed into, as returned
                by Scalar::Util::blessed.
  __value       Reference to the unblessed data.
  __tied        Flag indicating this variable is tied
  __recursive   Flag indicating this reference was seen before

If the reference was not blessed, then the __blessed key will not be present.
__value is generally a copy of the underlying data.  For example, if the input
value is an hashref, then __value will also be a hashref containing the input
value's kays and values.  For typeblobs and glob refs, __value will be a
hashref with the keys SCALAR, ARRAY, HASH, IO and CODE.  For coderefs,
__value will be the stringified reference, like "CODE=(0x12345678)".  For
v-strings and v-string refs, __value will by an arrayref containing the
integers making up the v-string.  For tied objects, __tied will be true
and __value will contain the underlying tied data.

if __recursive is true, then __value will contain a string representation
of the first place this reference was seen in the data structure.

encode_perl_data() handles arbitrarily nested data structures, meaning that
values in the __values slot may also be encoded this way.

=back

=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
