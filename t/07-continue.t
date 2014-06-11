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

my $stack = $client->stack();
my $filename = $stack->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 1, subroutine => 'main::MAIN' } ],
    'Stopped on line 1');

my $resp = $client->continue();
my $stopped_filename = delete $resp->{filename};
my $stopped_line = delete $resp->{line};
is_deeply($resp,
    { subroutine => 'Devel::Chitin::exiting::at_exit', running => 0, exit_code => 3 },
    'continue to end');

__END__
1;
foo();
exit(3);
sub foo {
    5;
}

