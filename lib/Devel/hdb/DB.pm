use warnings;
use strict;

package Devel::hdb::DB;

package DB;
no strict;

use vars qw( %dbline @dbline );

BEGIN {
    $DB::stack_depth    = 0;
    $DB::single         = 0;
    $DB::step_over_depth = -1;
    $DB::dbobj          = undef;
    $DB::ready          = 0;
    @DB::stack          = ();
    $DB::deep           = 100;
    @DB::saved          = ();
    $DB::usercontext    = '';
    $DB::in_debugger    = 0;
    # These are set from caller inside DB::DB()
    $DB::package        = '';
    $DB::filename       = '';
    $DB::line           = '';

    # Controlling program end of life
    $DB::finished       = 0;
    $DB::user_requested_quit = 0;

    # Used to postpone some action between calls to DB::DB:
    $DB::long_call      = undef;
}

#sub stack_depth {
#    my $class = shift;
#    $stack_depth = shift if (@_);
#    return $stack_depth;
#}
#
#sub step_over_depth {
#    my $class = shift;
#    $step_over_depth = shift if (@_);
#    return $step_over_depth;
#}
#
#sub single {
#    my $class = shift;
#    $single = shift if (@_);
#    return $single;
#}

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

sub is_breakpoint {
    my($package, $filename, $line) = @_;

    if ($single and $step_over_depth >= 0 and $step_over_depth < $stack_depth) {
        # This is from a step-over
        $single = 0;
        return 0;
    }

    if ($single || $signal) {
        $single = $signal = $tracking_step_over = 0;
        return 1;
    }

    local(*dbline) = $main::{'_<' . $filename};

    if ($dbline{$line}) {
        my($is_break) = split("\0", $dbline{$line});
        if ($is_break eq '1') {
            return 1
        } else {
            # eval $is_break in user's context here
        }
    }
    return;
}

sub DB {
    return unless $ready;

    local($package, $filename, $line) = caller;

    if (! is_breakpoint($package, $filename, $line)) {
        return;
    }
    $step_over_depth = -1;
    $DB::saved_stack_depth = $stack_depth;

    save();

    # set up the context for DB::eval, so it can properly execute
    # code on behalf of the user. We add the package in so that the
    # code is eval'ed in the proper package (not in the debugger!).
    if ($package eq 'DB::fake') {
        $package = 'main';
    }
    local $usercontext =
        '($@, $!, $^E, $,, $/, $\, $^W) = @saved;' . "package $package;";

    if ($DB::long_call) {
        $DB::long_call->();
        undef $DB::long_call;
    }
    unless ($dbobj) {
        $dbobj = Devel::hdb::App->new();
    }
    do {
        local($in_debugger) = 1;
        $dbobj->run();
    } while ($finished);
    restore();
}

sub sub {
    goto &$sub if (! $ready or index($sub, 'hdbStackTracker') == 0);

    my $stack_tracker;
    unless ($in_debugger) {
        my $tmp = $sub;
        $stack_depth++;
        if ($step_over_depth >= 0 and $step_over_depth < $stack_depth) {
            $stack_tracker = \$tmp;
            bless $stack_tracker, 'hdbStackTracker';
        }
    }

    return &$sub;
}

sub hdbStackTracker::DESTROY {
    $DB::stack_depth--;
    $DB::single = 1 if ($DB::step_over_depth > 0 and $DB::step_over_depth >= $stack_depth);
}

sub set_breakpoint {
    my($class, $filename, $line, $condition) = @_;

    local(*dbline) = $main::{'_<' . $filename};

    no warnings 'uninitialized';
    my(undef, $action) = split("\0", $dbline{$line});
    if ($action) {
        $dbline{$line} = "${condition}\0${action}";
    } else {
        $dbline{$line} = $condition;
    }

    return 1;
}

sub get_breakpoint {
    my($class, $filename, $line) = @_;

    no strict 'refs';
    local(*dbline) = $main::{'_<' . $filename};

    my($condition, $action) = split("\0", $dbline{$line});
    return $condition;
}

sub is_breakable {
    my($class, $filename, $line) = @_;

    no strict 'refs';
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
    my($class, $cb) = @_;
    $DB::long_call = $cb;
}

sub user_requested_exit {
    $user_requested_exit = 1;
}

END {
    $single=0;
    $finished = 1;
    print "Debugged program terminated with exit code $?\n";

    if ($long_call) {
        if ($user_requested_exit) {
            $long_call->({ type => 'hangup'});
        } else {
            $long_call->({ type => 'termination', data => { exit_code => $? }});
            $exit_code = $?;
            # These two will trigger DB::DB and the event loop
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
