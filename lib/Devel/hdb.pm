use warnings;
use strict;

package Devel::hdb;

use Devel::hdb::App;
use Devel::hdb::DB;

sub import {
    my $class = shift;

    while (@_) {
        my $param = shift;
        if ($param =~ m/port:(\d+)/) {
            our $PORT = $1;
        } elsif ($param eq 'testharness') {
            our $TESTHARNESS = 1;
        }
    }
}
1;
