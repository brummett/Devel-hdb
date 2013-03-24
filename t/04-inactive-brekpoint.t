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
    plan tests => 11;
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

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 6, c => 1 });
ok($resp->is_success, 'Set breakpoint on line 6');

$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 6, subroutine => 'main::foo' },
      { line => 1, subroutine => 'MAIN' } ],
    'Stopped on line 6 breakpoint');

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 6, ci => 1 });
ok($resp->is_success, 'set breakpoint to inactive');


$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 4, subroutine => 'MAIN' } ],
    'Stopped on line 4, in-code $DB::single');


$resp = $mech->post("${url}breakpoint", { f => $filename, l => 6, ci => 0 });
ok($resp->is_success, 'set breakpoint back to  active');


$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 6, subroutine => 'main::foo' },
      { line => 4, subroutine => 'MAIN' } ],
    'Stopped on line 6 breakpoint');



__DATA__
foo();
foo();
$DB::single=1;
foo();
sub foo {
    6;
    7;
}

