use warnings;
use strict;

package Devel::hdb::DB;

use Scalar::Util;
use IO::File;

use Devel::hdb::DB::Actionable;  # Breakpoints and Actions
use Devel::hdb::DB::Eval;
use Devel::hdb::DB::Stack;

my %attached_clients;
my %trace_clients;
my $is_initialized;
sub attach {
    my $self = shift;
    $attached_clients{$self} = $self;
    if ($is_initialized) {
        $self->init();
    }
    return $self;
}

sub detach {
    my $self = shift;
    delete $attached_clients{$self};
    delete $trace_clients{$self};
    $DB::trace = %trace_clients ? 1 : 0;
}

sub _clients {
    return values %attached_clients;
}

## Methods callable from client code

sub step {
    $DB::single=1;
}

sub stepover {
    $DB::single=1;
    $DB::step_over_depth = $DB::stack_depth;
}

sub stepout {
    $DB::single=0;
    $DB::step_over_depth = $DB::stack_depth - 1;
}

# Should support running to a subname, or file+line
sub continue {
    $DB::single=0;
}

sub trace {
    my $class = shift;
    my $rv;
    if (@_) {
        my $new_val = shift;
        if ($new_val) {
            # turning trace on
            $trace_clients{$class} = $class;
            $DB::trace = 1;
            $rv = 1;
        } else {
            # turning it off
            delete $trace_clients{$class};
            if (%trace_clients) {
                # No more clients requesting trace
                $DB::trace = 0;
            }
            $rv = 0;
        }

    } else {
        # Checking value
        $rv = exists $trace_clients{$class};
    }
    return $rv;
}

sub stack {
    return Devel::hdb::DB::Stack->new();
}

sub disable_debugger {
    # Setting $^P disables single stepping and subrouting entry
    # but if the program sets $DB::single explicitly, it'll still enter DB()
    $^P = 0;  # Stops single-stepping
    $DB::debugger_disabled = 1;
}

sub is_loaded {
    my($self, $filename) = @_;
    #no strict 'refs';
    return $main::{'_<' . $filename};
}

sub loaded_files {
    my @files = grep /^_</, keys(%main::);
    return map { substr($_,2) } @files; # remove the <_
}

sub is_breakable {
    my($class, $filename, $line) = @_;

    use vars qw(@dbline);
    local(*dbline) = $main::{'_<' . $filename};
    return $dbline[$line] + 0;   # FIXME change to == 0
}

sub add_break {
    my $self = shift;
    Devel::hdb::DB::Breakpoint->new(@_);
}

sub get_breaks {
    my $self = shift;
    my %params = @_;
    if (defined $params{file}) {
        return Devel::hdb::DB::Breakpoint->get(@_);
    } else {
        return map { Devel::hdb::DB::Breakpoint->get(@_, file => $_) }
                $self->loaded_files;
    }
}

sub remove_break {
    my $self = shift;
    if (ref $_[0]) {
        # given a breakpoint object
        shift->delete();
    } else {
        # given breakpoint params
        Devel::hdb::DB::Breakpoint->delete(@_);
    }
}

sub add_action {
    my $self = shift;
    Devel::hdb::DB::Action->new(@_);
}

sub remove_action {
    my $self = shift;
    if (ref $_[0]) {
        # given an action object
        shift->delete();
    } else {
        # given breakpoint params
        Devel::hdb::DB::Action->delete(@_);
    }
}

sub get_actions {
    my $self = shift;
    my %params = @_;
    if (defined $params{file}) {
        Devel::hdb::DB::Action->get(@_);
    } else {
        return map { Devel::hdb::DB::Action->get(@_, file => $_) }
                $self->loaded_files;
    }
}

sub subroutine_location {
    my $class = shift;
    my $subname = shift;

    return () unless $DB::sub{$subname};
    my($file, $start, $end) = $DB::sub{$subname} =~ m/(.*):(\d+)-(\d+)$/;
    return ($file, $start, $end);
}

# NOTE: This postpones until a named file is loaded.
# Have another interface for postponing until a module is loaded
sub postpone {
    my($class, $filename, $sub) = @_;

    if ($class->is_loaded($filename)) {
        # already loaded, run immediately
        $sub->($filename);
    } else {
        $DB::postpone_until_loaded{$filename} ||= [];
        push @{ $DB::postpone_until_loaded{$filename} }, $sub;
    }
}

sub user_requested_exit {
    $DB::user_requested_exit = 1;
}

