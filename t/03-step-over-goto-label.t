use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 5;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $stack = $client->stack();
ok($stack, 'Request stack position');
my $filename = $stack->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

my $resp = $client->stepover;
is_deeply($resp,
    { filename => $filename, line => 2, subroutine => 'MAIN', running => 1, stack_depth => 1 },
    'step over');
$stack = strip_stack($client->stack);
is_deeply($stack,
  [ { line => 2, subroutine => 'main::MAIN' } ],
    'Stopped on line 2');

$resp = $client->stepover;
my $stopped_filename = delete $resp->{filename};
my $stopped_line = delete $resp->{line};
my $stack_depth = delete $resp->{stack_depth};
is_deeply($resp,
    {   subroutine => 'Devel::Chitin::exiting::at_exit',
        running => 0,
        events => [
            { type => 'exit',
              value => 2,
            },
        ],
    },
    'step over');


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
