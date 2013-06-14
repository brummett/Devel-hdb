use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;

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
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

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
    [ { line => 2, subroutine => 'main::MAIN' } ],
    'Stopped on line 2');

$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 6, subroutine => 'main::MAIN' } ],
    'Stopped on line 6');


__DATA__
$a = 1;
2;
$a = 3;
4;
$a = 5;
5;

