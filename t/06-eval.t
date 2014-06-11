use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 21;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp = $client->continue();
is($resp->{line}, 9, 'Run to breakpoint');

$resp = $client->eval('$global');
is($resp, 1, 'Get value of a global scalar in the default package');
    
my @resp = $client->eval('@Other::global');
is_deeply(\@resp,
    [1, 2],
    'Get value of a global list in another package');

my %resp = $client->eval('%lexical');
is_deeply(\%resp,
    { key => 3 },
    'Get value of a lexical hash');

$resp = eval { $client->eval('do_die()') };
ok(! $resp && $@, 'eval a sub call that dies');
use Data::Dumper;
print Data::Dumper::Dumper($@);
is($@->message(
    {   type => 'evalresult',
        data => { expr => 'do_die()', exception => "in do_die\n" } },
    'caught exception');

$resp = $mech->post("${url}eval", content => '$refref');
ok($resp->is_success, 'Get value of a reference to a reference');
$answer = $json->decode($resp->content);
ok(delete $answer->{data}->{result}->{__refaddr}, 'Encoded value has a refaddr');
ok(delete $answer->{data}->{result}->{__value}->{__refaddr}, 'Reference value has a refaddr');
is_deeply($answer,
    {   type => 'evalresult',
        data => { expr => '$refref',
                  result => {
                      __reftype => 'REF',
                      __value => {
                          __reftype => 'SCALAR',
                          __value => 1
                        }
                    }
                }
    },
    'Value is correct');


$resp = $mech->post("${url}eval", content => '*STDOUT');
ok($resp->is_success, 'Get value of a reference to a reference');
$answer = $json->decode($resp->content);
ok(delete $answer->{data}->{result}->{__refaddr}, 'Encoded value has a refaddr');
ok(delete $answer->{data}->{result}->{__value}->{SCALAR}->{__refaddr}, 'Contained SCALAR value has a refaddr');
is_deeply($answer,
    {   type => 'evalresult',
        data => { expr => '*STDOUT',
                  result => {
                      __reftype => 'GLOB',
                      __value => {
                        NAME => 'STDOUT',
                        PACKAGE => 'main',
                        IO => 1,
                        IOseek => undef,
                        SCALAR => {
                            __reftype => 'SCALAR',
                            __value => undef
                        },
                      },
                  },
              },
    },
    'Encoded bare typeglob');


$resp = $mech->post("${url}eval", content => '@_');
ok($resp->is_success, 'Get value of @_');
$answer = $json->decode($resp->content);
strip_refaddr($answer->{data}->{result});
is_deeply($answer,
    {   type => 'evalresult',
        data => {
            expr => '@_',
            result => {
                __reftype => 'ARRAY',
                __value => [ 1, 2, 3 ],
            }
        }
    },
    '@_ is correct');





__DATA__
$global = 1;                # package global
@Other::global = (1,2);     # different package
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
