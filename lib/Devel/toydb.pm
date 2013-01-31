use warnings;
use strict;

package Devel::toydb;

package DB;

our $stack_depth = 0;
our $single = 0;
sub DB {
    my($package, $filename, $line) = caller;

    print "In file $filename on line $line depth $stack_depth\n";
    print "About to execute: ".$main::{'_<' . $filename}[$line];
}

sub sub {
    our $sub;
    local $stack_depth = $stack_depth + 1;

    print "Entering function $sub, stack depth $stack_depth\n";
    my(@ret,$ret);
    my $wantarray = wantarray;
    {
        no strict 'refs';
        if ($wantarray) {
            @ret = &$sub;
        } elsif (defined $wantarray) {
            $ret = &$sub;
        } else {
            &$sub;
            undef $ret;
        }
    }

    $stack_depth--;
    print "Leaving function $sub, stack depth is now $stack_depth\n";

    return $wantarray ? @ret : $ret;
}

1;
