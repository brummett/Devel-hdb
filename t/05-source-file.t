use strict;
use warnings;

use lib 't';
use HdbHelper;
use File::Basename;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 11;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp;

my $stack = $client->stack();
ok($stack, 'Request stack position');
my $filename = $stack->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 3, subroutine => 'main::MAIN' } ],
    'Stopped on line 3');

$resp = eval { $client->file_source_and_breakable('garbage') };
ok(!$resp && $@, 'Cannot get file source for non-existent file');
is($@->http_code, 404, 'error was not found');

# Find out where HdbHelper was loaded from
$resp = $client->loaded_files();
my($hdb_helper) = grep { $_->{filename} =~ m/HdbHelper.pm$/ } @$resp;
my $hdb_helper_pathname = $hdb_helper->{filename};
my $subdir = index($hdb_helper_pathname, '/') == -1
                ? ''
                : File::Basename::dirname($hdb_helper_pathname) . '/';

$resp = $client->file_source_and_breakable($hdb_helper_pathname);
ok($resp, 'Get source of HdbHelper.pm');
is($resp->[0]->[0], "package HdbHelper;\n", 'File contents looks ok');


$resp = eval { $client->file_source_and_breakable("${subdir}TestNothing.pm") };
ok(!$resp && $@, 'Request source of TestNothing.pm - not loaded yet');
is($@->http_code, 404, 'error is Not Found');


$resp = $client->stepover();
ok($resp, 'step over the require');

$resp = $client->file_source_and_breakable("${subdir}TestNothing.pm");
ok($resp, 'Request source of TestNothing.pm again');
is($resp->[0]->[0], "package TestNothing;\n", 'File contents looks ok');


__DATA__
use lib 't';
use HdbHelper;
require TestNothing;
3;
