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

my $stack;

my $resp = $client->stack();
ok($resp, 'Request stack position');
my $filename = $resp->[0]->{filename};
$stack = strip_stack($resp);
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

$resp = $client->stepover();
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
              value => 2
            },
        ],
    },
    'step over');


__DATA__
do_goto_sub();
exit(2);
sub do_goto_sub {
    goto \&goto_target;
}
sub goto_target {
    1;
}
