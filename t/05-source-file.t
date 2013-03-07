use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use File::Basename;
use JSON;

use Test::More tests => 12;

my $url = start_test_program();

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'stack');
ok($resp->is_success, 'Request stack position');
$stack = $json->decode($resp->content);
my $filename = $stack->{data}->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 3, subroutine => 'MAIN' } ],
    'Stopped on line 3');

# Find out where HdbHelper was loaded from
$resp = $resp = $mech->get('loadedfiles');
my $answer = $json->decode($resp->content);
my($hdb_helper) = grep { m/HdbHelper.pm$/ } @{$answer->{data}};
my $subdir = index($hdb_helper, '/') == -1 ? '' : File::Basename::dirname($hdb_helper) . '/';

$resp = $mech->get("sourcefile?f=${subdir}HdbHelper.pm");
ok($resp->is_success, 'Get source of HdbHelper.pm');
$answer = $json->decode($resp->content);
is( $answer->{data}->{filename}, "${subdir}HdbHelper.pm", 'Answered with the correct filename');
is($answer->{data}->{lines}->[0]->[0], "package HdbHelper;\n", 'File contents looks ok');


$resp = $mech->get("sourcefile?f=${subdir}TestNothing.pm");
ok($resp->is_success, 'Request source of TestNothing.pm');
$answer = $json->decode($resp->content);
is( $answer->{data}->{filename}, "${subdir}TestNothing.pm", 'Answered with the correct filename');
is_deeply($answer->{data}->{lines}, [], 'Response is an empty file');


$resp = $mech->get('stepover');
ok($resp->is_success, 'step over the require');

$resp = $mech->get("sourcefile?f=${subdir}TestNothing.pm");
ok($resp->is_success, 'Request source of TestNothing.pm again');
$answer = $json->decode($resp->content);
is( $answer->{data}->{filename}, "${subdir}TestNothing.pm", 'Answered with the correct filename');
is($answer->{data}->{lines}->[0]->[0], "package TestNothing;\n", 'File contents looks ok');


__DATA__
use lib 't';
use HdbHelper;
require TestNothing;
3;
