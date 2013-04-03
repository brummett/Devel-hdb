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
    plan tests => 8;
}

my $url = start_test_program();

my $json = JSON->new();
my $response;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');
$response = $json->decode($resp->content);

my $stack;
my($child_uri, $child_pid);

# should get two response messages, one with the new stack position
# and another with the child announcement

# 'child_process' sorts before 'stack'
my @responses = sort { $a->{type} cmp $b->{type} } @$response;
($child_uri, $child_pid) = check_child_process_message($responses[0]);

$stack = strip_stack($responses[1]);
is_deeply($stack,
        [ { line => 6, subroutine => 'MAIN' } ],
        'Parent process stopped on line 6');

eval qq(END { kill 'TERM', $child_pid }) if ($child_pid);

$resp = $mech->get($child_uri.'stack');
ok($resp->is_success, 'Request stack from child process');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
        [ { line => 3, subroutine => 'MAIN' } ],
        'Child process stopped immediately after fork');


sub check_child_process_message {
    my $msg = shift;

    is($msg->{type}, 'child_process', 'Saw child_process message');
    my $cpid = $msg->{data}->{pid};
    like($cpid, qr(^\d+$), 'pid data looks like a pid');;

    my $curi = $msg->{data}->{uri};
    like($curi,
        qr(^http://127.0.0.1:\d+/$),
        'uri data looks like a uri');

    like($msg->{data}->{run},
        qr(^${curi}continue\?nostop=1$),
        'run data looks ok');

    return ($curi, $cpid);
}


__DATA__
my $orig_pid = $$;
if (! fork) {
    3;  #child
}
$DB::single = 1 if ($$ == $orig_pid);
6;
print "___ pid $$ exiting\n";
