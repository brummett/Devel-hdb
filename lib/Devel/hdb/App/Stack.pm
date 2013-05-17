package Devel::hdb::App::Stack;

BEGIN {
    our @saved_ARGV = @ARGV;
}

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Devel::hdb::Response;

use Exporter 'import';
our @EXPORT_OK = qw(_stack);

use Devel::hdb::App::EncodePerlData qw(encode_perl_data);

__PACKAGE__->add_route('get', '/stack', \&stack);

sub stack {
    my($class, $app, $env) = @_;

    my $resp = Devel::hdb::Response->new('stack', $env);
    $resp->data( $class->_stack($app) );

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
        ];
}

sub _stack {
    my $class = shift;
    my $app = shift;

    my $discard = 1;
    my @stack;
    my $next_AUTOLOAD_name = $#DB::AUTOLOAD_names;
    our @saved_ARGV;

    for (my $i = 0; ; $i++) {
        my %caller;
        {
            package DB;
            @caller{qw( package filename line subroutine hasargs wantarray
                        evaltext is_require )} = caller($i);
        }
        last unless defined ($caller{line});
        # Don't include calls within the debugger
        if ($caller{subroutine} eq 'DB::DB') {
            $discard = 0;
        }
        next if $discard;

        $caller{args} = [ map { encode_perl_data($_) } @DB::args ]; # unless @stack;
        $caller{subname} = $caller{subroutine} =~ m/\b(\w+$|__ANON__)/ ? $1 : $caller{subroutine};
        if ($caller{subname} eq 'AUTOLOAD') {
            $caller{subname} .= '(' . ($DB::AUTOLOAD_names[ $next_AUTOLOAD_name-- ] =~ m/::(\w+)$/)[0] . ')';
        }
        $caller{level} = $i;

        push @stack, \%caller;
    }
    # TODO: put this into the above loop
    for (my $i = 0; $i < @stack-1; $i++) {
        @{$stack[$i]}{'subroutine','subname','args'} = @{$stack[$i+1]}{'subroutine','subname','args'};
    }
    $stack[-1]->{subroutine} = 'MAIN';
    $stack[-1]->{subname} = 'MAIN';
    $stack[-1]->{args} = \@saved_ARGV; # These are guaranteed to be simple scalars, no need to encode
    return \@stack;
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
  subroutine    Fully-qualified subroutine name.  Includes the pacakge
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

Copyright 2013, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
