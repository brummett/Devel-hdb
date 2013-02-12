package Devel::hdb::TestBase;

use strict;
use warnings;

use File::Basename;

use Exporter 'import';
our @EXPORT = qw( start_test_program );

use File::Temp;

sub start_test_program {
    my $pkg = caller;
    my $in_fh;
    {   no strict 'refs';
        $in_fh = *{ $pkg . '::DATA' };
    }
    my $out_fh = File::Temp->new('devel-hdb-test-XXXX');

    {
        # Localize $/ for slurp mode
        # Localize $. to avoid die messages including 
        local($/, $.);
        $out_fh->print(<$in_fh>);
        $out_fh->close();
    }

    my $libdir = File::Basename::dirname(__FILE__). '/../../../lib';

print "running ".$^X . " -I $libdir -d:hdb " . $out_fh->filename . "\n";
    my $pid = open(my $reader, '-|', $^X . " -I $libdir -d:hdb " . $out_fh->filename);
print STDERR "pid $pid\n";
    unless ($pid) {
        die "Couldn't start test process: $!";
    }
    my $line = <$reader>;
print STDERR "got line $line\n";
    my($url) = ($line =~ m{Debugger listening on (http://\S+?:\d+)});
    unless ($url) {
        kill $pid;
        die "Got '$line' from test process, expected 'Debugger listening on http://\\S+?:\\d+'";
    }

    eval "END { kill $pid }";
print STDERR "Returning to caller\n";
    return ($url, $out_fh, $reader);
}

1;
