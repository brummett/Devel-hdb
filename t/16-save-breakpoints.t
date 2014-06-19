use strict;
use warnings;

use lib 't';
use HdbHelper;
use IO::File;
use Data::Dumper;
use Devel::hdb::Client;

use File::Temp;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 15;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp;

my $stack = $client->stack();
my $filename = $stack->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 2, subroutine => 'main::MAIN' } ],
    'Stopped on line 2');

$resp = $client->create_breakpoint( filename => $filename, line => 3, code => 1, inactive => 1 );
ok($resp, 'set breakpoint');

$resp = $client->create_action( filename => $filename, line => 4, code => '123', inactive => 1 );
ok($resp, 'set action');

my $configfile = File::Temp::tmpnam();
$resp = $client->save_config($configfile);
ok($resp, 'save config');
ok(-f $configfile, 'Config file created');

eval "END { unlink '$configfile' }";

config_file_is_correct($configfile);

sub config_file_is_correct {
    my $file = shift;
    my $fh = IO::File->new($file, 'r') || die "Can't load $file: $!";
    local($/);
    my $content = <$fh>;

    my $config = eval $content;
    is( scalar(@{$config->{breakpoints}}), 1, '1 saved breakpoint');
    is( scalar(@{$config->{actions}}), 1, '1 saved action');

    my $bp = $config->{breakpoints}->[0];
    is( $bp->{inactive}, 1, 'Inactive');
    is( $bp->{code}, '1', '    unconditional breakpoint');
    is( $bp->{line}, 3, '    on line 3');
    is ($bp->{filename}, $filename, "    of $filename");

    my $action = $config->{actions}->[0];
    is( $action->{inactive}, 1, 'Inactive');
    is( $action->{code}, 123, '    action code');
    is( $action->{line}, 4, '    on line 4');
    is( $action->{filename}, $filename, "    of $filename");
}

    

__DATA__
use lib 't';
2;
3;
4;
5;
require TestNothing;
7;
