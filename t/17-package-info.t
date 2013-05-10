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
    plan tests => 61;
}

my $json = JSON->new();
my $url = start_test_program();
my $mech = WWW::Mechanize->new();

my $resp = $mech->get($url.'continue');
ok($resp->is_success, 'Run to breakpoint');
my $stack = $json->decode($resp->content);
my $filename = $stack->{data}->[0]->{filename};

my @tests = (
    { pkg => 'main',    pkgs => [ qw( Foo Quux ) ],    has_subs => 1 },
    { pkg => 'Foo',     pkgs => [ qw( Bar ) ],         has_subs => 1 },
    { pkg => 'Foo::Bar',pkgs => [ qw( Baz ) ],         has_subs => 1 },
    { pkg => 'Foo::Bar::Baz',   pkgs => [ ],           has_subs => 0 },
    { pkg => 'Not::There',      pkgs => undef,         has_subs => 0 },
    { pkg => 'Quux',    pkgs => [ qw( Sub ) ],         has_subs => 1 },
    { pkg => 'Quux::Sub',   pkgs => [ qw( Package ) ], has_subs => 0 },
    { pkg => 'Quux::Sub::Package', pkgs => [ ],        has_subs => 0 },
);

my %sub_locations = (
    'main_1'    => 8,
    'main_2'    => 9,
    'foo_1'     => 13,
    'foo_2'     => 14,
    'foo_bar_1' => 18,
    'foo_bar_2' => 19,
    'foo_bar_baz_1' => 23,
    'foo_bar_baz_2' => 24,
    'quux_1'    => 28,
    'quux_2'    => 29,
    'quux_sub_package_1' => 33,
    'quux_sub_pacakge_2' => 34,
);

foreach my $test ( @tests ) {

    my($package, $sub_packages, $has_subs) = @$test{'pkg', 'pkgs', 'has_subs'};

    my $resp = $mech->get($url."pkginfo/${package}");
    ok($resp->is_success, "Get package info for $package");
    my $info = $json->decode($resp->content);
    ok(exists($info->{data}->{packages}), 'Saw info for packages');
    ok(exists($info->{data}->{subs}), 'Saw info for subs');

    # Check for expected sub-packages
    if (!defined $sub_packages) {
        ok(!defined($info->{data}->{packages}), "Package $package does not exist");
    } elsif (@$sub_packages) {
        foreach my $target ( @$sub_packages ) {
            is_in($target, $info->{data}->{packages}, "Found sub-package $target");
        }
    } else {
        is_deeply($info->{data}->{packages}, [], "Package $package had no sub-packages");
    }
    next unless $has_subs;

    # Check for expected subs
    foreach my $c ( 1 .. 2 ) {
        (my $subname = lc($package)) =~ s/::/_/g;
        $subname .= "_$c";
        is_in($subname, $info->{data}->{subs}, "Found $subname in package $package");

        # Get info about this sub
        $resp = $mech->get("${url}subinfo/${package}::${subname}");
        ok($resp->is_success, "Get source location about $subname in $package");
        my $sub_info = $json->decode($resp->content);
        is_deeply($sub_info->{data},
                {   file    => $filename,
                    start   => $sub_locations{$subname},
                    end     => $sub_locations{$subname},
                    source  => $filename,
                    source_line => $sub_locations{$subname},
                },
                "location matches expected");
    }
}

$resp = $mech->get("${url}subinfo/main::on_the_fly");
ok($resp->is_success, 'Get info about main::on_the_fly');
my $sub_info = $json->decode($resp->content);

my $file = delete $sub_info->{data}->{file};
like($file, qr{\(eval \d+\)\[$filename:1\]}, 'file matches expected');
is_deeply($sub_info->{data},
    {   start   => 1,
        end     => 4,
        source  => $filename,
        source_line => 1,
    },
    'location matches expected');
    

sub is_in {
    my($target, $list, $msg) = @_;
    ok(scalar(grep { $target eq $_ } @$list), $msg);
}



__DATA__
eval "sub main::on_the_fly {
    1;
    2;
}";
$DB::single=1;
1;

sub main_1 { 1}
sub main_2 { 1}

package Foo;

sub foo_1 { 1}
sub foo_2 { 1}

package Foo::Bar;

sub foo_bar_1 { 1}
sub foo_bar_2 { 1}

package Foo::Bar::Baz;

sub foo_bar_baz_1 {1}
sub foo_bar_baz_2 {1}

package Quux;

sub quux_1 {1}
sub quux_2 {1}

package Quux::Sub::Package;

sub quux_sub_package_1 {1}
sub quux_sub_package_2 {1}
