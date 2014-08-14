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
    plan tests => 9;
}

my $program_file_name = File::Temp::tmpnam();
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
my $setting_file = Devel::hdb::App->settings_file($program_file_name);
like($setting_file,
    qr(^$program_file_name),
    'Settings file name starts with the program file name');
eval "END { unlink('$program_file_name', '$setting_file') }";

isnt($program_file_name, $setting_file, 'Settings file name different than program filename');

my $fh = IO::File->new($setting_file, 'w') || die "Can't open $setting_file: $!";
$fh->print(Data::Dumper->new([$config])->Terse(1)->Dump());
ok($fh->close(), 'Wrote settings file');

my $url = start_test_program('-file' => $program_file_name);
my $client = Devel::hdb::Client->new(url => $url);

my $resp = $client->stack();
ok($resp, 'Request stack position');
my $filename = $resp->[0]->{filename};
my $stack = strip_stack($resp);
is_deeply($stack,
    [ { line => 2, subroutine => 'main::MAIN' } ],
    'Stopped on line 2');

$resp = $client->continue();
is_deeply($resp,
    { filename => $program_file_name, line => 5, subroutine => 'MAIN', running => 1, stack_depth => 1 },
    'continue to line 5');

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
