use warnings;
use strict;

package Devel::hdb::DB;

use Scalar::Util;
use IO::File;

use Devel::hdb::DB::Actionable;  # Breakpoints and Actions
use Devel::hdb::DB::Eval;
use Devel::hdb::DB::Stack;

my %attached_clients;
sub attach {
    my $self = shift;
    $attached_clients{$self} = $self;
}

sub detach {
    my $self = shift;
    delete $attached_clients{$self};
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

sub continue {
    $DB::single=0;
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

sub trace {}
sub init {}
sub poll {}
sub idle { 1;}
sub cleanup {}
sub notify_stopped {}
sub notify_resumed {}
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

my $is_initialized;
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

    Devel::hdb::DB::_do_each_client('notify_stopped', $filename, $line);

    do {
        local($in_debugger) = 1;
        if ($DB::long_call) {
            $DB::long_call->();
            undef $DB::long_call;
        }

        undef $eval_string;

        my $should_continue = 0;
        until ($should_continue) {
            my @ready_clients = grep { $_->poll($filename, $line) } values %attached_clients;
            do { $should_continue |= $_->idle($filename, $line) } foreach @ready_clients;
        }

    } while ($finished || $eval_string);
    $_->notify_resumed($filename, $line) foreach (values %attached_clients);
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
