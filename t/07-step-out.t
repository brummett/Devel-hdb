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
    plan tests => 10;
}

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
    { line => 16, subroutine => 'main::subtwo' },
    'Stopped on line 16');


$resp = $mech->get($url.'stepout');
ok($resp->is_success, 'step out');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack->[0],
  { line => 11, subroutine => 'main::two' },
    'Stopped on line 11');

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
    11;
    12;
}
sub subtwo {
    $DB::single=1;
    16;
    17;
}
