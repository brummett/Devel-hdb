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
    plan tests => 19;
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

$resp = $mech->post("${url}action", { f => $filename, l => 7, c => '$a++'});
ok($resp->is_error, 'Cannot set action on unbreakable line');
is($resp->code, 403, 'Error was Forbidden');

$resp = $mech->post("${url}action", { f => 'garbage', l=> 123, c => '$a++'});
ok($resp->is_error, 'Cannot set action on unknown file');
is($resp->code, 404, 'Error was Not Found');

$resp = $mech->post("${url}action", { f => $filename, l => 4, c => '$a++'});
ok($resp->is_success, 'Set action for line 4');

$resp = $mech->post("${url}action", { f => $filename, l => 6, c => '$a++'});
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
        data => { expr => '$a', result => 3 }
    },
    'value is correct - action incremented $a');


$resp = $mech->get("${url}delete-action?f=${filename}&l=4");
ok($resp->is_success, 'Delete action on line 4');
is_deeply( $json->decode( $resp->content ),
    { type => 'delete-action', data => { filename => $filename, lineno => 4 }},
    'delete response ok');

$resp = $mech->get("${url}actions");
ok($resp->is_success, 'Get all actions');
is_deeply($json->decode( $resp->content ),
    [ { type => 'action',
        data => { filename => $filename, lineno => 6, code => '$a++'}
    } ],
    'One action remaining');




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
