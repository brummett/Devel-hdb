use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;

use Test::More tests => 3;

my $url = start_test_program();

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url);
ok($resp, "Request root URL $url");
ok($resp->is_success, 'Response is success');
is($mech->title, 'hdb', 'Page title is "hdb"');


__DATA__
1;
