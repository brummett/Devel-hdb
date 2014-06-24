use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 73;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp = $client->continue();
ok($resp, 'Run to breakpoint');
my $filename = $resp->{filename};

my @tests = (
    { pkg => 'main',    pkgs => [ qw( Foo Quux ) ],    has_subs => 1 },
    { pkg => 'Foo',     pkgs => [ qw( Bar ) ],         has_subs => 1 },
    { pkg => 'Foo::Bar',pkgs => [ qw( Baz ) ],         has_subs => 1 },
    { pkg => 'Foo::Bar::Baz',   pkgs => [ ],           has_subs => 0 },
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

    my $resp = $client->package_info($package);
    ok($resp, "Get package info for $package");
    is($resp->{name}, $package, "package name $package");
    ok(exists($resp->{packages}), 'Saw info for packages');
    ok(exists($resp->{subroutines}), 'Saw info for subs');

    # Check for expected sub-packages
    if (@$sub_packages) {
        foreach my $target ( @$sub_packages ) {
            my($matched) = grep { $_->{name} eq $target } @{ $resp->{packages}};
            ok($matched, "Found sub-package $target");
            ok($matched->{href}, "$target has href");
        }
    } else {
        is_deeply($resp->{packages}, [], "Package $package had no sub-packages");
    }
    next unless $has_subs;

    # Check for expected subs
    foreach my $c ( 1 .. 2 ) {
        (my $subname = lc($package)) =~ s/::/_/g;
        $subname .= "_$c";
        my($matched) = grep { $_->{name} eq $subname } @{ $resp->{subroutines} };
        ok($matched, "Found $subname in package $package");
        ok($matched->{href}, "$subname has href");

        # Get info about this sub
        my $sub_info = $client->sub_info("${package}::${subname}");
        is_deeply($sub_info,
                {   subroutine => $subname,
                    package => $package,
                    filename => $filename,
                    line   => $sub_locations{$subname},
                    end     => $sub_locations{$subname},
                    source  => $filename,
                    source_line => $sub_locations{$subname},
                },
                "location for $subname in $package");
    }
}

$resp = eval { $client->package_info('Not::There') };
ok(!$resp && $@, 'Getting info on non-existent package throws exception');
is($@->http_code, 404, 'Error was Not Found');

$resp = $client->sub_info("main::on_the_fly");
my $file = delete $resp->{filename};
is_deeply($resp,
    {   subroutine => 'on_the_fly',
        package => 'main',
        line   => 1,
        end     => 4,
        source  => $filename,
        source_line => 1,
    },
    'location of on_the_fly matches expected');
like($file, qr{\(eval \d+\)\[$filename:1\]}, 'file matches expected');
    

$resp = eval { $client->sub_info("non::existent::sub") };
ok(!$resp && $@, 'Cannot get info on non-existent sub');
is($@->http_code, 404, 'Error was 404');


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
