package Devel::hdb::DB::Eval;

# This substitution is done so that we return HASH, as opposed to a list
# An expression of %hash results in a list of key/value pairs that can't
# be distinguished from a list.  A glob gets replaced by a glob ref.
sub _fixup_expr_for_eval {
    my($expr) = @_;

    $expr =~ s/^\s*([%*])/\\$1/o;
    return $expr;
}

package DB;

# Needs to live in package DB because of the way eval works.
# when run on package DB, it searches back for the first stack
# frame that's _not_ package DB, and evaluates the expr there.

sub eval {

    local($^W) = 0;  # no warnings

    $eval_string = Devel::hdb::DB::Eval::_fixup_expr_for_eval($eval_string);

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

        @result = eval "$usercontext $eval_string;\n";

        # restore old values
        $trace  = $orig_trace;
        $single = $orig_single;
        $^D     = $orig_cd;
    }

    my $exception = $@;  # exception from the eval
    # Since we're only saving $@, we only have to localize the array element
    # that it will be stored in.
    local $saved[0];    # Preserve the old value of $@
    eval { &DB::save };

    if ($exception) {
        return { exception => $exception };
    } elsif (@result == 1) {
        return { result => $result[0] };
    } else {
        return { result => \@result };
    }
}

1;
