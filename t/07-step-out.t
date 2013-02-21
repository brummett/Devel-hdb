use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;

use Test::More tests => 9;

my $url = start_test_program();

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'continue');
ok($resp->is_success, 'Run to first breakpoint');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack->[0],
    { line => 6, subroutine => 'main::one' },
    'Stopped on line 6');

$resp = $mech->get($url.'stepout');
ok($resp->is_success, 'step out');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack->[0],
    { line => 2, subroutine => 'MAIN' },
    'Stopped on line 2');

$resp = $mech->get($url.'continue');
ok($resp->is_success, 'Run to next breakpoint');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack->[0],
    { line => 14, subroutine => 'main::subtwo' },
    'Stopped on line 14');


$resp = $mech->get($url.'stepout');
ok($resp->is_success, 'step out');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack->[0],
  { line => 10, subroutine => 'main::two' },
    'Stopped on line 10');

$resp = $mech->get($url.'stepout');
ok($resp->is_success, 'step out');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack->[0],
  { line => 3, subroutine => 'MAIN' },
    'Stopped on line 3');



__DATA__
one();
two();
3;
sub one {
    $DB::single=1;
    6;
    7;
}
sub two {
    subtwo();
    10;
    11;
}
sub subtwo {
    $DB::single=1;
    14;
    15;
}
