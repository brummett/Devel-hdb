package Devel::hdb::App::Control;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';
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
                    [$app->_parent_process_base_url
                        ? ('Access-Control-Allow-Origin' => $app->_parent_process_base_url)
                        : ()
                    ],
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
    my $stack = $app->stack;
    my %status = (
        running => $is_running,
        filename => $location->filename,
        subroutine => $location->subroutine,
        line => $location->line,
        stack_depth => $stack->depth,
    );

    my $events = $app->dequeue_events;
    if ($events and @$events) {
        $status{events} = $events;
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

=item GET /status

Get status information about the debugged program.  Returns 200 and a
JSON-encoded hash in the body with these keys:
  running     => True if the program is running, false if terminated
  subroutine  => Name of the subroutine the program is stopped in
  filename    => Name of the file the program is stopped in
  line        => Line number the program is stopped on
  stack_depth => How deep the program stack currently is
  events      => Array of program events since the last status report

For each event, there will be a hash describing the event.  All events have
a 'type' key.  The other keys are type-specific.

=over 2

=item fork

Immediately after the debugged program fork()s.
        type     => "fork"
        pid      => Child process ID
        href     => URL to communicate with the child process debugger
        gui_href => URL to bring up the child process GUI
        href_continue => URL to GET to tell the child to run without stopping

=item exception

When the program generates an uncaught exception
        type       => "exception"
        value      => Value of the exception
        package    => Location where the exception occurred
        filename   => ...
        subroutine => ...
        line       => ...

=item watchpoint

When a watchpoint expression changes value.  The location reported is
whichever line had executed immediately before the current program
line - likely the line that caused the change.
        type       => "watchpoint"
        expr       => Expression that changed value
        old        => Listref of the previous value
        new        => Listref of the new value
        package    => Location where the value was changed
        filename   => ...
        subroutine => ...
        line       => ...

=item exit

When the program is terminating
        type       => "exit"
        value      => Program exit code

=item hangup

When the program is exiting and will not respond to further requests.
        type       => "hangup"

=item trace_diff

When run in follow mode and an execution difference has happened.
        type       => "trace_diff"
        filename   => Where the program is stopped now
        line       => ...
        package    => ...
        subroutine => ...
        sub_offset => ...
        expected_filename   => where the trace expected to be instead
        expected_line       => ...
        expected_package    => ...
        expected_subroutine => ...

=back

=item POST /stepin

Causes the debugger to execute the current statement and pause before the
next.  If the current statement involves a function call, execution stops
at the first line inside the called function.

Returns 200 and the same JSON hash as GET /status

=item POST /stepover

Causes the debugger to execute the current statement and pause before the
next.  If the current statement involves function calls, these functions
are run to completion and execution stops before the next statement at
the current stack level.  If execution of these functions leaves the current
stack frame, usually from an exception caught at a higher frame or a goto,
execution pauses at the first statement following the unwinding.

Returns 200 and the same JSON hash as GET /status

=item POST /steoput

Causes the debugger to start running continuously until the current stack
frame exits.

Returns 200 and the same JSON hash as GET /status

=item POST /continue

Causes the debugger to start running continuously until it encounters another
breakpoint.

Returns 200 and the same JSON hash as GET /status

=item POST /continue?nostop=1

Request the debugger continue execution.  The param nostop=1 instructs the
debugger to run the program to completion and not stop at any breakpoints.

Returns 204 if successful.

=back

=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
