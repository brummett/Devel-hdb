use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;
use IO::File;
use Data::Dumper;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 11;
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
    [ { line => 2, subroutine => 'MAIN' } ],
    'Stopped on line 2');

$resp = $mech->post($url.'breakpoint', { f => $filename, l => 3, c => 1, ci => 1 });
ok($resp->is_success, 'set breakpoint');

$resp = $mech->post($url.'breakpoint', { f => $filename, l => 4, a => '123', ai => 1 });
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
    $config->{breakpoints} = [ sort { $a->{lineno} <=> $b->{lineno} }
                                  @{ $config->{breakpoints} } ];
    is_deeply($config,
            { breakpoints => [
              { filename => $filename, lineno => 3, condition => 1, condition_inactive => 1 },
              { filename => $filename, lineno => 4, action => 123, action_inactive => 1 },
            ]},
            'File contents ok');
}

    

__DATA__
use lib 't';
2;
3;
4;
5;
require TestNothing;
7;
