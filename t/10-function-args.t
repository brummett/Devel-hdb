use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 3;
}

my $url = start_test_program('arg1', 'arg2');
my $client = Devel::hdb::Client->new(url => $url);

my $resp;

my $stack = $client->stack();
$stack = strip_stack_inc_args($stack);
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN', args => ['arg1', 'arg2'] } ],
    'Stopped on line 1');

$resp = $client->continue();
ok($resp, 'continue');
$stack = strip_stack_inc_args($client->stack);

is_deeply($stack,
  [ { line => 6, subroutine => 'main::foo', args => [1, 'one', { two => 2 } ] },
    { line => 2, subroutine => 'main::MAIN', args => ['arg1','arg2'] } ],
    'Stopped on line 6, frame above is line 2');


__DATA__
1;
foo(1,'one', { two => 2 });
3;
sub foo {
    $DB::single=1;
    6;
}
