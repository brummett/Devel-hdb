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

my $resp = $client->continue();
my $filename = $resp->{filename};
is_deeply($resp,
    { filename => $filename, line => 6, subroutine => 'main::one', running => 1, stack_depth => 2 },
    'Run to first breakpoint');

$resp = $client->stepout();
is_deeply($resp,
    { filename => $filename, line => 2, subroutine => 'MAIN', running => 1, stack_depth => 1 },
    'step out to line 2');

$resp = $client->continue();
is_deeply($resp,
    { filename => $filename, line => 16, subroutine => 'main::subtwo', running => 1, stack_depth => 3 },
    'Run to next breakpoint line 16');

$resp = $client->stepout();
is_deeply($resp,
    { filename => $filename, line => 11, subroutine => 'main::two', running => 1, stack_depth => 2 },
    'step out to line 11');

$resp = $client->stepout();
is_deeply($resp,
    { filename => $filename, line => 3, subroutine => 'MAIN', running => 1, stack_depth => 1 },
    'step out to line 3');



__DATA__
one();
two();
3;
sub one {
    $DB::single=1;
    6;
    7;
}
sub two {
    subtwo();
    11;
    12;
}
sub subtwo {
    $DB::single=1;
    16;
    17;
}
