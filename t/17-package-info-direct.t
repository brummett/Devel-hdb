use strict;
use warnings;

use lib 't';

use Test::More tests => 17;

use Devel::hdb::DB::PackageInfo;

my @tests = (
    { pkg => 'main',    pkgs => [qw( Foo Quux )],   has_subs => 0 },
    { pkg => 'Foo',     pkgs => [qw( Bar )],        has_subs => 1 },
    { pkg => 'Foo::Bar',    pkgs => [qw( Baz )],    has_subs => 1 },
    { pkg => 'Foo::Bar::Baz',   pkgs => [ ],        has_subs => 0 },
    { pkg => 'Not::There',  pkgs => undef,          has_subs => 0 },
    { pkg => 'Quux',        pkgs => [qw( Sub )],    has_subs => 1 },
    { pkg => 'Quux::Sub',   pkgs => [qw( Package)], has_subs => 0 },
    { pkg => 'Quux::Sub::Package', pkgs => [ ],     has_subs => 1 },
);

foreach my $test ( @tests ) {
    my($package, $sub_packages, $has_subs) = @$test{'pkg', 'pkgs', 'has_subs'};

    my $got_packages = Devel::hdb::DB::PackageInfo::namespaces_in_package($package);
    if (!defined $sub_packages) {
        ok(!defined($got_packages), "Package $package does not exist");

    } elsif (@$sub_packages) {
        foreach my $target ( @$sub_packages ) {
            is_in($target, $got_packages, "Found sub-package $target in package $package");
        }
    } else {
        is_deeply($got_packages, [], "Package $package has no sub-packages");
    }
    next unless $has_subs;

    my $subs = Devel::hdb::DB::PackageInfo::subs_in_package($package);
    foreach my $c ( 1 .. 2) {
        (my $subname = lc($package)) =~ s/::/_/g;
        $subname .= "_$c";
        is_in($subname, $subs, "Found $subname in package $package");
    }
}

sub is_in {
    my($target, $list, $msg) = @_;
    ok(scalar(grep { $target eq $_ } @$list), $msg);
}


# Below here are  packages we're goin to be introspecting

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