sub file_source {
    my($class, $file) = @_;

    my $glob = $main::{'_<' . $file};
    return unless $glob;
    return *{$glob}{ARRAY};
}

## Methods called by the DB core - override in clients

sub init {}
sub poll {}
sub idle { 1;}
sub cleanup {}
sub notify_stopped {}
sub notify_resumed {}
sub notify_trace {}
sub notify_fork_parent {}
sub notify_fork_child {}
sub notify_program_terminated {}
sub notify_program_exit {}
sub notify_uncaught_exception {}

sub _do_each_client {
    my($method, @args) = @_;

    $_->$method(@args) foreach values %attached_clients;
}

package DB;

use vars qw( %dbline @dbline );

our($stack_depth,
    $single,
    $signal,
    $trace,
    $debugger_disabled,
    $no_stopping,
    $step_over_depth,
    $dbobj,
    $ready,
    @saved,
    $usercontext,
    $in_debugger,
    $finished,
    $user_requested_exit,
    $long_call,
    $eval_string,
    @AUTOLOAD_names,
    $sub,
    $uncaught_exception,
    $input_trace,
    %postpone_until_loaded,
);

BEGIN {
    $stack_depth    = 0;
    $single         = 0;
    $trace          = 0;
    $debugger_disabled = 0;
    $no_stopping    = 0;
    $step_over_depth = undef;
    $dbobj          = undef;
    $ready          = 0;
    @saved          = ();
    $usercontext    = '';
    $in_debugger    = 0;

    # Controlling program end of life
    $finished       = 0;
    $user_requested_exit = 0;

    # Used to postpone some action between calls to DB::DB:
    $long_call      = undef;
    $eval_string    = undef;

    # Remember AUTOLOAD sub names
    @AUTOLOAD_names = ();
}

sub save {
    # Save eval failure, command failure, extended OS error, output field
    # separator, input record separator, output record separator and
    # the warning setting.
    @saved = ( $@, $!, $^E, $,, $/, $\, $^W );

    $,  = "";      # output field separator is null string
    $/  = "\n";    # input record separator is newline
    $\  = "";      # output record separator is null string
    $^W = 0;       # warnings are off
}

sub restore {
    ( $@, $!, $^E, $,, $/, $\, $^W ) = @saved;
}

sub _line_offset_for_sub {
    my($line, $subroutine) = @_;
    no warnings 'uninitialized';
    if ($DB::sub{$subroutine} =~ m/(\d+)\-\d+$/) {
        return $line - $1;
    } else {
        return undef;
    }
}

sub _trace_report_line {
    my($package, $filename, $line, $subroutine) = @_;

    my $location;
    if (my $offset = _line_offset_for_sub($line, $subroutine)) {
        $location = "${subroutine}+${offset}";
    } else {
        $location = "${filename}:${line}";
    }

    return join("\t", $location, $package, $filename, $line, $subroutine);
}

sub input_trace_file {
    my($class, $file, $cb) = @_;
    my $fh = IO::File->new($file, 'r');
    unless ($fh) {
        warn "Can't open trace file $file for reading: $!";
    }
    $input_trace = sub {
        my($package, $filename, $line, $subroutine) = @_;

        my @line = split("\t", $fh->getline);
        my($offset, $expected_sub, $expected_offset, $should_stop);

        if (($expected_sub, $expected_offset) = $line[0] =~ m/(.*?)\+(\d+)/) {
            $offset = _line_offset_for_sub($line, $subroutine);
            $should_stop = ($expected_sub ne $subroutine or $expected_offset != $offset);
        } else {
            my($file, $fileline) = $line[0] =~ m/(.*)?\:(\d+)/;
            $should_stop = ($file ne $filename or $fileline != $line);
        }
        if ($should_stop) {
            my $diff_data = {
                'package'   => $package,
                filename    => $filename,
                line        => $line,
                subroutine  => $subroutine,
                sub_offset  => _line_offset_for_sub($line, $subroutine),
            };
            @$diff_data{'expected_package', 'expected_filename', 'expected_line',
                        'expected_subroutine','expected_sub_offset'}
                = (@line[1, 2, 3, 4], $expected_offset);
            $cb->($diff_data);
            undef $input_trace; # It's likely _every_ line will now be different
        }
        return $should_stop;
    };
    $trace = 1;
}

