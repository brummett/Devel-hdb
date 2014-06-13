use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 4;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp = $client->continue();
is($resp->{line}, 5, 'continue to line 5');

my $stack = $client->stack();
is($stack->[0]->{subroutine}, 'main::AUTOLOAD', 'Stopped in recursive AUTOLOAD');
is($stack->[0]->{subname}, 'AUTOLOAD(bar)', 'Short subname shows the recursive called sub name');
is($stack->[1]->{subname}, 'AUTOLOAD(foo)', 'Short subname shows the first called sub name');


__DATA__
foo();
2;
sub AUTOLOAD {
    $DB::single=1 if $AUTOLOAD eq 'main::bar';
    bar();
    5;
}
