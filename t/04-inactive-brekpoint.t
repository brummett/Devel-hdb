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
ok($stack, 'Request stack position');
my $filename = $stack->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

my $bp = $client->create_breakpoint( filename => $filename, line => 6, code => 1 );
ok($bp, 'Set breakpoint on line 6');

$resp = $client->continue();
is_deeply($resp,
    { filename => $filename, line => 6, subroutine => 'main::foo', running => 1, stack_depth => 2 },
    'Continue to line 6 breakpoint');

$resp = $client->change_breakpoint($bp, inactive => 1 );
is_deeply($resp,
    { filename => $filename, line => 6, code => 1, inactive => 1, href => $bp },
    'set breakpoint to inactive');


$resp = $client->continue();
is_deeply($resp,
    { filename => $filename, line => 4, subroutine => 'MAIN', running => 1, stack_depth => 1 },
    'Continue to  line 4, in-code $DB::single');


$resp = $client->change_breakpoint($bp, inactive => 0 );
is_deeply($resp,
    { filename => $filename, line => 6, code => 1, inactive => 0, href => $bp },
    'set breakpoint back to active');


$resp = $client->continue();
is_deeply($resp,
    { filename => $filename, line => 6, subroutine => 'main::foo', running => 1, stack_depth => 2 },
    'Continue to line 6 breakpoint');




__DATA__
foo();
foo();
$DB::single=1;
foo();
sub foo {
    6;
    7;
}

