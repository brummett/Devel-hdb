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
    plan tests => 2;
}

my $url = start_test_program();

my $json = JSON->new();

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'ping');
ok($resp->is_success, 'ping');
my $msg = $json->decode( $resp->content );
is($msg->{type}, 'ping', 'message type is ping');

__DATA__
1;
