use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
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
if (ref($response) eq 'ARRAY' and @$response > 1) {
    # got the child announcement here
    # expecting child_announce and stack messages
    my @responses = sort { $a->{type} cmp $b->{type} } @$response;
    ($child_uri, $child_pid) = check_child_process_message($responses[0]);

    $stack = strip_stack($responses[1]);
    is_deeply($stack, 
            [ { line => 6, subroutine => 'MAIN' } ],
            'Parent process stopped on line 6');

} else {
    # only got the stack from program stopping
    $stack = strip_stack($response);
    is_deeply($stack, 
            [ { line => 6, subroutine => 'MAIN' } ],
            'Parent process stopped on line 6');

    my $retries = 5;
    do { 
        last if $retries-- < 0;

        sleep(0.1); # Give the child process a timeslice
        $resp = $mech->get($url.'ping');
        last unless $resp->is_success();
        $response = $json->decode($resp->content);
    } until (ref($response) eq 'ARRAY');
    ok($resp->is_success, 'ping to get child announcement');
    is(ref($response), 'ARRAY', 'Got ARRAY response to ping');

    my @responses = sort { $a->{type} cmp $b->{type} } @$response;
    ($child_uri, $child_pid) = check_child_process_message($responses[0]);

    is($responses[1]->{type}, 'ping', 'Got ping response');
}

eval qq(END { kill 'TERM', $child_pid }) if ($child_pid);

$resp = $mech->get($child_uri.'stack');
ok($resp->is_success, 'Request stack from child process');
$stack = strip_stack($json->decode($resp->content));
is_deeply($stack,
        [ { line => 3, subroutine => 'MAIN' } ],
        'Child process stopped immediately after fork');

done_testing();

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
