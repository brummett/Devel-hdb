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
    plan tests => 41;
}

my $json = JSON->new();
my $url = start_test_program();
my $mech = WWW::Mechanize->new();

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
    }
}
    

sub is_in {
    my($target, $list, $msg) = @_;
    ok(scalar(grep { $target eq $_ } @$list), $msg);
}



__DATA__
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
