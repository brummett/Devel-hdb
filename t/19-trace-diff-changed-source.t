use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;
use File::Temp;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 4;
}

my $program_source = <<'PROGRAM';
    f($a);
    # EMPTY_LINE
    sub f {
        if ($a) {
            4;
        } else {
            6;
        }
        8;
    }
PROGRAM

my $program_file = File::Temp->new();
$program_file->close();

my $trace_file = File::Temp->new();
$trace_file->close();

my($url, $pid) = start_test_program('-file' => $program_file->filename,
                                    '-source' => $program_source,
                                    '-module_args' => 'trace:'.$trace_file->filename);

local $SIG{ALRM} = sub {
    ok(0, 'Test program did not finish');
    exit;
};
alarm(5);
waitpid($pid, 0);
ok(-s $trace_file->filename, 'Program generated a trace file');

# Run it again, but remove the line "# EMPTY_LINE" to make the raw line number different
$program_source =~ s/# EMPTY_LINE\n//;

my $url2 = start_test_program('-file' => $program_file->filename,
                              '-source' => $program_source,
                              '-module_args' => 'follow:'.$trace_file->filename);
isnt($url2, $url, 'Start test program again in follow mode');

my $client = Devel::hdb::Client->new(url => $url2);
my $resp = $client->eval('$a = 1' );
is($resp, 1, 'Set test variable to 1');

$resp = $client->continue();
is_deeply($resp,
    {
        filename => $program_file->filename,
        line => 4,
        running => 1,
        stack_depth => 2,
        subroutine => 'main::f',
        events => [
            {
                type => 'trace_diff',
                filename => $program_file->filename,
                expected_filename => $program_file->filename,
                line => 4,
                expected_line => 6,
                sub_offset => 2,
                expected_sub_offset => 4,
                package => 'main',
                expected_package => 'main',
                subroutine => 'main::f',
                expected_subroutine => 'main::f',
            },
        ],
    },
    'continue');

