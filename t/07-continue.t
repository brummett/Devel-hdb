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
    plan tests => 5;
}

my $url = start_test_program();

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'stack');
ok($resp->is_success, 'Request stack position');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
# Expecting 'stack' and 'termination' messages
my @messages = sort { $a->{type} cmp $b->{type} } @{ $json->decode($resp->content) };
is($messages[0]->{data}->[0]->{subroutine},
    'Devel::Chitin::exiting::at_exit',
    'Stopped in at_exit()');
is_deeply($messages[1],
    { type => 'termination', data => { exit_code => 3 } },
    'Got termination message');

__END__
1;
foo();
exit(3);
sub foo {
    5;
}

