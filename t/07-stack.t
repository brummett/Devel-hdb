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
    plan tests => 20;
}

my($url, $pid, $filename) = start_test_program();

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'continue');
ok($resp->is_success, 'Run to first breakpoint');
$stack = $json->decode($resp->content)->{data};

is($stack->[0]->{line}, 15, 'Stopped on line 15');
my $level = $stack->[0]->{level};

my @expected = (
    {   wantarray   => undef,
        subroutine  => 'ListPackage::noargs_fn',
        args        => [],
        hasargs     => 0,
        package     => 'ListPackage',
        evaltext    => undef,
        level       => $level++,
        subname     => 'noargs_fn',
        is_require  => undef,
        line        => 15,
    },
    {   wantarray   => undef,
        subroutine  => '(eval)',
        args        => [],
        hasargs     => 0,
        package     => 'ListPackage',
        evaltext    => "&noargs_fn\n;",
        level       => $level++,
        subname     => '(eval)',
        is_require  => '',
        line        => 1,
    },
    {   wantarray   => 1,
        subroutine  => 'ListPackage::list_fn',
        args        => [1,2,3],
        hasargs     => 1,
        package     => 'ListPackage',
        evaltext    => undef,
        level       => $level++,
        subname     => 'list_fn',
        is_require  => undef,
        line        => 10,
    },
    {   wantarray   => 0,
        subroutine  => 'main::scalar_fn',
        args        => [1],
        hasargs     => 1,
        package     => 'main',
        evaltext    => undef,
        level       => $level++,
        subname     => 'scalar_fn',
        is_require  => undef,
        line        => 6,
    },
    {   wantarray   => undef,
        subroutine  => 'main::void_fn',
        args        => [],
        hasargs     => 1,
        package     => 'main',
        evaltext    => undef,
        level       => $level++,
        subname     => 'void_fn',
        is_require  => undef,
        line        => 3,
    },
    {   wantarray   => undef,
        subroutine  => 'MAIN',
        args        => [],
        hasargs     => 1,
        package     => 'main',
        evaltext    => undef,
        level       => $level++,
        subname     => 'MAIN',
        is_require  => undef,
        line        => 1,
    },
);
        
for (my $i = 0; $i < @expected; $i++) {
    my $frame_filename = delete($stack->[$i]->{filename});
    if ($stack->[$i]->{evaltext}) {
        my $escaped_filename = quotemeta($filename);
        like($frame_filename, qr(\(eval \d+\)[$escaped_filename:\d+]), "Filename stack frame $i");
    } else {
        is($frame_filename, $filename, "Filename stack frame $i");
    }

    # Some perls use 0 for false, others use ''
    my($expected_hasargs, $hasargs) = ( delete($expected[$i]->{hasargs}), delete $stack->[$i]->{hasargs});
    $hasargs = $expected_hasargs ? $hasargs : !$hasargs;
    ok($hasargs, "Stack frame $i hasargs");

    my($expected_wantarray, $wantarray) = ( delete($expected[$i]->{wantarray}), delete $stack->[$i]->{wantarray});
    if (defined $expected_wantarray) {
        $wantarray = $expected_wantarray ? $wantarray : !$wantarray;
        ok($wantarray, "Stack frame $i wantarray");
    } else {
        ok(! defined($wantarray), "Stack frame $i wantarray");
    }
}


__DATA__
void_fn();
sub void_fn {
    my $a = scalar_fn(1);
}
sub scalar_fn {
    my @a = ListPackage::list_fn(1,2,3);
}
package ListPackage;
sub list_fn {
    eval "&noargs_fn";
    1;
}
sub noargs_fn {
    $DB::single = 1;
    15;
}