sub is_breakpoint {
    my($package, $filename, $line, $subroutine) = @_;

    if ($input_trace && $input_trace->($package, $filename, $line, $subroutine)) {
        return 1;
    }

    if ($single and defined($step_over_depth) and $step_over_depth < $stack_depth) {
        # This is from a step-over
        $single = 0;
        return 0;
    }

    if ($single || $signal) {
        $single = $signal = 0;
        return 1;
    }

    local(*dbline)= $main::{'_<' . $filename};

    my $should_break = 0;
    my $breakpoint_key = Devel::hdb::DB::Breakpoint->type;
    if ($dbline{$line} && $dbline{$line}->{$breakpoint_key}) {
        my @delete;
        foreach my $condition ( @{ $dbline{$line}->{$breakpoint_key} }) {
            next if $condition->inactive;
            my $code = $condition->code;
            if ($code eq '1') {
                $should_break = 1;
            } else {
                $eval_string = $condition->code;
                my $rv = &eval;
                $should_break = 1 if ($rv and $rv->{result});
            }
            push @delete, $condition if $condition->once;
        }
        $_->delete for @delete;
    }

    if ($should_break) {
        $single = $signal = 0;
    }
    return $should_break;
}

BEGIN {
    # Code to get control when the debugged process forks
    *CORE::GLOBAL::fork = sub {
        my $pid = CORE::fork();
        return $pid unless $ready;
        my $app = Devel::hdb::App->get();
        my $tracker;
        if ($pid) {
            $app->notify_fork_parent($pid);
        } elsif (defined $pid) {
            $long_call = undef;   # Cancel any pending long call in the child
            $app->notify_fork_child();

        }

        # These should make it stop after returning from the fork
        # It's cut-and-paste from Devel::hdb::App::stepout()
        $DB::single=0;
        $DB::step_over_depth = $DB::stack_depth - 1;
        $tracker = _new_stack_tracker($pid);
        return $pid;
    };
};

# NOTE: Look into trapping $SIG{__DIE__} se we can report
# untrapped exceptions back to the debugger.
# inside the handler, note the value for $^S:
# undef - died while parsing something
# 1 - died while executing an eval
# 0 - Died not inside an eval
# We could re-throw the die if $^S is 1
$SIG{__DIE__} = sub {
    if (defined($^S) && $^S == 0) {
        my $exception = $_[0];
        # It's interesting to note that if we pass an arg to caller() to
        # find out the offending subroutine name, then the line reported
        # changes.  Instead of reporting the line the exception occured
        # (which it correctly does with no args), it returns the line which
        # called the function which threw the exception.
        # We'll work around it by calling it twice
        my($package, $filename, undef, $subname) = caller(1);
        my(undef, undef, $line, undef) = caller(0);
        $subname = 'MAIN' unless defined($subname);
        $uncaught_exception = {
            'package'   => $package,
            line        => $line,
            filename    => $filename,
            exception   => $exception,
            subroutine  => $subname,
        };
        # After we fall off the end, the interpreter will try and exit,
        # triggering the END block that calls DB::fake::at_exit()
    }
};


sub disable_stopping {
    my $class = shift;
    $no_stopping = shift;
}


sub _execute_actions {
    my($filename, $line) = @_;
    local(*dbline) = $main::{'_<' . $filename};
    if ($dbline{$line} && $dbline{$line}->{action}) {
        my @delete;
        foreach my $action ( @{ $dbline{$line}->{action}} ) {
            next if $action->inactive;
            $eval_string = $action->code;
            &eval;
            push @delete, $action if $action->once;
        }
        $_->delete for @delete;
    }
}

