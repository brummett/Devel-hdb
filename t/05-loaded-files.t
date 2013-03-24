use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 8;
}

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

$resp = $mech->get('loadedfiles');
ok($resp->is_success, 'Get list of loaded file names');
my $answer = $json->decode($resp->content);
ok( file_list_contains($answer->{data}, $filename, 'HdbHelper.pm'),
    'program file and HdbHelper are loaded');

ok(! file_list_contains($answer->{data}, 'TestNothing.pm'),
    'TestNothing.pm is not loaded yet');

$resp = $mech->get('stepover');
ok($resp->is_success, 'step over the require');

$resp = $mech->get('loadedfiles');
ok($resp->is_success, 'Get list of loaded file names');
$answer = $json->decode($resp->content);
ok( file_list_contains($answer->{data}, $filename, 'HdbHelper.pm', 'TestNothing.pm'),
    'program file, HdbHelper and TestNothing are loaded');

sub file_list_contains {
    my $source = shift;
    my %source = map { $_ => 1 } @$source;

    STRING:
    foreach my $string ( @_ ) {
        foreach my $listitem ( @$source ) {
            next STRING if $listitem eq $string;
            next STRING if $listitem =~ m/\/\Q$string\E$/;
        }
        return;

    }
    return 1;
}


__DATA__
use lib 't';
use HdbHelper;
require TestNothing;
3;
