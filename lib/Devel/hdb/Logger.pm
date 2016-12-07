package Devel::hdb::Logger;

use Exporter 'import';
our @EXPORT_OK = qw(log);

sub log {
    return unless $ENV{HDB_DEBUG_MSG};
    my $subname = (caller(1))[3];
    print STDERR '[', $subname, '] ', @_, "\n";
}

1;
