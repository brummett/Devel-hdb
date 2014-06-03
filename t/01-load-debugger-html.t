use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;
use HTML::TreeBuilder;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 3;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);


subtest 'Main debugger page' => sub {
    plan tests => 4;

    my $resp = $client->gui;
    ok($resp, "Request root URL $url");
    my $tree = HTML::TreeBuilder->new_from_content($resp);
    my @title = $tree->find_by_tag_name('title');
    is(scalar(@title), 1, 'found 1 title tag');
    my @title_text = $title[0]->content_list;
    is(scalar(@title_text), 1, 'title tag contents');
    is($title_text[0], 'hdb', 'Page title is "hdb"');
};

subtest 'debugger js' => sub {
    plan tests => 1;

    my $url = $client->_combined_url($client->_gui_url, 'db/debugger.js');
    my $resp = $client->_GET($url);
    ok($resp, 'Get debugger js');
};

subtest 'debugger icon' => sub {
    plan tests => 1;

    my $url = $client->_combined_url($client->_gui_url, 'img/favicon.ico');
    my $resp = $client->_GET($url);
    ok($resp, 'Get debugger icon');
};



__DATA__
1;
