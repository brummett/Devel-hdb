package Devel::hdb::App::Control;

BEGIN {
    our @saved_ARGV = @ARGV;
}

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

__PACKAGE__->add_route('get', '/stack', \&stack);
__PACKAGE__->add_route('get', '/stepin', \&stepin);
__PACKAGE__->add_route('get', '/stepover', \&stepover);
__PACKAGE__->add_route('get', '/stepout', \&stepout);
__PACKAGE__->add_route('get', '/continue', \&continue);

sub stack {
    my($class, $app, $env) = @_;

    my $resp = $app->_resp('stack', $env);
    $resp->data( $class->_stack($app) );

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
        ];
}

sub stepin {
    my($class, $app, $env) = @_;

    $DB::single=1;
    return $class->_delay_stack_return_to_client($app, $env);
}

sub stepover {
    my($class, $app, $env) = @_;

    $DB::single=1;
    $DB::step_over_depth = $DB::stack_depth;
    return $class->_delay_stack_return_to_client($app, $env);
}

sub stepout {
    my($class, $app, $env) = @_;

    $DB::single=0;
    $DB::step_over_depth = $DB::stack_depth - 1;
    return $class->_delay_stack_return_to_client($app, $env);
}

sub continue {
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $nostop = $req->param('nostop');

    $DB::single=0;
    if ($nostop) {
        DB->disable_debugger();
        my $resp = Devel::hdb::App::Response->new('continue', $env);
        $resp->data({ nostop => 1 });
        $env->{'psgix.harakiri.commit'} = Plack::Util::TRUE;
        return [ 200,
                    [ 'Content-Type' => 'application/json'],
                    [ $resp->encode() ]
                ];
    }

    return $class->_delay_stack_return_to_client($app,$env);
}

sub _delay_stack_return_to_client {
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $rid = $req->param('rid');

    my $json = $app->{json};
    return sub {
        my $responder = shift;
        my $writer = $responder->([ 200, [ 'Content-Type' => 'application/json' ]]);
        $env->{'psgix.harakiri.commit'} = Plack::Util::TRUE;

        DB->long_call( sub {
            my $resp = Devel::hdb::App::Response->new('stack', $env);
            $resp->data( $class->_stack($app) );
            $writer->write( $resp->encode );
            $writer->close();
        });
    };
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

        $caller{args} = [ map { $app->_encode_eval_data($_) } @DB::args ]; # unless @stack;
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

Devel::hdb::App::Control - Control execution of the debugged program

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

Complex subroutine arguments like typeglobs and references are encoded as a
hash (regardless of the actual type) containing additional metadata about
the value that is not expressable with normal JSON-encoding, like the
reference address and what package it is blessed into.

=item /stepin

Causes the debugger to execute the current statement and pause before the
next.  If the current statement involves a function call, execution stops
at the first line inside the called function.

=item /stepover

Causes the debugger to execute the current statement and pause before the
next.  If the current statement involves function calls, these functions
are run to completion and execution stops before the next statement at
the current stack level.  If execution of these functions leaves the current
stack frame, usually from an exception caught at a higher frame or a goto,
execution pauses at the first staement following the unwinding.

=item /steoput

Causes the debugger to start running continuously until the current stack
frame exits.

=item /continue

Causes the debugger to start running continuously until it encounters another
breakpoint.  /continue accepts one optional argument C<nostop>; if true, the
debugger gets out of the way of the debugged process and will not stop for
any reason.

=back

=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2013, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