sub DB {
    return if (!$ready or $debugger_disabled);

    my($package, $filename, $line) = caller;

    unless ($is_initialized) {
        $is_initialized = 1;
        Devel::hdb::DB::_do_each_client('init');
    }

    local $usercontext =
        'no strict; no warnings; ($@, $!, $^E, $,, $/, $\, $^W) = @DB::saved;' . "package $package;";

    _execute_actions($filename, $line);

    my(undef, undef, undef, $subroutine) = caller(1);
    $subroutine ||= 'MAIN';
    if ($trace && ! $input_trace) {
        my $fh = (ref($trace) and $trace->can('print')) ? $trace : \*STDERR;
        $fh->print( _trace_report_line($package, $filename, $line, $subroutine), "\n");
    }

    $_->notify_trace($filename, $line, $subroutine) foreach values(%trace_clients);

    return if $no_stopping;

    if (! is_breakpoint($package, $filename, $line, $subroutine)) {
        return;
    }
    $step_over_depth = undef;
#    $DB::saved_stack_depth = $stack_depth;

    save();

    # set up the context for DB::eval, so it can properly execute
    # code on behalf of the user. We add the package in so that the
    # code is eval'ed in the proper package (not in the debugger!).
    if ($package eq 'DB::fake') {
        $package = 'main';
    }

    Devel::hdb::DB::_do_each_client('notify_stopped', $filename, $line, $subroutine);

    STOPPED_LOOP:
    foreach (1) {
        local($in_debugger) = 1;
        if ($DB::long_call) {
            $DB::long_call->();
            undef $DB::long_call;
        }

        undef $eval_string;

        my $should_continue = 0;
        until ($should_continue) {
            my @ready_clients = grep { $_->poll($filename, $line, $subroutine) } values %attached_clients;
            last STOPPED_LOOP unless (@ready_clients);
            do { $should_continue |= $_->idle($filename, $line, $subroutine) } foreach @ready_clients;
        }

        redo if ($finished || $eval_string);
    }
    Devel::hdb::DB::_do_each_client('notify_resumed', $filename, $line, $subroutine);
    restore();
}

sub sub {
    no strict 'refs';
    goto &$sub if (! $ready or index($sub, 'hdbStackTracker') == 0 or $debugger_disabled);

    local @AUTOLOAD_names = @AUTOLOAD_names;
    if (index($sub, '::AUTOLOAD', -10) >= 0) {
        my $caller_pkg = substr($sub, 0, length($sub)-8);
        my $caller_AUTOLOAD = ${ $caller_pkg . 'AUTOLOAD'};
        unshift @AUTOLOAD_names, $caller_AUTOLOAD;
    }
    my $stack_tracker;
    unless ($in_debugger) {
        my $tmp = $sub;
        $stack_depth++;
        $stack_tracker = _new_stack_tracker($tmp);
    }

    return &$sub;
}

sub _new_stack_tracker {
    my $token = shift;
    my $self = bless \$token, 'hdbStackTracker';
}

sub hdbStackTracker::DESTROY {
    $stack_depth--;
    $single = 1 if (defined($step_over_depth) and $step_over_depth >= $stack_depth);
}

# Count how many stack frames we should discard when we're
# interested in the debugged program's stack frames
sub _first_program_frame {
    for(my $level = 1;
        my ($package, $filename, $line, $subroutine) = caller($level);
        $level++
    ) {
        if ($subroutine eq 'DB::DB') {
            return $level;
        }
    }
    return;
}


sub get_var_at_level {
    my($class, $varname, $level) = @_;

    require Devel::hdb::DB::GetVarAtLevel;
    return Devel::hdb::DB::GetVarAtLevel::get_var_at_level($varname, $level+1);
}


# This gets called after a require'd file is compiled, but before it's executed
# it's called as DB::postponed(*{"_<$filename"})
# We can use this to break on module load, for example.
# If $DB::postponed{$subname} exists, then this is called as
# DB::postponed($subname)
sub postponed {
    my($filename) = ($_[0] =~ m/_\<(.*)$/);

    if (my $actions = delete $postpone_until_loaded{$filename}) {
        $_->($filename) foreach @$actions;
    }
}

sub long_call {
    my $class = shift;
    if (@_) {
        $DB::long_call = shift;
    }
    return $DB::long_call;
}

sub prepare_eval {
    my($class, $string, $cb) = @_;

    () = caller(_first_program_frame() );
    my @db_args = @DB::args;
    return sub {
        $eval_string = $string;
        @_ = @db_args;
        my $data = &eval;
        $cb->($data);
    }
}


END {
    $trace = 0;

    return if $debugger_disabled;

    $single=0;
    $finished = 1;
    $in_debugger = 1;

    eval {
        Devel::hdb::DB::_do_each_client('notify_uncaught_exception', $uncaught_exception) if $uncaught_exception;

        if ($user_requested_exit) {
            Devel::hdb::DB::_do_each_client('notify_program_exit');
        } else {
            Devel::hdb::DB::_do_each_client('notify_program_terminated', $?);
            # These two will trigger DB::DB and the event loop
            $in_debugger = 0;
            $single=1;
            DB::fake::at_exit();
        }
    }
}

package DB::fake;
sub at_exit {
    1;
}

