## Devel::hdb

A Perl graphical debugger that uses an HTTP REST interface

## Usage

Start a program with the debugger

    shell> perl -d:hdb yourprogram.pl
    Debugger listening on http://127.0.0.1:8080/debugger-gui

Tell the debugger to use a different port

    shell> perl -d:hdb=port:9876 yourprogram.pl
    Debugger listening on http://127.0.0.1:9876/debugger-gui

## How to use it

Operation of the interface should be straightforward, though there are a few
controls that may not be obvious.

### Breakpoints and actions

Clicking on a line number will toggle an unconditional breakpoint for that line.
Right-clicking on a line number will bring up a form to enter a breakpoint
expression and action.  When the expression evaluates true, the debugger will
stop on that line.

A line number with a red circle is an unconditional breakpoint.  A blue circle
is a conditional breakpoint.  The circle is dimmed if the breakpoint is
inactive, and outlined if that line has an action.  Actions are executed
before the statement on that line is executed, and the action's result is
ignored.

Click on the thick border between the code and watch expression panes to slide
out the breakpoint list.

### Watch Expressions

Click on the "+" to add a new watch expression.

Double-click on an existing expression to edit the expression.

For arrays, hashes and globs, click on the blue circle to collapse/expand it

Click on the checkbox to turn the expression into a watchpoint.  Execution
will stop if the expression's value changes.  Watchpoint values are evaluated
in list context.  Execution will stop if the list's length changes or if any
of the first-level elements changes values.  It will not recurse further down
into data structures.

### Stack

The current stack is shown to the left of the code pane.  The inital program
frame, not part of any function, is called "MAIN".  Entering into a function
will add a new function name to the top of the list, so that the function the
debugger is currently stopped in is always at the top of the list.  Mousing
over the function name will pop up information showing the full name of the
function and what line execution has reached in that frame.

Function names are prepended by a sigil indicating their context/wantarray-ness.
String eval frames are represented as `"eval"`.

Clicking on the yellow bar at the top of a code pane will scroll the code to
show the currently executing line in that frame.

### Mouseover variables

Resting the pointer on a Perl variable in the code pane will show its value.
When looking at a stack frame other than the most recent, it will show the
value from that stack frame.

### Child Processes

If the debugged program forks, it will pop up a dialog giving the option to
"Open" a new debugger window, or "Detach" and allow it to run without
stopping.

## Features

* Single step, step over, step out, continue and exit the debugged program
* Set breakpoints dynamically in the running program
* Inspect the current position at any level in the call stack
* Watch variables/expressions
* Get control when the process exits
* Hover over a variable to see its value.  Works for all stack frames.
* Get notification of untrapped exceptions, and stop at the exception point
* Stop execution when execution reaches a different point than a previous run

Pretty much what you would expect from any debugger.

### Planned Features

* Step into an arbitrary expression
* Restart execution at some prior execution point

## Implementation

The debugger is split into two major parts.

* Devel::hdb::App - Implements the REST interface.  It is a Plack app, and uses
    HTTP::Server::PSGI as the web server.  It's a subclass of Devel::Chitin,
    which supplies the low-level debuggung facilities.
* The user interface is HTML and JavaScript code that lives under Devel/hdb/html/.
    It makes requests to the REST interface.
