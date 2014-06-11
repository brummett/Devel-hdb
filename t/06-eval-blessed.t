use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;
use Devel::hdb::App;
use Scalar::Util;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 11;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp = $client->continue();
is($resp->{line}, 8, 'Run to breakpoint');

my $hash = $client->eval('$hash;');
isa_ok($hash, 'HashThing', 'Get blessed hashref');
is_deeply($hash,
    { a => 1 },
    'hashref value');

my $array = $client->eval('$array');
isa_ok($array, 'ArrayThing', 'Get blessed arrayref');
is_deeply($array,
    [ 1, 2, 3 ],
    'arrayref value');

my $scalar = $client->eval('$scalar');
isa_ok($scalar, 'ScalarThing', 'Get blessed scalar');
is($$scalar, 'a string', 'scalarref value');


my $code = $client->eval('$code');
isa_ok($code, 'CodeThing', 'Get blessed coderef');
like($code->(), qr(Put in place by), 'call dummy coderef');


my $complex = $client->eval('$complex');
isa_ok($complex, 'ComplexThing', 'Get value of a complex structure');
is_deeply($complex,
    [
        $hash,
        $array,
        $scalar,
    ],
    'complex value is correct');



__DATA__
my $hash = bless {a => 1 }, 'HashThing';
my $array = bless [ 1,2,3 ], 'ArrayThing';
my $string = "a string";
my $scalar = bless \$string, 'ScalarThing';
my $code = bless sub { 1; }, 'CodeThing';
my $complex = bless [ $hash, $array, $scalar ], 'ComplexThing';
$DB::single=1;
1;
