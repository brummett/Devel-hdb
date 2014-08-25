use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;
use LWP::UserAgent;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 33;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp = $client->overview();
ok($resp, 'overview');

my @get_keys = qw( program_name perl_version source loaded_files stack breakpoints actions
                   watchpoints packageinfo debugger_gui status );
my @other_keys = qw( stepin stepover stepout continue eval getvar subinfo exit
                    loadconfig saveconfig);
foreach my $key ( @get_keys, @other_keys ) {
    ok(exists($resp->{$key}), "overview key $key");
}

my $ua = LWP::UserAgent->new();
foreach my $key ( @get_keys ) {
    ok($ua->get( $resp->{$key} ), "GET $key");
}

__DATA__
1;
