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
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 4, c=> 1});
ok($resp->is_error, 'Cannot set breakpoint on unbreakable line');
is($resp->code, 403, 'Error was Forbidden');

$resp = $mech->post("${url}breakpoint", { f => 'garbage', l=> 123, c => 1});
ok($resp->is_error, 'Cannot set breakpoint on unknown file');
is($resp->code, 404, 'Error was Not Found');

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 3, c => 1});
ok($resp->is_success, 'Set breakpoint for line 3');


$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 3, subroutine => 'main::MAIN' } ],
    'Stopped on line 3');

$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
my $message = $json->decode($resp->content);
is($message->[0]->{data}->[0]->{subroutine},
    'Devel::Chitin::exiting::at_exit',
    'Stopped in at_exit()');
is_deeply($message->[1],
    { type => 'termination', data => { exit_code => 0 } },
    'Got termination message');


__DATA__
1;
foo();
3;
sub foo {
    5;
}
