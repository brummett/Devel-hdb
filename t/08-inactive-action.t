use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 8;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp;

my $stack = $client->stack();
my $filename = $stack->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

my $action_4 = $client->create_action( filename => $filename, line => 4, code => '$a++' );
ok($action_4, 'Create action for line 4');

$resp = $client->change_action($action_4, inactive => 1);
ok($resp, 'Change action for line 4 to inactive');

$resp = $client->create_action( filename => $filename, line => 6, code => '$a++' );
ok($resp, 'Create action for line 6');


$resp = $client->continue();
ok($resp, 'continue');

$resp = $client->eval('$a');
is($resp, 1, '$a value is correct');

$resp = $client->continue();
# Make sure it didn't stop on line 4 - it has an action but no breakpoint
is($resp->{line}, 6, 'continue to line 6');

$resp = $client->eval('$a');
is($resp, 2, 'Get value of $a - action incremented $a');


__DATA__
my $a = 1;
$DB::single=1;
3;
4;
$DB::single=1;
6;
sub foo {
    8;
}
