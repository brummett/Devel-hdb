use warnings;
use strict;

package Devel::hdb::DB;

use Scalar::Util;
use IO::File;

use Devel::hdb::DB::Eval;

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

sub file_source {
    my($class, $file) = @_;

    my $glob = $main::{'_<' . $file};
    return unless $glob;
    return *{$glob}{ARRAY};
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

    if ($dbline{$line}) {
        return if $dbline{$line}->{condition_inactive};

        my($condition) = $dbline{$line}->{condition};
        return unless $condition;
        # TODO - allow user to set 1-time unconditional BP for run-to
        # see perl5db.pl and search for ";9"
        if ($condition eq '1') {
            return 1
        } elsif (length($condition)) {
            $eval_string = $condition;
            my $result = &eval;
            if ($result->{result}) {
                $single = $signal = 0;
                return 1;
            }
        }
    }
    return;
}

BEGIN {
    # Code to get control when the debugged process forks
    *CORE::GLOBAL::fork = sub {
        my $pid = CORE::fork();
        return $pid unless $ready;
        my $app = Devel::hdb::App->get();
        my $tracker;
        if ($pid) {
            $app->notify_parent_child_was_forked($pid);
        } elsif (defined $pid) {
            $long_call = undef;   # Cancel any pending long call in the child
            $app->notify_child_process_is_forked();

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

sub DB {
    return if (!$ready or $debugger_disabled);

    my($package, $filename, $line) = caller;

    local $usercontext =
        'no strict; no warnings; ($@, $!, $^E, $,, $/, $\, $^W) = @DB::saved;' . "package $package;";

    # Run any action associated with this line
    local(*dbline) = $main::{'_<' . $filename};
    my $action;
    if ($dbline{$line}
        && ($action = $dbline{$line}->{action})
        && (! $dbline{$line}->{action_inactive})
        && $action
    ) {
        $eval_string = $action;
        &eval;
    }

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

    $dbobj = Devel::hdb::App->get();

    do {
        local($in_debugger) = 1;
        if ($DB::long_call) {
            $DB::long_call->();
            undef $DB::long_call;
        }

        undef $eval_string;
        $dbobj->run();

    } while ($finished || $eval_string);
    restore();
}

sub sub {
    no strict 'refs';
    goto &$sub if (! $ready or index($sub, 'hdbStackTracker') == 0 or $debugger_disabled);

    local @AUTOLOAD_names = @AUTOLOAD_names;
    if (index($sub, '::AUTOLOAD', -10) >= 0) {
        my $caller_pkg = substr($sub, 0, length($sub)-8);
        my $caller_AUTOLOAD = ${ $caller_pkg . 'AUTOLOAD'};
        push @AUTOLOAD_names, $caller_AUTOLOAD;
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

    our %postpone_until_loaded;
    if (my $actions = delete $postpone_until_loaded{$filename}) {
        $_->() foreach @$actions;
    }
}

sub postpone_until_loaded {
    my($class, $filename, $sub) = @_;

    our %postpone_until_loaded;
    $postpone_until_loaded{$filename} ||= [];

    push @{ $postpone_until_loaded{$filename} }, $sub;
}

sub set_breakpoint {
    my $class = shift;
    my $filename = shift;
    my $line = shift;
    my %params = @_;

    local(*dbline) = $main::{'_<' . $filename};

    if (exists $params{condition}) {
        if ($params{condition}) {
            $dbline{$line}->{condition} = $params{condition};
        } else {
            delete $dbline{$line}->{condition};
        }
    }
    if (exists $params{condition_inactive}) {
        if ($params{condition_inactive}) {
            $dbline{$line}->{condition_inactive} = 1;
        } else {
            delete $dbline{$line}->{condition_inactive}
        }
    }
    if (exists $params{action}) {
        if ($params{action}) {
            $dbline{$line}->{action} = $params{action};
        } else {
            delete $dbline{$line}->{action};
        }
    }
    if (exists $params{action_inactive}) {
        if ($params{action_inactive}) {
            $dbline{$line}->{action_inactive} = 1;
        } else {
            delete $dbline{$line}->{action_inactive}
        }
    }

    unless (keys %{ $dbline{$line} }) {
        $dbline{$line} = undef;
    }

    return 1;
}

sub get_breakpoint {
    my $class = shift;

    my $filename = shift;
    unless ($filename) {
        return map { $class->get_breakpoint($_) } $class->loaded_files;
    }

    #no strict 'refs';
    local(*dbline) = $main::{'_<' . $filename};

    my $line = shift;
    if ($line) {
        if ($dbline{$line}) {
            my %bp = map { exists $dbline{$line}->{$_} ? ( $_ => $dbline{$line}->{$_} ) : () }
                        qw(condition action condition_inactive action_inactive);
            return { filename => $filename, lineno => $line, %bp };
        }

    } else {
        my @bps;
        while( my($line, $bpdata) = each( %dbline ) ) {
            next unless $bpdata;
            my %bp = map { exists $bpdata->{$_} ? ( $_ => $bpdata->{$_} ) : () }
                        qw(condition action condition_inactive action_inactive);
            push @bps, { filename => $filename, lineno => $line, %bp };
        }
        return @bps;
    }
}

sub is_breakable {
    my($class, $filename, $line) = @_;

    #no strict 'refs';
    local(*dbline) = $main::{'_<' . $filename};
    return $dbline[$line] + 0;
}

sub is_loaded {
    my($class, $filename) = @_;
    no strict 'refs';
    return $main::{'_<' . $filename};
}

sub loaded_files {
    my @files = grep /^_</, keys(%main::);
    return map { substr($_,2) } @files; # remove the <_
}

sub long_call {
    my $class = shift;
    if (@_) {
        $DB::long_call = shift;
    }
    return $DB::long_call;
}

sub user_requested_exit {
    $user_requested_exit = 1;
}

sub prepare_eval {
    my($class, $string, $cb) = @_;

    my @db_args = @DB::args;
    return sub {
        $eval_string = $string;
        @_ = @db_args;
        my $data = &eval;
        $cb->($data);
    }
}

sub disable_debugger {
    # Setting $^P disables single stepping and subrouting entry
    # bug if the program sets $DB::single explicitly, it'll still enter DB()
    $^P = 0;  # Stops single-stepping
    $debugger_disabled = 1;
}


END {
    $trace = 0;

    return if $debugger_disabled;

    $single=0;
    $finished = 1;
    $in_debugger = 1;

    if ($user_requested_exit) {
        Devel::hdb::App->get()->notify_program_exit();
    } else {
        Devel::hdb::App->get()->notify_program_terminated($?, $uncaught_exception);
        # These two will trigger DB::DB and the event loop
        $in_debugger = 0;
        $single=1;
        DB::fake::at_exit();
    }
}

package DB::fake;
sub at_exit {
    1;
}

package DB;
BEGIN { $DB::ready = 1; }

1;
