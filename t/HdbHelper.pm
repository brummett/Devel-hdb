package HdbHelper;

BEGIN { delete $ENV{'http_proxy'} }

use strict;
use warnings;

use File::Basename;
use IO::Socket;
use File::Temp;
use Time::HiRes qw(sleep);

use Exporter 'import';
our @EXPORT = qw( start_test_program strip_stack );


my $out_fh;
sub start_test_program {
    my $pkg = caller;
    my $in_fh;
    {   no strict 'refs';
        $in_fh = *{ $pkg . '::DATA' };
    }
    $out_fh = File::Temp->new(TEMPLATE => 'devel-hdb-test-XXXX');

    {
        # Localize $/ for slurp mode
        # Localize $. to avoid die messages including 
        local($/, $.);
        $out_fh->print(<$in_fh>);
        $out_fh->close();
    }

    my $libdir = File::Basename::dirname(__FILE__). '/../lib';

    my $port = $ENV{DEVEL_HDB_PORT} = pick_unused_port();
    Test::More::note("Using port $ENV{DEVEL_HDB_PORT}\n");
    my $cmdline = $^X . " -I $libdir -d:hdb=port:$port,testharness " . $out_fh->filename;
    Test::More::note("running $cmdline");
    my $pid = fork();
    if ($pid) {
        Test::More::note("pid $pid");
        wait_on_port($port);
    } elsif(defined $pid) {
        exec($cmdline);
        die "Running child process failed: $!";
    } else {
        die "fork failed: $!";
    }

    eval "END { Test::More::note('Killing pid $pid'); kill 'TERM',$pid }";
    return ("http://localhost:${port}/");
}

# Pick a port not in use by the system
# It's kind of a hack, in that some other process _could_
# pick the same port between the time we close this one and the
# debugged program starts up.
# It also relies on the fact that HTTP::Server::PSGI specifies
# Reuse => 1 when it opens the port
sub pick_unused_port {
    my $s = IO::Socket::INET->new(Listen => 1, LocalAddr => 'localhost', Proto => 'tcp');
    my $port = $s->sockport();
    return $port;
}

# Waits until we can connect to the port
sub wait_on_port {
    my $port = shift;
    my $tries = shift;
    $tries = 100 unless defined $tries;

    my $s;
    while($tries--) {
        sleep 0.01;
        $s = IO::Socket::INET->new(PeerAddr => 'localhost',
                                        PeerPort => $port,
                                        Proto => 'tcp');
        last if $s;
        next if ($! eq 'Connection refused');
        die $!;
    }
    $s->close if $s;
    return $s;
}


# given a list of stack frames, return a new list with only
# line and subroutine.
# FIXME: when we figure out how to encode/decode blessed vars through JSON
# then we'll also want subroutine args
sub strip_stack {
    my $stack = shift;
    if (ref $stack eq 'ARRAY') {
        $stack = shift @$stack;  # If multiple messages passed in
    }
    if ($stack->{type} ne 'stack') {
        return $stack;  # not was expected, return the whole thing
    }
    return [ map { { line => $_->{line}, subroutine => $_->{subroutine} } } @{$stack->{data}} ];
}

1;
