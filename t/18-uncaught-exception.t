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
    plan tests => 4;
}

my $url = start_test_program();

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'stack');
ok($resp->is_success, 'Request stack position');
$stack = $json->decode($resp->content);
my $filename = $stack->{data}->[0]->{filename};

$resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
# expecting 'stack', 'termination' messages
my @messages = sort { $a->{type} cmp $b->{type} } @{ $json->decode($resp->content) };

is($messages[0]->{data}->[0]->{subroutine},
    'Devel::Chitin::exiting::at_exit',
    'Stopped in at_exit()');

is_deeply($messages[1],
    {   type => 'termination',
        data => {
            'package'   => 'main',
            line        => 11,
            filename    => $filename,
            exception   => "This is an uncaught exception at $filename line 11.\n",
            exit_code   => 255,
            subroutine  => 'main::do_die2',
        }
    },
    'Got termination/exception message');


__DATA__
eval { die "inside eval" };
die "exception was not trapped: $@" unless $@ =~ m/^inside eval at/;
&do_die();
4;
$DB::single = 1;
6;
sub do_die {
    &do_die2()
}
sub do_die2 {
    die "This is an uncaught exception";
}
    
