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
    plan tests => 7;
}

my $url = start_test_program();

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'stack');
ok($resp->is_success, 'Request stack position');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 1, subroutine => 'MAIN' } ],
    'Stopped on line 1');

$resp = $mech->get($url.'stepover');
ok($resp->is_success, 'step over');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
  [ { line => 2, subroutine => 'MAIN' } ],
    'Stopped on line 2');

$resp = $mech->get($url.'stepover');
ok($resp->is_success, 'step over');
my $message = $json->decode($resp->content);
is($message->[0]->{data}->[0]->{subroutine},
    'DB::fake::at_exit',
    'Stopped in at_exit()');
is_deeply($message->[1],
    { type => 'termination', data => { exit_code => 2 } },
    'Got termination message');


__DATA__
foo();
exit(2);
sub foo {
    bar();
    GOTO_TARGET:
    1;
}
sub bar {
    goto GOTO_TARGET;
}
