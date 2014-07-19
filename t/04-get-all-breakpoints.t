use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 13;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp;

my $stack = $client->stack();
ok($stack, 'Request stack position');
my $filename = $stack->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 3, subroutine => 'main::MAIN' } ],
    'Stopped on line 3');

my $bp_3 = $client->create_breakpoint( filename => $filename, line => 3, code => '$a' );
ok($bp_3, 'Set breakpoint for line 3');

my $bp_4 = $client->create_breakpoint( filename => $filename, line => 4, inactive => 1 );
ok($bp_4, 'Set breakpoint for line 4');

my $bp_5 = $client->create_breakpoint( filename => $filename, line => 5 );
ok($bp_5, 'Set breakpoint line 5');

my($test_nothing_file) = grep { $_->{filename} =~ m/TestNothing.pm/ } @{$client->loaded_files()};
$test_nothing_file = $test_nothing_file->{filename};
my $bp_tn = $client->create_breakpoint( filename => $test_nothing_file, line => 3 );
ok($bp_tn, 'Set breakpoint for line TestNothing.pm 3');

$resp = $client->get_breakpoints();
is_deeply(sort_breakpoints_by_file_and_line($resp),
    [   { filename => $filename, line => 3, code => '$a', inactive => 0, href => $bp_3 },
        { filename => $filename, line => 4, code => 1, inactive => 1, href => $bp_4 },
        { filename => $filename, line => 5, code => 1, inactive => 0, href => $bp_5 },
        { filename => $test_nothing_file, line => 3, code => 1, inactive => 0, href => $bp_tn },
    ],
    'Got all set breakpoints'
);

$resp = $client->get_breakpoints(filename => $filename);
is_deeply(sort_breakpoints_by_file_and_line($resp),
    [
        { filename => $filename, line => 3, code => '$a', inactive => 0, href => $bp_3 },
        { filename => $filename, line => 4, code => 1, inactive => 1, href => $bp_4 },
        { filename => $filename, line => 5, code => 1, inactive => 0, href => $bp_5 },
    ],
    'Get all breakpoints for main file'
);

$resp = $client->get_breakpoints(filename => $filename, inactive => 1);
is_deeply($resp,
    [ { filename => $filename, line => 4, code => 1, inactive => 1, href => $bp_4 }, ],
    'Get breakpoints filtered by file and inactive');

$resp = $client->get_breakpoints(line => 3, code => '$a');
is_deeply($resp,
    [ { filename => $filename, line => 3, code => '$a', inactive => 0, href => $bp_3} ],
    'Get breakpoints filtered by line and code');

$resp = $client->get_breakpoints(line => 3, code => 'garbage');
is_deeply($resp,
    [],
    'Get breakpoints filtered by line and code matching nothing');

$resp = $client->delete_breakpoint($bp_4);
ok($resp, 'Remove breakpoint for line 4');
$resp = $client->get_breakpoints(filename => $filename);
is_deeply( sort_breakpoints_by_file_and_line($resp),
    [
      { filename => $filename, line => 3, code => '$a', inactive => 0, href => $bp_3 },
      { filename => $filename, line => 5, code => 1, inactive => 0, href => $bp_5 },
    ],
    'Got all remaining breakpoints for main file'
);

sub sort_breakpoints_by_file_and_line {
    my $bp_list = shift;

    my @sorted =
            sort { $a->{filename} cmp $b->{filename}
                   or
                   $a->{line} <=> $b->{line}
                 }
            @$bp_list;
    return \@sorted;
}



__DATA__
use lib 't';
use TestNothing;
1;
foo();
3;
sub foo {
    5;
}
