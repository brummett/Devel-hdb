package Devel::hdb::Logger;

our $VERSION = '0.23_08';

use Exporter 'import';
our @EXPORT_OK = qw(log);

use Scalar::Util qw(reftype);

sub log {
    return unless $ENV{HDB_DEBUG_MSG};
    my $subname = (caller(1))[3];
    print STDERR '[', $subname, '] ';
    print STDERR join('', map { _dump_value($_) } @_), "\n";
}

our $indent = 0;
sub _dump_value {
    my $val = shift;

    if (my $type = ref($val)) {
        if ($type eq 'ARRAY') {
            return _dump_array($val);
        } elsif ($type eq 'HASH') {
            return _dump_hash($val);
        } elsif ($type eq 'SCALAR') {
            return _dump_scalar($val);
        } else {
            return $val;
        }
    } else {
        return $val;
    }
}

sub _dump_array {
    my $val = shift;
    my $str = '[ ';
    for (my $i = 0; $i < @$val; $i++) {
        $str .= _dump_value($val->[$i]);
        $str .= ', ' unless $i == $#$val;
    }
    return($str . ' ]');
}

sub _dump_hash {
    my $val = shift;
    my $str = '{ ';
    my @keys = keys %$val;
    for (my $i = 0; $i < @keys; $i++) {
        $str .= $k . ' => ' . _dump_value($val->{$k});
        $str .= ', ' unless $i == $#keys;
    }
    return($str . ' }');
}

sub _dump_scalar {
    return('\\' . _dump_value(shift()));
}

1;
