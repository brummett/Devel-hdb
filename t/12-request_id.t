use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;

use Test::More tests => 5;

my $url = start_test_program();

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();

my $resp = $mech->get($url.'stack?rid=abc');
ok($resp->is_success, 'Request stack position');
$stack = $json->decode($resp->content);
is($stack->{rid}, 'abc', 'request IDs match');

my $filename = $stack->{data}->[0]->{filename};
$resp = $mech->get($url.'program_name?rid=def');
ok($resp->is_success, 'Request program name');
my $retval = $json->decode($resp->content);
is($retval->{data}, $filename, 'Filename matches');
is($retval->{rid}, 'def', 'request IDs match');




__DATA__
1;
