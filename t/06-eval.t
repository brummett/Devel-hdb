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
    plan tests => 19;
}

my $url = start_test_program();

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'continue');
ok($resp->is_success, 'Run to breakpoint');

$resp = $mech->post("${url}eval", content => '$global');
ok($resp->is_success, 'Get value of a global scalar in the default package');
my $answer = $json->decode($resp->content);
is_deeply($answer,
    {   type => 'evalresult',
        data => { expr => '$global', result => 1 }
    },
    'value is correct');
    
$resp = $mech->post("${url}eval", content => '@Other::global');
ok($resp->is_success, 'Get value of a global list in another package');
$answer = $json->decode($resp->content);
ok(delete $answer->{data}->{result}->{__refaddr}, 'Encoded value has a refaddr');
is_deeply($answer,
    {   type => 'evalresult',
        data => { expr => '@Other::global',
                  result => {
                      __reftype => 'ARRAY',
                      __value => [1,2] },
                }
    },
    'Value is correct');

$resp = $mech->post("${url}eval", content => '%lexical');
ok($resp->is_success, 'Get value of a lexical hash');
$answer = $json->decode($resp->content);
ok(delete $answer->{data}->{result}->{__refaddr}, 'Encoded value has a refaddr');
is_deeply($answer,
    {   type => 'evalresult',
        data => { expr => '%lexical',
                  result => {
                      __reftype => 'HASH',
                      __value => { key => 3} }
                }
    },
    'Value is correct');

$resp = $mech->post("${url}eval", content => 'do_die()');
ok($resp->is_success, 'eval a sub call that dies');
$answer = $json->decode($resp->content);
is_deeply($answer,
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
                        IO => 'fileno 1',
                        SCALAR => {
                            __reftype => 'SCALAR',
                            __value => undef
                        },
                      },
                  },
              },
    },
    'Encoded bare typeglob');
                    








__DATA__
$global = 1;                # package global
@Other::global = (1,2);     # different package
my %lexical = (key => 3);   # lexical
my $ref = \$global;
my $refref = \$ref;
$DB::single=1;
1;
sub do_die {
    die "in do_die\n";
}
