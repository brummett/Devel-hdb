use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 7;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp;

my $stack = $client->stack();
ok($stack, 'Request stack position');
my $filename = $stack->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

$resp = $client->create_breakpoint( filename => $filename, line => 2, code => '$a != 3' );
ok($resp, 'Set conditional breakpoint on line 2 for $a != 3');

$resp = $client->create_breakpoint( filename => $filename, line => 4, code => '$a != 3' );
ok($resp, 'Set conditional breakpoint on line 4 for $a != 3');

$resp = $client->create_breakpoint( filename => $filename, line => 6, code => '$a != 3' );
ok($resp, 'Set conditional breakpoint on line 6 for $a != 3');


$resp = $client->continue();
is_deeply($resp,
    { filename => $filename, line => 2, subroutine => 'MAIN', running => 1, stack_depth => 1 },
    'continue to line 2');

$resp = $client->continue();
is_deeply($resp,
    { filename => $filename, line => 6, subroutine => 'MAIN', running => 1, stack_depth => 1 },
    'continue to line 6');


__DATA__
$a = 1;
2;
$a = 3;
4;
$a = 5;
5;

