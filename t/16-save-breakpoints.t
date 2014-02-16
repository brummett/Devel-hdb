use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;
use IO::File;
use Data::Dumper;
use Devel::Chitin::Actionable;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 29;
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
    [ { line => 2, subroutine => 'main::MAIN' } ],
    'Stopped on line 2');

$resp = $mech->post($url.'breakpoint', { f => $filename, l => 3, c => 1, ci => 1 });
ok($resp->is_success, 'set breakpoint');

$resp = $mech->post($url.'action', { f => $filename, l => 4, c => '123', ci => 1 });
ok($resp->is_success, 'set action');

$resp = $mech->post($url.'saveconfig');
ok($resp->is_success, 'save config');
my $result = $json->decode($resp->content)->{data};
is($result->{success}, 1, 'successful');

my $configfile = $result->{filename};
eval "END { unlink '$configfile' }";

config_file_is_correct($configfile);

my $another_configfile = File::Temp::tmpnam();
eval "END { unlink '$another_configfile' }";
$resp = $mech->post($url.'saveconfig', { f => $another_configfile });
ok($resp->is_success, 'save config');
$result = $json->decode($resp->content)->{data};
is($result->{success}, 1, 'successful');
is($result->{filename}, $another_configfile, 'Saved to correct filename');

config_file_is_correct($another_configfile);


sub config_file_is_correct {
    my $file = shift;
    my $fh = IO::File->new($file, 'r') || die "Can't load $file: $!";
    local($/);
    my $content = <$fh>;

    my $config = eval $content;
    is( scalar(@{$config->{breakpoints}}), 1, '1 saved breakpoint');
    is( scalar(@{$config->{actions}}), 1, '1 saved action');

    my $bp = $config->{breakpoints}->[0];
    is( $bp->inactive, 1, 'Inactive');
    is( $bp->code, '1', '    unconditional breakpoint');
    is( $bp->line, 3, '    on line 3');
    is ($bp->file, $filename, "    of $filename");

    my $action = $config->{actions}->[0];
    is( $action->inactive, 1, 'Inactive');
    is( $action->code, 123, '    action code');
    is( $action->line, 4, '    on line 4');
    is( $action->file, $filename, "    of $filename");
}

    

__DATA__
use lib 't';
2;
3;
4;
5;
require TestNothing;
7;
