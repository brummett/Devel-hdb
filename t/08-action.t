use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 13;
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

$resp = eval { $client->create_action( filename => $filename, line => 7, code => '$a++' ) };
ok(! $resp && $@, 'Cannot set action on unbreakable line');
is($@->http_code, 403, 'Error was Forbidden');

$resp = eval { $client->create_action( filename => 'garbage', line => 123, code => '$a++' ) };
ok(! $resp && $@, 'Cannot set action on unknown file');
is($@->http_code, 404, 'Error was Not Found');

my $action_4 = $client->create_action( filename => $filename, line => 4, code => '$a++' );
ok($action_4, 'Set action for line 4');

my $action_6 = $client->create_action( filename => $filename, line => 6, code => '$a++' );
ok($action_6, 'Set action for line 6');


$resp = $client->continue();
is($resp->{line}, 3, 'continue to line 3');
$resp = $client->eval('$a');
is($resp, 1, 'Get value of $a');

$resp = $client->continue();
# Make sure it didn't stop on line 4 - it has an action but no breakpoint
is($resp->{line}, 6, 'continue to line 6');

$resp = $client->eval('$a');
is($resp, 3, 'Get value of $a - action incremented it to 3');


$resp = $client->delete_action($action_4);
ok($resp, 'Delete action on line 4');

$resp = $client->get_actions();
is_deeply($resp,
    [ { filename => $filename, line => 6, code => '$a++', inactive => 0, href => $action_6 } ],
    'One action remaining');


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
