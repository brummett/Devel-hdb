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
    plan tests => 28;
}

my $url = start_test_program();

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'stack');
ok($resp->is_success, 'Request stack position');

$stack = $json->decode($resp->content);
my $filename = $stack->{data}->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');

$resp = $mech->get($url.'stack');
ok($resp->is_success, 'get stack');
$stack = $json->decode($resp->content);
$stack = $stack->{data};

my @expected = (
    {   package     => 'Bar',
        filename    => $filename,
        subroutine  => 'Bar::baz',
        line        => 15,
        hasargs     => 1,
        wantarray   => 1,
        evaltext    => undef,
        evalfile    => undef,
        evalline    => undef,
        is_require  => undef,
        autoload    => undef,
        subname     => 'baz',
        args        => [],
    },
    {   package     => 'Bar',
        filename    => qr/\(eval \d+\)\[$filename:10\]/,
        subroutine  => qr/\(eval\)/,
        line        => 1,          # It's line 1 if the eval-ed text
        hasargs     => 0,
        wantarray   => 1,
        evaltext    => "baz();",
        evalfile    => $filename,
        evalline    => 10,
        is_require  => '',     # false but not undef because it is a string eval
        autoload    => undef,
        subname     => qr/\(eval\)/,
        args        => [],
    },
    {   package     => 'Bar',
        filename    => $filename,
        subroutine  => '(eval)',
        line        => 10,
        hasargs     => 0,
        wantarray   => 1,
        evaltext    => undef,
        evalfile    => undef,
        evalline    => undef,
        is_require  => undef,
        autoload    => undef,
        subname     => qr/\(eval\)/,
        args        => [],
    },
    {   package     => 'Bar',
        filename    => $filename,
        subroutine  => 'Bar::bar',
        line        => 9,
        hasargs     => 1,
        wantarray   => 1,
        evaltext    => undef,
        evalfile    => undef,
        evalline    => undef,
        is_require  => undef,
        autoload    => undef,
        subname     => 'bar',
        args        => [],
    },
    {   package     => 'main',
        filename    => $filename,
        subroutine  => 'main::foo',
        line        => 4,
        hasargs     => 1,
        wantarray   => undef,
        evaltext    => undef,
        evalfile    => undef,
        evalline    => undef,
        is_require  => undef,
        autoload    => undef,
        subname     => 'foo',
        args        => [1,2,3],
    },
    {   package     => 'main',
        filename    => $filename,
        subroutine  => 'main::MAIN',
        line        => 1,
        hasargs     => 1,
        wantarray   => undef,
        evaltext    => undef,
        evalfile    => undef,
        evalline    => undef,
        is_require  => undef,
        autoload    => undef,
        subname     => 'MAIN',
        args        => [],
    },
);
for (my $i = 0; $i < @expected; $i++) {
    delete $stack->[$i]->{hints};
    delete $stack->[$i]->{bitmask};
    delete $stack->[$i]->{level};

    _compare_strings(   delete $stack->[$i]->{subroutine},
                        delete $expected[$i]->{subroutine},
                        "subroutine matches for level $i");

    _compare_strings(   delete $stack->[$i]->{subname},
                        delete $expected[$i]->{subname},
                        "subname matches for level $i");

    _compare_strings(   delete $stack->[$i]->{filename},
                        delete $expected[$i]->{filename},
                        "filename matches for level $i");

    is_deeply($stack->[$i],
                $expected[$i],
                "Other stack frame matches for frame $i");
}


sub _compare_strings {
    my($got, $expected, $message) = @_;
    if (ref $expected) {
        like($got, $expected, $message);
    } else {
        is($got, $expected, $message);
    }
}

__DATA__
foo(1,2,3);             # 1

sub foo {
    @a = Bar::bar();    # 4
}

package Bar;
sub bar {
    eval {              # 9
        eval "baz();";  # 10
    }
}
sub baz {
    $DB::single = 1;
    15;
}
