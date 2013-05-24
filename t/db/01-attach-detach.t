use strict;
use warnings;

use Test::More tests => 26;

my $c = TestDB->new();
ok($c, 'Create new debugger object');

ok($c->attach, 'attach()');
is(scalar($c->_clients), 1, 'client list has 1 item');
is(($c->_clients)[0], $c, ' ... and is the new debugger');

ok($c->attach, 'attach() again');
is(scalar($c->_clients), 1, 'client list still has 1 item');
is(($c->_clients)[0], $c, ' ... and is the new debugger');

my $c2 = TestDB->new();
ok($c2, 'Create second debugger object');
ok($c2->attach(), 'attach() second debugger object');

is(scalar($c->_clients), 2, 'client list has 2 items');
is_deeply([ sort $c->_clients ], [ sort ($c, $c2) ], 'Client list has both debugger objects');


ok(TestDB->attach(), 'attach() with a class name');
is(scalar($c->_clients), 3, 'client list has 3 items');
is_deeply([ sort $c->_clients ], [ sort ($c, $c2, 'TestDB') ], 'Client list has all three debugger objects');

ok(TestDB->detach(), 'detach() on the class name');
is(scalar($c->_clients), 2, 'client list has 2 items');
ok(! TestDB->detach(), 'detach() on the class name again returns false');
is(scalar($c->_clients), 2, 'client list still has 2 items');

ok($c->detach(), 'detach() on the first debugger object');
is(scalar($c->_clients), 1, 'client list has 1 item');
ok(! $c->detach(), 'detach() on the first debugger object again');
is(scalar($c->_clients), 1, 'client list still has 1 item');

ok($c2->detach(), 'detach() on the second debugger object');
is(scalar($c->_clients), 0, 'client list is empty');
ok(! $c2->detach(), 'detach() on the second debugger object again');
is(scalar($c->_clients), 0, 'client list is still empty');

package TestDB;

use Devel::hdb::DB;
BEGIN {
    our @ISA = qw(Devel::hdb::DB);
}

sub new {
    return bless {}, shift;
}

1;

