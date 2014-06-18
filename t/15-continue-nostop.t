use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;
use Time::HiRes qw(sleep);

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 3;
}

my($url,$pid) = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp = $client->stack();
ok($resp, 'stack');
my $filename = $resp->[0]->{filename};

$resp = $client->continue(1);
is($resp, 1, 'continue to end without stopping');

$SIG{'ALRM'} = sub { die "alarm" };
alarm(5);
eval {
    waitpid($pid, 0);
};
ok(! $@, 'Child process exited without stopping');

__DATA__
1;
2;
3;
$DB::single=1;
$DB::single=1;
6;
7;
print "$$ About to fall off the end\n";
