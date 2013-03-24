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
    plan tests => 12;
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

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 4, a => '$a++'});
ok($resp->is_success, 'Set action for line 4');

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 4, ai => 1});
ok($resp->is_success, 'Set action for line 4 to inactive');

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 6, a => '$a++'});
ok($resp->is_success, 'Set action for line 6');


$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$resp = $mech->post("${url}eval", content => '$a');
ok($resp->is_success, 'Get value of $a');
my $answer = $json->decode($resp->content);
is_deeply($answer,
    {   type => 'evalresult',
        data => { expr => '$a', result => 1 }
    },
    'value is correct');

$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$stack = $json->decode($resp->content);
# Make sure it didn't stop on line 4 - it has an action but no breakpoint
is($stack->{data}->[0]->{line}, 6, 'Stopped on line 6');
$resp = $mech->post("${url}eval", content => '$a');
ok($resp->is_success, 'Get value of $a');
$answer = $json->decode($resp->content);
is_deeply($answer,
    {   type => 'evalresult',
        data => { expr => '$a', result => 2 }
    },
    'value is correct - action incremented $a');





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
