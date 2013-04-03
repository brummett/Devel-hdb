use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;

use Test::More tests => 22;

use_ok('Devel::hdb::Router');

my $r = Devel::hdb::Router->new();
ok($r, 'Create router');

my $get_called = 0;
ok($r->get('test', sub { $get_called++; return "foo" }), 'Add route for GET test');
my $put_called = 0;
ok($r->put('test', sub { $put_called++; return "bar" }), 'Add route for PUT test');

is($r->route( make_req('GET', 'test')), "foo", 'Run route for GET test');
is($get_called, 1, 'GET callback ran');
is($put_called, 0, 'PUT callback did not run');

$get_called = $put_called = 0;
is($r->route( make_req('PUT', 'test')), "bar", 'Run route for PUT test');
is($put_called, 1, 'PUT callback ran');
is($get_called, 0, 'GET callback did not run');

$get_called = $put_called = 0;
is($r->route( make_req('DELETE', 'test')), undef, 'Run route for DELETE test');
is($get_called, 0, 'GET callback did not run');
is($put_called, 0, 'PUT callback did not run');

$get_called = $put_called = 0;
my $after_ran = 0;
ok($r->once_after('GET', 'test', sub { $after_ran++ }), 'Add once_after callback');
is($r->route( make_req('GET', 'test')), "foo", 'Run route for GET test');
is($get_called, 1, 'GET callback ran');
is($put_called, 0, 'PUT callback did not run');
is($after_ran, 1, 'after callback ran');

$after_ran = $get_called = $put_called = 0;
is($r->route( make_req('GET', 'test')), "foo", 'Run route for GET test again');
is($get_called, 1, 'GET callback ran');
is($put_called, 0, 'PUT callback did not run');
is($after_ran, 0, 'after callback did not run');




sub make_req {
    my $method = shift;
    my $path = shift;
    my $data = shift;

    # Pretend to be a psgi env object
    return {
        REQUEST_METHOD  => $method,
        PATH_INFO       => $path,
        data            => $data,
    };
}
