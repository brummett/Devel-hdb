use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 3;
}

my($url, $pid) = start_test_program();

ok(kill(0, $pid), 'Debugged process is running');

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'exit');
ok($resp->is_success, 'exit');

eval {
    local $SIG{'ALRM'} = sub { die "alarm\n" };
    alarm(5);
    waitpid($pid, 0);
    alarm(0);
};

ok(! kill(0, $pid), 'Debugged process is no longer running');
__DATA__
1;
