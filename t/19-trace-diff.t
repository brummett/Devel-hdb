use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;
use File::Temp;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 9;
}

my $program_file = File::Temp->new();;
$program_file->close();

my $trace_file = File::Temp->new();
$trace_file->close();

my $url = start_test_program('-file' => $program_file->filename,
                             '-module_args' => 'trace:'.$trace_file->filename);

my $json = JSON->new();

#my $resp = $mech->get($url.'continue');

#ok($resp->is_success, 'Run test program tracing execution');
#my $messages = $json->decode($resp->content);
#ok(scalar(grep { $_->{type} eq 'termination'} @$messages ), 'Program ran to termination');
ok(-s $trace_file->filename, 'Program generated a trace file');

my $url2 = start_test_program('-file' => $program_file->filename,
                              '-module_args' => 'follow:'.$trace_file->filename);
isnt($url2, $url, 'Start test program again in follow mode');

my $mech = WWW::Mechanize->new();
my $resp = $mech->post($url2.'eval', content => '$a = 1' );
ok($resp->is_success, 'Set test variable to 1');

$resp = $mech->get($url2.'continue');
ok($resp->is_success, 'continue');

# expecting 'stack' and 'trace_diff' messages
my @messages = sort { $a->{type} cmp $b->{type} } @{ $json->decode( $resp->content) };
use Data::Dumper;
#print Data::Dumper::Dumper(\@messages);
is($messages[0]->{type}, 'stack', 'Got stack message');
is($messages[0]->{data}->[0]->{line}, 2, 'Stopped on differing line');

is($messages[1]->{type}, 'trace_diff', 'Got trace_diff message');
my $diff_data = $messages[1]->{data};
is($diff_data->{line}, 2, 'Diff data shows actual line');
is($diff_data->{expected_line}, 4, 'Diff data shows expected line');


__DATA__
if($a) {  # default $a is undef
    2;
} else {
    4;
}
6;

