use warnings;
use strict;

package Devel::hdb;

use Devel::hdb::App;
use Devel::hdb::DB;
use IO::Socket::INET;

sub import {
    my $class = shift;

    while (@_) {
        my $param = shift;
        if ($param =~ m/port:(\d+)/) {
            our $PORT = $1;
        } elsif ($param =~ m/host:([\w.]+)/) {
            our $HOST = $1;
        } elsif ($param eq 'a') {
            our $HOST = inet_ntoa(INADDR_ANY);
        } elsif ($param eq 'testharness') {
            our $TESTHARNESS = 1;
        }
    }
}
1;
__END__

=pod

=head1 NAME

Devel::hdb - Perl debugger as a web page and REST service

=head1 DESCRIPTION

hdb is a Perl debugger that uses HTML and javascript to implement the GUI.
This front-end talks to a REST service provided by the debugger running with
the Perl code.

=head1 SYNOPSIS

To debug a Perl program, start it like this:

    perl -d:hdb youprogram.pl

It will print a message on STDERR with the URL the debugger is listening to.
Point you web browser at this URL and it will being up the debugger GUI.
It defaults to listening on localhost port 8080; to use a different port,
start it like this:

    perl -d:hdb=port:9876 yourprogram.pl

To specify a particular IP address to listen on:

    perl -d:hdb=host:192.168.0.123 yourprogram.pm

And to listen on any interface:

    perl -d:hdb=a yourprogram.pm

=head2 Interface

The GUI is divided into three main parts: Control buttons, Code browser and
Watch expressions.

=over 4

=item Control buttons

=over 4

=item Step In

Causes the debugger to execute the next line and stop.  If the next line is a
subroutine call, it will stop at the first executable line in the subroutine.

=item Step Over

Causes the debugger to execute the next line and stop.  If the next line is a
subroutine call, it will step over the call and stop when the subroutine
returns.

=item Step Out

Causes the debugger to run the program until it returns from the current
subroutine.

=item Run

Resumes execution of the program until the next breakpoint.

=item Exit

The debugged program immediately exits.  The GUI in the web browser remains
running.

=back

=item Code Browser

Most of the interface is taken up by the code browser.  Tabs along the top
show one file at a time.  The "+" next to the last tab brings up a dialog
to choose another file to open.  Click the "x" next to a file name to close
that tab.  NOTE: loading additional files is not implemented yet.

The first tab is special: it shows the stack frames of the currently
executing program and cannot be closed.  The stack tab itself has tabs along
the left, one tab for each stack frame; the most recent frame is at the top.

Each of these tabs shows a Code Pane.  The line numbers on the left are struck
through if that line is not breakable.  For breakable lines, clicking on the
line number will set an unconditional breakpoint and turn the number red.
Right-clicking on a breakable line number will bring up a menu where a
breakpoint condition and action can be set.  Lines with conditional breakpoints
are blue.  Lines with actions habe a circle outline.

=item Watch Expressions

The right side of the GUI shows watch expressions.  To add a new expression to
the watch window, click on the "+".  To remove a watched expression, click on
the "x" next to its name.  Hashes and arrays have a blue circled number
indicating how many elements belong to it.  To collapse them, click the blue
cicle.

=back
