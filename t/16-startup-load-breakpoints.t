use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;
use IO::File;
use Data::Dumper;
use Devel::hdb::App;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 13;
}

my $program_file_name = File::Temp::tmpnam();
my $config = {
    breakpoints => [
        { file => $program_file_name, line => 3, code => '$a == 1' },  # This won't be triggered
        { file => $program_file_name, line => 5, code => '$a == 1' },
        { file => $program_file_name, line => 11, code => '1' },
        { file => 't/TestNothing.pm', line => 6, code => 1 }, # loaded at runtime
    ],
    actions => [
        { file => $program_file_name, line => 7, code => '$a++' },
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

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'stack');
ok($resp->is_success, 'Request stack position');
$stack = $json->decode($resp->content);
my $filename = $stack->{data}->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 2, subroutine => 'main::MAIN' } ],
    'Stopped on line 2');

$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 5, subroutine => 'main::MAIN' } ],
    'Stopped on line 5');

$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 6, subroutine => 'TestNothing::a_sub' },
      { line => 10, subroutine => 'main::MAIN' } ],
    'Stopped on line 6 of TestNothing');

$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 11, subroutine => 'main::MAIN' } ],
    'Stopped on line 11');

$resp = $mech->post($url.'eval', content => '$a');
ok($resp->is_success, 'Get $a after increment action');
my $answer = $json->decode($resp->content);
is_deeply($answer->{data},
        { expr => '$a', result => 2 },
        '$a was incremented by action');



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
