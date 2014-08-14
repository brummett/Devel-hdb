use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 6;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $response;

my $resp = $client->continue();
my $filename = delete $resp->{filename};
my $child_pid = delete $resp->{events}->[0]->{pid};
my $child_url = delete $resp->{events}->[0]->{href};
my $child_gui_url = delete $resp->{events}->[0]->{gui_href};
my $child_continue_url = delete $resp->{events}->[0]->{continue_href};
is_deeply($resp,
    {   subroutine => 'MAIN',
        line => 5,
        running => 1,
        stack_depth => 1,
        events => [
            { type => 'fork' },
        ]
    },
    'continue to breakpoint');

ok($child_pid, 'Fork event has pid');
ok($child_url, 'Fork event has href');
ok($child_gui_url, 'Fork event has GUI href');
ok($child_continue_url, 'Fork event has continue_href');

eval qq(END { kill 'TERM', $child_pid }) if ($child_pid);

my $child_client = Devel::hdb::Client->new(url => $child_url);
$resp = $child_client->status();
is_deeply($resp,
    {   filename => $filename,
        line => 3,
        subroutine => 'MAIN',
        running => 1,
        stack_depth => 1,
    },
    'Child is stopped on line 3');

__DATA__
my $orig_pid = $$;
if (! fork) {
    3;  #child
}
5;
6;
print "___ pid $$ exiting\n";
