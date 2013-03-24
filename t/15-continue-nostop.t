use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;
use Time::HiRes qw(sleep);

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 4;
}

my($url,$pid) = start_test_program();

my $json = JSON->new();

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'stack');
ok($resp->is_success, 'stack');

$resp = $mech->get($url.'continue?nostop=1');
ok($resp->is_success, 'continue without stopping');
my $data = $json->decode( $resp->content );
is_deeply($data,
        {type => 'continue', data => { nostop => 1 }},
        'response include nostop = 1');

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