package DB;
BEGIN { $DB::ready = 1; }

1;

__END__

=pod

=head1 NAME

Devel::hdb::DB - Programmatic interface to the Perl debugging API

=head1 SYNOPSIS

  package CLIENT;
  use base 'Devel::hdb::DB';

  # These inherited methods can be called by the client class
  CLIENT->attach();             # Register with the debugging system
  CLIENT->detach();             # Un-register with the debugging system
  CLIENT->step();               # single-step into subs
  CLIENT->stepover();           # single-step over subs
  CLIENT->stepout();            # Return from the current sub, then stop
  CLIENT->continue();           # Run until the next breakpoint
  CLIENT->trace([$flag]);       # Get/set the trace flag
  CLIENT->disable_debugger();   # Deactivate the debugging system
  CLIENT->is_loaded($file);     # Return true if the file is loaded
  CLIENT->loaded_files();       # Return a list of loaded file names
  CLIENT->postpone($file, $subref);     # Run $subref->() when $file is loaded
  CLIENT->is_breakable($file, $line);   # Return true if the line is executable
  CLIENT->stack();              # Return Devel::hdb::DB::Stack

  CLIENT->add_break(%params);   # Create a breakpoint
  CLIENT->get_breaks([%params]);# Get breakpoint info
  CLIENT->remove_break(...);    # Remove a breakpoint
  CLIENT->add_action(%params);  # Create a line-action
  CLIENT->get_actions([%params]);  # Get line-action info
  CLIENT->remove_action(...);   # Remove a line-action

  # These methods are called by the debugging system at the appropriate time.
  # Base-class methods do nothing.  These methods must not block.
  CLIENT->init();                       # Called when the debugging system is ready
  CLIENT->poll($file, $line, $sub);     # Return true if there is user input
  CLIENT->idle($file, $line, $sub);     # Handle user interaction (can block)
  CLIENT->notify_trace($file, $line, $sub);   # Called on each executable statement
  CLIENT->notify_stopped($file, $line, $sub); # Called when a break has occured
  CLIENT->notify_resumed($file, $line, $sub); # Called before the program gets control after a break
  CLIENT->notify_fork_parent($pid);     # Called after fork() in parent
  CLIENT->notify_fork_child();          # Called after fork() in child
  CLIENT->notify_program_terminated($?);    # Called as the program is finishing 
  CLIENT->notify_program_exit();        # Called as the program is exiting
  CLIENT->notify_uncaught_exception($exc);  # Called after an uncaught exception

=head1 DESCRIPTION

This class is meant to expose the Perl debugger API used by debuggers,
tracers, profilers, etc so they can all benefit from common code.  It
supports multiple "front-ends" using the API together.

=head1 CONSTRUCTOR

This class does not supply a constructor.  Clients wishing to use this API
must inherit from this class and call the C<attach> method.  They may use
whatever mechanism they wish to implement their object or class.

=head1 API Methods

These methods are provided by the debugging API and may be called as inherited
methods by clients.

=over 4

=item CLIENT->attach()

Attaches a client to the debugging API.  May be called as a class or instance
method.  When later client methods are called by the debugging API, the
same invocant will be used.

=item CLIENT->detach()

Removes a client from the debugging API.  The invocant must match a previous
C<attach> call.

=item CLIENT->trace([1 | 0])

Get or set the trace flag.  If trace is on, the client will get notified
before every executable statement by having its C<notify_trace> method called.

=item CLIENT->disable_debugger()

Turn off the debugging system.  The debugged program will continue normally.
The debugger system will not be triggered afterward.

=item CLIENT->postpone($file, $subref)

Causes C<$subref> to be called when $file is loaded.  If $file is already
loaded, then $subref will be called immediately.


=back

=head2 Program control methods

=over 4

=item CLIENT->step()

Single-step the next statement in the debugged program.  If the next statement
is a subroutine call, the debugger will stop on its first executable statement.

=item CLIENT->stepover()

Single-step the next statement in the debugged program.  If the next statement
is a subroutine call, the debugger will stop on its first executable statement
after that subroutine call returns.

=item CLIENT->stepout()

Continue running the debugged program until the current subroutine returns
or until the next breakpoint, whichever comes first.

=item CLIENT->continue()

Continue running the debugged program until the next breakpoint.

=item CLIENT->user_requested_exit()

Sets a flag that indicates the program should completely exit after the
debugged program ends.  Normally, the debugger will regain control after the
program ends.

