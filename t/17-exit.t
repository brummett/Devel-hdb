use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 3;
}

my($url, $pid) = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

ok(kill(0, $pid), 'Debugged process is running');

my $resp = $client->exit();
ok($resp, 'exit');

eval {
    local $SIG{'ALRM'} = sub { die "alarm\n" };
    alarm(5);
    waitpid($pid, 0);
    alarm(0);
};

ok(! kill(0, $pid), 'Debugged process is no longer running');
__DATA__
1;
