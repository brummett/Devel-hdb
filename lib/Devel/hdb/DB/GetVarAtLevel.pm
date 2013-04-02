package Devel::hdb::DB::GetVarAtLevel;

use Devel::hdb::DB::Eval;

sub evaluate_complex_var_at_level {
    my($expr, $level) = @_;

    $level++;  # Don't count this stack level

    # try and figure out what vars we're dealing with
    my($sigil, $base_var, $open, $index, $close)
        = $expr =~ m/([\@|\$])(\w+)(\[|\{)(.*)(\]|\})/;

    my $varname = ($open eq '[' ? '@' : '%') . $base_var;
    my $var_value = get_var_at_level($varname, $level);
    return unless $var_value;

    my @indexes = split(/\s*,\s*/, $index);
    @indexes = map {
        if (m/(\S+)\s*\.\.\s*(\S+)/) {
            # it's a range
            my($first,$last) = ($1, $2);
            (get_var_at_level($first, $level) .. get_var_at_level($last, $level));
        } else {
            my $val = get_var_at_level($_, $level);
            ref($val) ? @$val : $val;
        }
    } @indexes;

    my @retval;
    if ($open eq '[') {
        # indexing the list
        @retval = @$var_value[@indexes];
    } else {
        # hash
        @retval = @$var_value{@indexes};
    }
    return (@retval == 1) ? $retval[0] : \@retval;
}

sub get_var_at_level {
    my($varname, $level) = @_;
    return if ($level < 0); # reject inspection into our frame

    require PadWalker;

    $level++;  # Don't count this stack level

    if ($varname !~ m/^[\$\@\%\*]/) {
        # not a variable at all, just return it
        return $varname;

    } elsif ($varname eq '@_' or $varname eq '@ARG') {
        # handle these special, they're implemented as local() vars, so we'd
        # really need to eval at some higher stack frame to inspect it if we could
        # (that would make this whole enterprise easier).  We can fake it by using
        # caller's side effect

        # Count how many eval frames are between here and there.
        # caller() counts them, but PadWalker does not
        for (my $i = 1; $i <= $level; $i++) {
            package DB;
            (caller($i))[3] eq '(eval)' and $level++;
        }
        my @args = @DB::args;
        return \@args;

    } elsif ($varname =~ m/\[|\}/) {
        # Not a simple variable name, maybe a complicated expression
        # like @list[1,2,3].  Try to emulate something like eval_at_level()
        return evaluate_complex_var_at_level($varname, $level);
    }

    my $h = PadWalker::peek_my( $level || 1);

    unless (exists $h->{$varname}) {
        # not a lexical, try our()
        $h = PadWalker::peek_our( $level || 1);
    }

    if (exists $h->{$varname}) {
        # it's a simple varname, padwalker found it
        if (ref($h->{$varname}) eq 'SCALAR' or ref($h->{$varname}) eq 'REF') {
            return ${ $h->{$varname} };
        } else {
            return $h->{$varname};
        }

    } else {
        # last chance, see if it's a package var

        if (my($sigil, $bare_varname) = ($varname =~ m/^([\$\@\%\*])(\w+)$/)) {
            # a varname without a pacakge, try in the package at
            # that caller level
            my($package) = caller($level+1);
            $package ||= 'main';

            my $expanded_varname = $sigil . $package . '::' . $bare_varname;
            $expanded_varname = Devel::hdb::DB::Eval::_fixup_expr_for_eval($expanded_varname);
            my @value = eval( $expanded_varname );
            return @value < 2 ? $value[0] : \@value;

        } elsif ($varname =~ m/^[\$\@\%\*]\w+(::\w+)*(::)?$/) {
            $varname = Devel::hdb::DB::Eval::_fixup_expr_for_eval($varname);
            my @value = eval($varname);
            return @value < 2 ? $value[0] : \@value;
        }
    }

}

1;
