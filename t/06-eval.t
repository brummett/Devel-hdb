use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 12;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp = $client->continue();
is($resp->{line}, 10, 'Run to breakpoint');

$resp = $client->eval('$global');
is($resp, 1, 'Get value of a global scalar in the default package');

my @resp = $client->eval('@Other::global');
is_deeply(\@resp,
    [1, 2],
    'Get value of a global list in another package');

$resp = $client->eval('$global_arrayref');
is_deeply($resp,
    [1, 2],
    'Get value of arrayref');

my %resp = $client->eval('%lexical');
is_deeply(\%resp,
    { key => 3 },
    'Get value of a lexical hash');

$resp = eval { $client->eval('do_die()') };
ok(! $resp && $@, 'eval a sub call that dies');
is($@->message,
    "in do_die\n",
    'caught exception');

$resp = $client->eval('$refref');
is($$$resp, 1, 'Get value of a reference to a reference');


$resp = $client->eval('*STDOUT');
is(ref(\$resp), 'GLOB', 'Get glob');
is(fileno($resp), 1, 'stdout fileno');


@resp = $client->eval('@_');
is_deeply(\@resp,
    [ 1, 2, 3 ],
    'Get value of @_');

@resp = $client->eval('returns_list()');
is_deeply(\@resp,
    [ 3, 2, 1 ],
    'Calling function returns list');


__DATA__
$global = 1;                # package global
@Other::global = (1,2);     # different package
$global_arrayref = \@Other::global;
my %lexical = (key => 3);   # lexical
my $ref = \$global;
my $refref = \$ref;
foo(1,2,3);
sub foo {
    $DB::single=1;
    1;
}
sub do_die {
    die "in do_die\n";
}
sub returns_list {
    return (3,2,1);
}
