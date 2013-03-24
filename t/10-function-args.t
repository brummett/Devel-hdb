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
    plan tests => 5;
}

my $url = start_test_program('arg1', 'arg2');

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'stack');
ok($resp->is_success, 'Request stack position');
$stack = strip_stack_inc_args($json->decode($resp->content));
is_deeply($stack,
    [ { line => 1, subroutine => 'MAIN', args => ['arg1', 'arg2'] } ],
    'Stopped on line 1');

$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$stack = strip_stack_inc_args($json->decode($resp->content));
ok(delete($stack->[0]->{args}->[2]->{__refaddr}), '3rd arg has a refaddr');

is_deeply($stack,
  [ { line => 6, subroutine => 'main::foo',
        args => [1, 'one', { __reftype => 'HASH', __value => { two => 2 }} ] },
    { line => 2, subroutine => 'MAIN', args => ['arg1','arg2'] } ],
    'Stopped on line 6, frame above is line 2');


__DATA__
1;
foo(1,'one', { two => 2 });
3;
sub foo {
    $DB::single=1;
    6;
}
