package Devel::hdb::DB::GetVarAtLevel;

use strict;
use warnings;

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

    my @indexes = _parse_index_expression($index, $level);

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

# Parse out things that could go between the brackets/braces in
# an array/hash expression.  Hopefully this will be good enough,
# otherwise we'll need a real grammar
my %matched_close = ( '(' => '\)', '[' => '\]', '{' => '\}');
sub _parse_index_expression {
    my($string, $level) = @_;

    $level++;  # don't count this level
    my @indexes;
    if ($string =~ m/qw([([{])\s*(.*)$/) {       # @list[qw(1 2 3)]
        my $close = $matched_close{$1};
        $2 =~ m/(.*)\s*$close/;
        @indexes = split(/\s+/, $1);
    } elsif ($string =~ m/(\S+)\s*\.\.\s*(\S+)/) { # @list[1 .. 4]
        @indexes = (_parse_index_element($1, $level) .. _parse_index_element($2, $level));
    } else {                            # @list[1,2,3]
        @indexes = map { _parse_index_element($_, $level) }
                    split(/\s*,\s*/, $string);
    }
    return @indexes;
}

sub _parse_index_element {
    my($string, $level) = @_;

    if ($string =~ m/^(\$|\@|\%)/) {
        my $value = get_var_at_level($string, $level+1);
        return _dereferenced_value($string, $value);
    } elsif ($string =~ m/('|")(\w+)\1/) {
        return $2;
    } else {
        return $string;
    }
}

sub _dereferenced_value {
    my($string, $value) = @_;
    my $sigil = substr($string, 0, 1);
    if (($sigil eq '@') and (ref($value) eq 'ARRAY')) {
        return @$value;

    } elsif (($sigil eq '%') and (ref($value) eq 'HASH')) {
        return %$value;

    } else {
        return $value;
    }
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
            # a varname without a package, try in the package at
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
