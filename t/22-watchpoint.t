use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 7;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp;

my $stack = $client->stack();
ok($stack, 'Request stack position');
my $filename = $stack->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

$resp = $client->add_watchpoint( '$a' );
ok($resp, 'Add watchpoint for $a');

$resp = $client->continue();
is_deeply($resp,
    { filename => $filename, line => 2, subroutine => 'MAIN', running => 1, stack_depth => 1,
      events => [
            {   expr => '$a',
                type => 'watchpoint',
                filename => $filename,
                line => 1,
                subroutine => 'MAIN',
                package => 'main',
                old => [ undef ],
                new => [ 1 ]
            },
        ],

     },
    'difference on line 2')
        || diag explain $resp;

$resp = $client->continue();
is_deeply($resp,
    { filename => $filename, line => 4, subroutine => 'MAIN', running => 1, stack_depth => 1,
      events => [
            {   expr => '$a',
                type => 'watchpoint',
                filename => $filename,
                line => 3,
                subroutine => 'MAIN',
                package => 'main',
                old => [ 1 ],
                new => [ 3 ]
            },
        ],
    },
    'difference on line 4')
        || diag explain $resp;

$resp = $client->continue();
is_deeply($resp,
    { filename => $filename, line => 10, subroutine => 'main::foo', running => 1, stack_depth => 2,
      events => [
            {   expr => '$a',
                type => 'watchpoint',
                filename => $filename,
                line => 9,
                subroutine => 'main::foo',
                package => 'main',
                old => [ 3 ],
                new => [ { my => 'variable', lexical => 1 } ],
            },
        ],
    },
    'difference on line 10 inside foo()')
        || diag explain $resp;

$resp = $client->continue();
is_deeply($resp,
    { filename => $filename, line => 6, subroutine => 'MAIN', running => 1, stack_depth => 1,
      events => [
            {   expr => '$a',
                type => 'watchpoint',
                filename => $filename,
                line => 10,
                subroutine => 'main::foo',
                package => 'main',
                old => [ { my => 'variable', lexical => 1 } ],
                new => [ 3 ]
            },
        ],
    },
    'difference on line 6')
        || diag explain $resp;


__DATA__
$a = 1;
2;
$a = 3;
4;
foo();
6;

sub foo {
    my $a = { my => 'variable', lexical => 1 };
    10;
}

