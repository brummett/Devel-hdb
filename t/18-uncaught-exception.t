use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 2;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp = $client->status();
ok($resp, 'status');
my $filename = $resp->{filename};

$resp = $client->continue();
delete @$resp{'filename','line'};
is_deeply($resp,
    { subroutine => 'Devel::Chitin::exiting::at_exit',
      running => 0,
      events => [
        {
            type => 'exception',
            package => 'main',
            subroutine => 'main::do_die2',
            filename => $filename,
            line => 11,
            value => "This is an uncaught exception at $filename line 11.\n",
        },
        {
            type => 'exit',
            value => 255,
        },
    ] },
    'continue response');


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
    
