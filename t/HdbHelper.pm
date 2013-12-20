package HdbHelper;

BEGIN { delete $ENV{'http_proxy'} }

use strict;
use warnings;

use File::Basename;
use IO::Socket;
use File::Temp;
use IO::File;
use Fcntl;
use Time::HiRes qw(sleep);

use Exporter 'import';
our @EXPORT = qw( start_test_program strip_stack strip_stack_inc_args strip_refaddr );


my $out_fh;
my $program_source;
sub start_test_program {

    my($program_file, $module_args);
    if ($_[0] and $_[0] eq '-file') {
        (undef, $program_file) = splice(@_,0,2);
    }
    if ($_[0] and $_[0] eq '-module_args') {
        (undef, $module_args) = splice(@_,0,2);
    }
    my @argv = @_;

    if ($program_file) {
        $out_fh = IO::File->new($program_file,'w');
    } else {
        $out_fh = File::Temp->new(TEMPLATE => 'devel-hdb-test-XXXX', TMPDIR => 1);
        $program_file = $out_fh->filename();
    }

    unless ($program_source) {
        # Localize $/ for slurp mode
        # Localize $. to avoid die messages including 
        local($/, $.);
        my $pkg = caller;
        my $in_fh = do {
            no strict 'refs';
            *{ $pkg . '::DATA' };
        };
        $program_source = <$in_fh>;
    }
    $out_fh->print($program_source);
    $out_fh->close();

    my $libdir = File::Basename::dirname(__FILE__). '/../lib';

    # Create a listen socket for the child process to use
    my $listen_sock = IO::Socket::INET->new(LocalAddr => '127.0.0.1',
                                            Proto => 'tcp',
                                            Listen => 5);
    my $sock_flags = fcntl($listen_sock, F_GETFD, 0) or die "fcntl F_GETFD: $!";
    fcntl($listen_sock, F_SETFD, $sock_flags & ~FD_CLOEXEC) or die "fcntl F_SETFD: $!";
    my $port = $listen_sock->sockport();

    my $module_invocation = "-d:hdb=testharness,listenfd:".$listen_sock->fileno;
    if ($module_args) {
        $module_invocation .= ",$module_args";
    }
    my $cmdline = join(' ', $^X, "-I $libdir $module_invocation",
                               $program_file,
                               @argv);

    my $pid = fork();
    if ($pid) {
        Test::More::note("pid $pid");
    } elsif(defined $pid) {
        Test::More::note("running $cmdline");
        exec($cmdline) || die "Running child process failed: $!";
    } else {
        die "fork failed: $!";
    }

    eval "END { Test::More::note('Killing pid $pid'); kill 'TERM',$pid }";
    $HdbHelper::child_pid = $pid;

    if (wantarray) {
        return ("http://localhost:${port}/", $pid, $program_file);
    } else {
        return "http://localhost:${port}/";
    }
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

sub strip_stack_inc_args {
    my $stack = shift;
    if (ref $stack eq 'ARRAY') {
        $stack = shift @$stack;  # If multiple messages passed in
    }
    if ($stack->{type} ne 'stack') {
        return $stack;  # not was expected, return the whole thing
    }
    return [ map { { line => $_->{line}, subroutine => $_->{subroutine}, args => $_->{args} } } @{$stack->{data}} ];
}

# recursively remove all occurances of __refaddr
sub strip_refaddr {
    my $value = shift;

    return unless ref $value;

    if ($value->{__reftype} && $value->{__refaddr}) {
        delete $value->{__refaddr};
        return unless exists($value->{__value});
        my $reftype = ref($value->{__value});
        if ($reftype eq 'ARRAY') {
            strip_refaddr($_) foreach @{$value->{__value}};
        } elsif ($reftype eq 'HASH') {
            strip_refaddr($_) foreach (values %{$value->{__value}});
        }
    }
}


1;
