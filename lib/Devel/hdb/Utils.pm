package Devel::hdb::Utils;

# This substitution is done so that we return HASH, as opposed to a list
# An expression of %hash results in a list of key/value pairs that can't
# be distinguished from a list.  A glob gets replaced by a glob ref.
sub _fixup_expr_for_eval {
    my($expr) = @_;

    $expr =~ s/^\s*(?<!\\)([%*])/\\$1/o;
    return $expr;
}

1;
