use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;

use Test::More tests => 4;

my $url = start_test_program();

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');

$stack = $json->decode($resp->content);
is($stack->[0]->{data}->[0]->{subroutine}, 'main::AUTOLOAD', 'Stopped in recursive AUTOLOAD');
is($stack->[0]->{data}->[0]->{subname}, 'AUTOLOAD(bar)', 'Short subname shows the recursive called sub name');
is($stack->[0]->{data}->[1]->{subname}, 'AUTOLOAD(foo)', 'Short subname shows the first called sub name');


__DATA__
foo();
2;
sub AUTOLOAD {
    $DB::single=1 if $AUTOLOAD eq 'main::bar';
    bar();
    5;
}
