package Devel::hdb::App::Stack;

BEGIN {
    our @saved_ARGV = @ARGV;
}

use strict;
use warnings;

use base 'Devel::hdb::App::Base';


use Exporter 'import';
our @EXPORT_OK = qw(_serialize_stack);

use Data::Transform::ExplicitMetadata qw(encode);

__PACKAGE__->add_route('get', qr{(^/stack$)}, \&stack);

sub stack {
    my($class, $app, $env, $base_url) = @_;

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $app->encode_json($class->_serialize_stack($app, $base_url)) ]
        ];
}

sub _serialize_stack {
    my($class, $app, $base_url) = @_;
    my $frames = $app->stack()->iterator;
    my @stack;
    my $level = 0;
    while (my $frame = $frames->()) {
        push @stack, _serialize_frame($frame, $base_url, $level++);
    }
    return \@stack;
}

sub _serialize_frame {
    my($frame, $base_url, $level) = @_;

    my %frame = %$frame; # copy

    if ($frame{autoload}) {
        $frame{subname} .= "($frame{autoload})";
    }

    my @encoded_args = map { encode($_) } @{$frame{args}};
    $frame{args} = \@encoded_args;

    $frame{href} = join('/', $base_url, $level++);

    return \%frame;
}

1;

=pod

=head1 NAME

Devel::hdb::App::Stack - Get information about the program stack

=head1 DESCRIPTION

=head2 Routes

=over 4

=item /stack

Get a list of the current program stack.  Does not include any stack frames
within the debugger.  The currently executing frame is the first element in
the list.  Returns a JSON-encoded array where each item is a hash
with the following keys:
  package       Package/namespace
  subroutine    Fully-qualified subroutine name.  Includes the package
  subname       Subroutine name without the package included
  filename      File where the subroutine was defined
  lineno        Line execution is stopped on
  args          Array of arguments to the subroutine

The top-level stack frame is reported as being in the subroutine named 'MAIN'.

Values in the args list are encoded using Devel::hdb::App::EncodePerlData.

=back

=head1 SEE ALSO

Devel::hdb, Devel::hdb::App::EncodePerlData

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
