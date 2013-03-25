use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;
use IO::File;
use Data::Dumer;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 9;
}

my $url = start_test_program();

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new(autocheck => 0);
my $resp = $mech->get($url.'stack');
ok($resp->is_success, 'Request stack position');
$stack = $json->decode($resp->content);
my $filename = $stack->{data}->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 1, subroutine => 'MAIN' } ],
    'Stopped on line 1');


my $breakpoints = { breakpoints => [
        { file => $filename, line => 2, condition => 1 },
        { file => $filename, line => 3, condition => '$a == 1' },  # This won't be triggered
        { file => $filename, line => 5, condition => '$a == 1' },
        { file => $filename, line => 6, action => '$a++' },
        { file => $filename, line => 
        


$resp = $mech->post("${url}breakpoint", { f => $filename, l => 2, c => '$a != 3'});
ok($resp->is_success, 'Set conditional breakpoint on line 2 for $a != 3');

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 4, c => '$a != 3'});
ok($resp->is_success, 'Set conditional breakpoint on line 4 for $a != 3');

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 6, c => '$a != 3'});
ok($resp->is_success, 'Set conditional breakpoint on line 6 for $a != 3');


$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 2, subroutine => 'MAIN' } ],
    'Stopped on line 2');

$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 6, subroutine => 'MAIN' } ],
    'Stopped on line 6');


__DATA__
my $a = 0;
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
