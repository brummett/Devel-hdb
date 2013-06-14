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

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'stack');
ok($resp->is_success, 'Request stack position');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

$resp = $mech->get($url.'stepin');
ok($resp->is_success, 'step in');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 2, subroutine => 'main::MAIN' } ],
    'Stopped on line 2');

$resp = $mech->get($url.'stepin');
ok($resp->is_success, 'step in');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
  [ { line => 6, subroutine => 'main::foo' },
    { line => 2, subroutine => 'main::MAIN' } ],
    'Stopped on line 6, frame above is line 2');

$resp = $mech->get($url.'stepin');
ok($resp->is_success, 'step in');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
  [ { line => 3, subroutine => 'main::MAIN' } ],
    'Stopped on line 3');

$resp = $mech->get($url.'stepin');
ok($resp->is_success, 'step in');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
  [ { line => 4, subroutine => 'main::MAIN' } ],
    'Stopped on line 4');

$resp = $mech->get($url.'stepin');
ok($resp->is_success, 'step in');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack->[0],
  { line => 9, subroutine => 'main::END' },
    'Stopped on line 9, in END block');


__DATA__
1;
foo();
3;
exit(4);
sub foo {
    6;
}
END {
    9;
}
