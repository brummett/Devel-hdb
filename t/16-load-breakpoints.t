use strict;
use warnings;

use lib 't';
use HdbHelper;
use IO::File;
use Data::Dumper;
use Devel::hdb::App;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 10;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp;

my $stack = $client->stack();
ok($stack, 'Request stack position');
my $program_file_name = $stack->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 2, subroutine => 'main::MAIN' } ],
    'Stopped on line 2');

my $config = {
    breakpoints => [
        { filename => $program_file_name, line => 3, code => '$a == 1' },  # This won't be triggered
        { filename => $program_file_name, line => 5, code => '$a == 1' },
        { filename => $program_file_name, line => 11, code => '1' },
        { filename => 't/TestNothing.pm', line => 6, code => 1 }, # loaded at runtime
    ],
    actions => [
        { filename => $program_file_name, line => 7, code => '$a++' },
    ]
};

my $fh = File::Temp->new(TEMPLATE => 'devel-hdb-config-XXXX', TMPDIR => 1);
$fh->print(Data::Dumper->new([$config])->Terse(1)->Dump());
ok($fh->close(), 'Wrote settings file');

$resp = $client->load_config($fh->filename);
ok($resp, 'loadconfig');


my $result = $client->get_breakpoints();
is(@$result, 3, '3 breakpoints were set'); # TestNothing isn't loaded yet

$result = $client->get_actions();
is(@$result, 1, '1 action was set');


$resp = $client->continue();
is_deeply($resp,
    { filename => $program_file_name, line => 5, subroutine => 'MAIN', running => 1, stack_depth => 1 },
    'Continue to line 5');

$resp = $client->continue();
is_deeply($resp,
    { filename => 't/TestNothing.pm', line => 6, subroutine => 'TestNothing::a_sub', running => 1, stack_depth => 2 },
    'Continue to line 6 of TestNothing');

$resp = $client->continue();
is_deeply($resp,
    { filename => $program_file_name, line => 11, subroutine => 'MAIN', running => 1, stack_depth => 1 },
    'Continue to line 11');

$resp = $client->eval('$a');
is($resp, 2, '$a was incremented by action');


__DATA__
use lib 't';
2;
3;
$a = 1;
5;
6;
7;
8;
require TestNothing;
TestNothing::a_sub();
11;
