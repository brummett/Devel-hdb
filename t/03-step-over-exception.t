use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 9;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $stack = $client->stack();
ok($stack, 'Request stack position');
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

my $resp = $client->stepover();
ok($resp, 'step over');
$stack = strip_stack($client->stack);
is_deeply($stack,
    [ { line => 1, subroutine => '(eval)' },
      { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped inside the eval line 1');

$resp = $client->stepover();
ok($resp, 'step over');
$stack = strip_stack($client->stack);
is_deeply($stack,
  [ { line => 2, subroutine => 'main::MAIN' } ],
    'Stopped on line 2');

$resp = $client->stepover();
ok($resp, 'step over');
$stack = strip_stack($client->stack);
is_deeply($stack,
  [ { line => 3, subroutine => 'main::MAIN' } ],
    'Stopped on line 3');

$resp = $client->stepover();
ok($resp, 'step over');
$stack = strip_stack($client->stack);


__DATA__
eval { do_die() };
wrap_die();
exit(2);
sub do_die {
    die "in do_die";
}
sub wrap_die {
    eval { do_die() };
}
