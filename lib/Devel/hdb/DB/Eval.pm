package Devel::hdb::DB::Eval;

use strict;
use warnings;

package DB;

our($single, $trace, $usercontext, @saved);

# Needs to live in package DB because of the way eval works.
# when run on package DB, it searches back for the first stack
# frame that's _not_ package DB, and evaluates the expr there.

sub _eval_in_program_context {
    my($eval_string, $wantarray, $cb) = @_;

    local($^W) = 0;  # no warnings

    my @result;
    {
        # Try to keep the user code from messing  with us. Save these so that
        # even if the eval'ed code changes them, we can put them back again.
        # Needed because the user could refer directly to the debugger's
        # package globals (and any 'my' variables in this containing scope)
        # inside the eval(), and we want to try to stay safe.
        my $orig_trace   = $trace;
        my $orig_single  = $single;
        my $orig_cd      = $^D;

        # Untaint the incoming eval() argument.
        { ($eval_string) = $eval_string =~ /(.*)/s; }

        # Fill in the appropriate @_
        () = caller(_first_program_frame() );
        @_ = @DB::args;

        if ($wantarray) {
            my @eval_result = eval "$usercontext $eval_string;\n";
            $result[0] = \@eval_result;
        } elsif (defined $wantarray) {
            my $eval_result = eval "$usercontext $eval_string;\n";
            $result[0] = $eval_result;
        } else {
            eval "$usercontext $eval_string;\n";
            $result[0] = undef;
        }

        # restore old values
        $trace  = $orig_trace;
        $single = $orig_single;
        $^D     = $orig_cd;
    }

    $result[1] = $@;  # exception from the eval
    # Since we're only saving $@, we only have to localize the array element
    # that it will be stored in.
    local $saved[0];    # Preserve the old value of $@
    eval { &DB::save };

    $cb->(@result) if $cb;
    return @result;
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

1;
