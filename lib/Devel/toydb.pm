use warnings;
use strict;

package Devel::toydb;

package DB;
no strict;

BEGIN {
    $DB::stack_depth    = 0;
    $DB::single         = 0;
    $DB::dbobj          = undef;
    $DB::ready          = 0;
    @DB::stack          = ();
    $DB::deep           = 100;
}

sub DB {
    return unless $ready;

    my($package, $filename, $line) = caller;

    print "In file $filename on line $line depth $stack_depth\n";
    print "About to execute: ".$main::{'_<' . $filename}[$line];
}

sub sub {
    &$sub unless ($ready);

    # Using the same trick perl5db uses to preserve the single step flag
    # even in the cse where multiple stack frames are unwound, as in an
    # an eval that catches an exception thrown many sub calls down
    local $stack_depth = $stack_depth + 1;
    $#stack = $stack_depth;
    $stack[-1] = $single;

    # Turn off all flags except single-stepping
    $single &= 1;

    # If we've gotten really deeply recursed, turn on the flag that will
    # make us stop with the 'deep recursion' message.
    $single |= 4 if $stack_depth == $deep;

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

    $single |= $stack[ $stack_depth-- ];
    print "Leaving function $sub, stack depth is now $stack_depth\n";

    return $wantarray ? @ret : $ret;
}

BEGIN { $DB::ready = 1; }
END { $DB::ready = 0; }

1;
