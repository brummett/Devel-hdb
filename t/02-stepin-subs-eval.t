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

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'stack');
ok($resp->is_success, 'Request stack position');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 1, subroutine => 'MAIN' } ],
    'Stopped on line 1');

$resp = $mech->get($url.'stepin');
ok($resp->is_success, 'step in');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 1, subroutine => '(eval)' },
      { line => 1, subroutine => 'MAIN' } ],
    'Still stopped on line 1, in the eval');

$resp = $mech->get($url.'stepin');
ok($resp->is_success, 'step in');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
  [ { line => 4, subroutine => 'main::foo' },
    { line => 1, subroutine => '(eval)' },
    { line => 1, subroutine => 'MAIN' } ],
    'Stopped on line 4, frame above is line 1');

$resp = $mech->get($url.'stepin');
ok($resp->is_success, 'step in');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
  [ { line => 8, subroutine => 'main::bar' },
    { line => 4, subroutine => 'main::foo' },
    { line => 1, subroutine => '(eval)' },
    { line => 1, subroutine => 'MAIN' } ],
    'Stopped on line 7, frames above are lines 4 and 1');

$resp = $mech->get($url.'stepin');
ok($resp->is_success, 'step in');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
  [ { line => 2, subroutine => 'MAIN' } ],
    'Stopped on line 2 after the eval');

$resp = $mech->get($url.'stepin');
ok($resp->is_success, 'step in');
my $message = $json->decode($resp->content);
is($message->[0]->{data}->[0]->{subroutine},
    'DB::fake::at_exit',
    'Stopped in at_exit()');
is_deeply($message->[1],
    { type => 'termination', data => { exit_code => 2 } },
    'Got termination message');


__DATA__
eval { foo(); };
exit(2);
sub foo {
    bar();
    5;
}
sub bar {
    die "8";
    9;
}
