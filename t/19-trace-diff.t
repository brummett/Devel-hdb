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

my $program_file = File::Temp->new();
$program_file->close();

my $trace_file = File::Temp->new();
$trace_file->close();

my($url, $pid) = start_test_program('-file' => $program_file->filename,
                                    '-module_args' => 'trace:'.$trace_file->filename);
local $SIG{ALRM} = sub {
    ok(0, 'Test program did not finish');
    exit;
};
alarm(5);
waitpid($pid, 0);
ok(-s $trace_file->filename, 'Program generated a trace file');

my $url2 = start_test_program('-file' => $program_file->filename,
                              '-module_args' => 'follow:'.$trace_file->filename);
isnt($url2, $url, 'Start test program again in follow mode');

my $client = Devel::hdb::Client->new(url => $url2);

my $resp = $client->eval('$a = 1');
is($resp, 1, 'Set test variable to 1');

$resp = $client->continue();
is_deeply($resp,
    {
        filename => $program_file->filename,
        line => 2,
        subroutine => 'MAIN',
        running => 1,
        stack_depth => 1,
        events => [
            {
                type => 'trace_diff',
                line => 2,
                expected_line => 4,
                filename => $program_file->filename,
                expected_filename => $program_file->filename,
                sub_offset => undef,
                expected_sub_offset => '',
                package => 'main',
                expected_package => 'main',
                subroutine => 'MAIN',
                expected_subroutine => 'MAIN',
            },
        ],
    },
    'continue to trace diff');


__DATA__
if($a) {  # default $a is undef
    2;
} else {
    4;
}
6;

