use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;
use Devel::hdb::App;
use IO::Handle;

use Devel::hdb::App::EncodePerlData qw(encode_perl_data);

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 17;
}

my %tied_hash;
tie %tied_hash, 'HdbHelper::Tied';
my $encoded = encode_perl_data(\%tied_hash);
ok($encoded, 'Encode a tied hash directly');
ok(delete $encoded->{__refaddr}, 'encoded has a refaddr');
ok(delete $encoded->{__tied}->{__refaddr}, 'tie object has a refaddr');
is_deeply($encoded,
    {   __reftype => 'HASH',
        __tied => {
            __reftype => 'SCALAR',
            __blessed => 'HdbHelper::Tied',
            __value => 'HdbHelper::Tied',
        },
    },
    'Encoded tied hash correctly');

my $tied_handle = IO::Handle->new();
tie *$tied_handle, 'HdbHelper::Tied';
$encoded = encode_perl_data($tied_handle);
ok($encoded, 'Encode a tied handle directly');
ok(delete $encoded->{__refaddr}, 'encoded has a refaddr');
ok(delete $encoded->{__tied}->{__refaddr}, 'tie object has a refaddr');
is_deeply($encoded,
    {   __reftype => 'GLOB',
        __blessed => 'IO::Handle',
        __tied => {
            __reftype => 'HASH',
            __blessed => 'HdbHelper::Tied',
            __value => { is_tied_handle => 'HdbHelper::Tied' },
        },
    },
    'Encoded tied handle correctly');


my $url = start_test_program();

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'continue');
ok($resp->is_success, 'Run to breakpoint');

$resp = $mech->post("${url}eval", content => '%tied_hash');
ok($resp->is_success, 'Get value of a tied hash through api');
my $answer = $json->decode($resp->content);
ok(delete $answer->{data}->{result}->{__refaddr}, 'encoded has a refaddr');
ok(delete $answer->{data}->{result}->{__tied}->{__refaddr}, 'tie object has a refaddr');
is_deeply($answer->{data},
    {   expr => '%tied_hash',
        result => { __reftype => 'HASH',
                    __tied => {
                        __reftype => 'SCALAR',
                        __blessed => 'HdbHelper::Tied',
                        __value   => 'HdbHelper::Tied',
                    }
        }
    },
    'value is correct');
    
$resp = $mech->post("${url}eval", content => '$tied_handle');
ok($resp->is_success, 'Get value of a tied handle through api');
$answer = $json->decode($resp->content);
ok(delete $answer->{data}->{result}->{__refaddr}, 'encoded has a refaddr');
ok(delete $answer->{data}->{result}->{__tied}->{__refaddr}, 'encoded has a refaddr');
is_deeply($answer->{data},
    { expr => '$tied_handle',
      result => { __blessed => 'IO::Handle',
                  __reftype => 'GLOB',
                  __tied => {
                        __blessed => 'HdbHelper::Tied',
                        __reftype => 'HASH',
                        __value => { is_tied_handle => 'HdbHelper::Tied' },
                    }
            }
    },
    'value is correct');

# Ugly: This part is duplicated in the test program below
package HdbHelper::Tied;
sub TIEHASH {
    my $class = shift;
    return bless \$class, $class;
}

sub TIEHANDLE {
    my $class = shift;
    return bless { is_tied_handle => $class }, $class;
}

package main;  # Make the DATA section in the main package

__DATA__
use IO::Handle;

my %tied_hash;
tie %tied_hash, 'HdbHelper::Tied';

my $tied_handle = IO::Handle->new();
tie *$tied_handle, 'HdbHelper::Tied';

$DB::single=1;
1;

package HdbHelper::Tied;
sub TIEHASH {
    my $class = shift;
    return bless \$class, $class;
}

sub TIEHANDLE {
    my $class = shift;
    return bless { is_tied_handle => $class }, $class;
}

