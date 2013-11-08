package Devel::hdb::App::Control;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';
use Devel::hdb::Response;
use Devel::hdb::App::Stack qw(_stack);

__PACKAGE__->add_route('get', '/stack', \&stack);
__PACKAGE__->add_route('get', '/stepin', \&stepin);
__PACKAGE__->add_route('get', '/stepover', \&stepover);
__PACKAGE__->add_route('get', '/stepout', \&stepout);
__PACKAGE__->add_route('get', '/continue', \&continue);

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
        my $resp = Devel::hdb::Response->new('continue', $env);
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
            my $resp = Devel::hdb::Response->new('stack', $env);
            $resp->data( $class->_stack($app) );
            $writer->write( $resp->encode );
            $writer->close();
        });
    };
}


1;

=pod

=head1 NAME

Devel::hdb::App::Control - Control execution of the debugged program

=head1 DESCRIPTION

Registers routes for methods to control execution of the debugged program

=head2 Routes

=over 4

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
execution pauses at the first statement following the unwinding.

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
