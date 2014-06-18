package Devel::hdb::App::Control;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';
use Devel::hdb::Response;
use Devel::hdb::App::Stack qw(_serialize_stack);

__PACKAGE__->add_route('post', '/stepin', \&stepin);
__PACKAGE__->add_route('post', '/stepover', \&stepover);
__PACKAGE__->add_route('post', '/stepout', \&stepout);
__PACKAGE__->add_route('post', '/continue', \&continue);
__PACKAGE__->add_route('get', '/status', \&program_status);

sub stepin {
    my($class, $app, $env) = @_;

    $app->step;
    return $class->_delay_status_return_to_client($app, $env);
}

sub stepover {
    my($class, $app, $env) = @_;

    $app->stepover;
    return $class->_delay_status_return_to_client($app, $env);
}

sub stepout {
    my($class, $app, $env) = @_;

    $app->stepout;
    return $class->_delay_status_return_to_client($app, $env);
}

sub continue {
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $nostop = $req->param('nostop');

    $app->continue;
    if ($nostop) {
        $app->disable_debugger();
        $env->{'psgix.harakiri.commit'} = Plack::Util::TRUE;
        return [ 204,
                    [],
                    [],
                ];
    }

    return $class->_delay_status_return_to_client($app,$env);
}

sub program_status {
    my($class, $app, $env) = @_;

    my $status = $class->_program_status_data($app);
    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $app->encode_json($status) ] ];
}

sub _program_status_data {
    my($class, $app) = @_;

    my $location = $app->current_location;
    my $is_running = $location->at_end ? 0 : 1;
    my %status = (
        running => $is_running,
        filename => $location->filename,
        subroutine => $location->subroutine,
        line => $location->line,
    );

    my $events = $app->dequeue_events;
    if ($events and @$events) {
        $status{events} = $events;
    }

    if (my $exception = $app->uncaught_exception) {
        foreach my $prop (qw( exception package filename line subroutine )) {
            $status{$prop} = $exception->prop;
        }
    }
    return \%status;
}


sub _delay_status_return_to_client {
    my($class, $app, $env) = @_;

    return sub {
        my $responder = shift;
        my $writer = $responder->([ 200, [ 'Content-Type' => 'application/json' ]]);
        $env->{'psgix.harakiri.commit'} = Plack::Util::TRUE;

        my $cb = sub {
            my $status = $class->_program_status_data($app);
            $writer->write( $app->encode_json($status) );
            $writer->close();
        };
        $app->on_notify_stopped($cb);
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

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
