use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 4;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp;

my $stack = $client->stack();
ok($stack, 'Request stack position');
my $filename = $stack->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

$resp = $client->continue();
is_deeply($resp,
    { filename => $filename, line => 4, subroutine => 'MAIN', running => 1, stack_depth => 1 },
    'continue to breakpoint in code');

$resp = $client->continue();
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
    'continue');


__DATA__
1;
one();
$DB::single=1;
two();
exit(2);
sub one {
    4;
}
sub two {
    subtwo();
}
sub subtwo {
    10;
}
