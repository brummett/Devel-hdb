use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;

use Test::More tests => 13;

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

$resp = $mech->post("${url}action", { f => $filename, l => 6, a => '$a++'});
ok($resp->is_error, 'Cannot set action on unbreakable line');
is($resp->code, 403, 'Error was Forbidden');

$resp = $mech->post("${url}action", { f => 'garbage', l=> 123, a => '$a++'});
ok($resp->is_error, 'Cannot set action on unknown file');
is($resp->code, 404, 'Error was Not Found');

$resp = $mech->post("${url}action", { f => $filename, l => 5, a => '$a++'});
ok($resp->is_success, 'Set action for line 5');


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
$DB::single=1;
5;
sub foo {
    7;
}