=back

=head2 Informational methods

=item CLIENT->is_loaded($file)

Return true if the file is loaded

=item CLIENT->loaded_files()

Return a list of loaded file names

=item CLIENT->is_breakable($file, $line)

Return true if the line has an executable stament.  Only lines with executable
statements may have breakpoints.  In particular, line containing only comments,
whitespace or block delimiters are typically not breakable.

=item CLIENT->subroutine_location($subroutine)

Return a list containing ($filename, $start_line, $end_line) for where the
named subroutine was defined.  Can be called either with a fullt qualified
function name or with the package and name separate.

IF the named function does not exist, it returns a nempty list.

=item CLIENT->stack()

Return an instance of L<Devel::hdb::DB::Stack>.  This object represents the
execution/call stack of the debugged program.

=back

=head2 Breakpoints and Actions

=item CLIENT->add_break(%params)

Create a breakpoint.  The %params are passed along to the
L<Devel::hdb::DB::Breakpoint> constructor.  Returns the Breakpoint instance.

Lines may contain more than one breakpoint.  The debugger will stop before
the next statement on a line if that line contains a breakpoint, and one of
the breakpoint conditions evaluates to true.  Unconditional breakpoints
generally have the condition "1" so they are always true.

=item  CLIENT->get_breaks([%params]);

Return a list of L<Devel::hdb::DB::Breakpoint> instances.  This is a wrapper
around the C<get> method of Devel::hdb::DB::Breakpoint

=item CLIENT->remove_break(...)

Remove a breakpoint.  This is a wrapper around the C<delete> method of
L<Devel::hdb::DB::Breakpoint>.

=item CLIENT->add_action(%params)

Create a line-action.  The %params are passed along to the
L<Devel::hdb::DB::Action> constructor.  Returns the Action instance.

Lines may contain more than one action.  Before the next statement on a line,
all the actions are executed and the values are ignored, though they may have
other side-effects.

=item CLIENT->get_actions([%params])

Return a list of L<Devel::hdb::DB::Action> instances.  This is a wrapper
around the C<get> method of Devel::hdb::DB::Action

=item CLIENT->remove_action(...)

Remove an action.  This is a wrapper around the C<delete> method of
L<Devel::hdb::DB::Action>.

=back

=head CLIENT METHODS

These methods exist in the base class, but only as empty stubs.  They are
called at the appropriate time by the debugging system.  Clients should
provide their own implementation.

With the exception of C<idle>, these client-provided methods must not block
so that other clients may get called.

=over 4

=item CLIENT->init()

Called before the first breakpoint, usually before the first executable
statement in the debugged program.  Its return value is ignored

=item CLIENT->poll($file, $line, $subroutine)

Called when the debugger is stopped on a line.  This method should return
true to indicate that it wants its C<idle> method called.

=item CLIENT->idle($file, $line, $subroutine)

Called when the client can block, to accept and process user input, for
example.  This method should return true to indicate to the debugger system
that it has finished processing, and that it is OK to continue the debugged
program.  The loop around calls to C<idle> will stop when all clients return
true.

=item CLIENT->notify_trace($file, $line, $subroutine)

If a client has turned on the trace flag, this method will be called before
each executable statement.  The return value is ignored.

notify_trace() will be called only on clients that have requested tracing by
calling CLIENT->trace(1).

=item CLIENT->notify_stopped($file, $line, $subroutine)

This method is called when a breakpoint has occured.  Its return value is
ignored.

=item CLIENT->notify_resumed($file, $line, $subroutine)

This method is called after a breakpoint, after any calls to C<idle>, and
just before the debugged program resumes execution.  The return value is
ignored.

=item CLIENT->notify_fork_parent($pid)

This method is called immediately after the debugged program calls fork()
in the context of the parent process.  C<$pid> is the child process ID
created by the fork.  The return value is ignored

=item CLIENT->notify_fork_child()

This method is called immediately after the debugged program calls fork()
in the context of the child process.  The return value is ignored.

=item CLIENT->notify_program_terminated($?)

This method is called after the last executable statement in the debugged
program.  After all clients are notified, the debugger system emulates
one final breakpoint inside a function called C<at_exit> and the program
remains running, though stopped.

=item CLIENT->notify_program_exit()

If the user

  CLIENT->notify_uncaught_exception
package'   => $package,
            line        => $line,
            filename    => $filename,
            exception   => $exception,
            subroutine  => $subname,

