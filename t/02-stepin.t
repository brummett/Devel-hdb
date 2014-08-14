use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 11;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $stack;

my $resp = $client->stack();
ok($resp, 'Request stack position');
my $filename = $resp->[0]->{filename};
$stack = strip_stack($resp);
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

$resp = $client->stepin();
is_deeply($resp,
    { filename => $filename, line => 2, subroutine => 'MAIN', running => 1, stack_depth => 1 },
    'step in');
$stack = strip_stack($client->stack);
is_deeply($stack,
    [ { line => 2, subroutine => 'main::MAIN' } ],
    'Stopped on line 2');

$resp = $client->stepin();
is_deeply($resp,
    { filename => $filename, line => 6, subroutine => 'main::foo', running => 1, stack_depth => 2 },
    'step in');
$stack = strip_stack($client->stack);
is_deeply($stack,
  [ { line => 6, subroutine => 'main::foo' },
    { line => 2, subroutine => 'main::MAIN' } ],
    'Stopped on line 6, frame above is line 2');

$resp = $client->stepin();
is_deeply($resp,
    { filename => $filename, line => 3, subroutine => 'MAIN', running => 1, stack_depth => 1 },
    'step in');
$stack = strip_stack($client->stack);
is_deeply($stack,
  [ { line => 3, subroutine => 'main::MAIN' } ],
    'Stopped on line 3');

$resp = $client->stepin();
is_deeply($resp,
    { filename => $filename, line => 4, subroutine => 'MAIN', running => 1, stack_depth => 1 },
    'step in');
$stack = strip_stack($client->stack);
is_deeply($stack,
  [ { line => 4, subroutine => 'main::MAIN' } ],
    'Stopped on line 4');

$resp = $client->stepin();
like($resp->{subroutine}, qr(::END$), 'step-in ended up in an END block');


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
