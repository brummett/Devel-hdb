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
    [ { line => 3, subroutine => 'main::MAIN' } ],
    'Stopped on line 3');

$resp = $client->loaded_files();
ok($resp, 'Get list of loaded file names');
ok( file_list_contains($resp, $filename, 'HdbHelper.pm'),
    'program file and HdbHelper are loaded');

ok(! file_list_contains($resp, 'TestNothing.pm'),
    'TestNothing.pm is not loaded yet');

$resp = $client->stepover();
ok($resp, 'step over the require');

$resp = $client->loaded_files();
ok( file_list_contains($resp, $filename, 'HdbHelper.pm', 'TestNothing.pm'),
    'program file, HdbHelper and TestNothing are loaded');

sub file_list_contains {
    my $source = shift;
    my @loaded_files = map { $_->{filename} } @$source;

    STRING:
    foreach my $string ( @_ ) {
        foreach my $listitem ( @loaded_files ) {
            next STRING if $listitem eq $string;
            next STRING if $listitem =~ m/\/\Q$string\E$/;
        }
        return;

    }
    return 1;
}


__DATA__
use lib 't';
use HdbHelper;
require TestNothing;
3;
