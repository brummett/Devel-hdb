package Devel::hdb::TraceFollow;

use strict;
use warnings;

use base 'Devel::Chitin';
use IO::File;

sub new {
    my($class, $file, $cb) = @_;

    my $self = {
                file => $file,
                cb   => $cb,
            };
    bless $self, $class;

    $self->attach();
}

sub init {
    my $self = shift;
    $self->_open_fh();
    $self->trace(1);
}

sub shutdown {
    my $self = shift;
    $self->trace(0);
    $self->detach();
}

BEGIN {
    no strict 'refs';

    # Accessors
    foreach my $acc( qw( file cb fh ) ) {
        *{$acc} = sub {
            my $self = shift;
            if (@_) {
                $self->{$acc} = shift;
            }
            return $self->{$acc};
        };
    }

    # Methods child classes must implement
    foreach my $acc ( qw(_open_fh notify_trace) ) {
        *{$acc} = sub {
            my $self = shift;
            my $type = ref($self);
            die "$type did not implement ${acc}()";
        };
    }
}

sub _line_offset_for_sub {
    my($self, $line, $subroutine) = @_;
    my $loc = $self->subroutine_location($subroutine);

    return $loc
            ? $line - $loc->line
            : undef;
}

sub _line_from_sub_and_offset {
    my($self, $subroutine, $offset) = @_;
    my $loc = $self->subroutine_location($subroutine);

    return $loc
            ? $loc->line + $offset
            : undef;
}

package Devel::hdb::Trace;
use base 'Devel::hdb::TraceFollow';

sub _open_fh {
    my $self = shift;
    my $fh = IO::File->new($self->file, 'w')
                || die "Can't open ".$self->file." for writing trace file: $!";
    $self->fh($fh);
}

sub notify_trace {
    my($self, $location) = @_;

    my $line    = $location->line;
    my $subname = $location->subroutine;
    my $file    = $location->filename;
    my $package = $location->package;

    my $loc_string;
    if (my $offset = $self->_line_offset_for_sub($line, $subname)) {
        $loc_string = "${subname}+${offset}";
    } else {
        $loc_string = "${file}:${line}";
    }
    $package ||= 'main';
    $self->fh->print( join("\t", $loc_string, $package, $file, $line, $subname), "\n");
}

sub notify_program_terminated {
    my $self = shift;
    $self->shutdown();
}


package Devel::hdb::Follow;
use base 'Devel::hdb::TraceFollow';

sub _open_fh {
    my $self = shift;
    my $fh = IO::File->new($self->file, 'r')
                || die "Can't open ".$self->file." for reading trace file: $!";
    $self->fh($fh);
}

sub _next_trace_line {
    my $self = shift;
    return $self->fh->getline();
}

sub notify_trace {
    my($self, $at_location) = @_;

    my $at_line     = $at_location->line;
    my $at_file     = $at_location->filename;
    my $at_subname  = $at_location->subroutine;

    # The expected next location
    chomp(my $next_trace_line = $self->_next_trace_line);
    my($exp_location, $exp_package, $exp_file, $exp_line, $exp_subname) = split("\t", $next_trace_line);

    my $should_stop;
    if (my ($expected_sub, $expected_offset) = $exp_location =~ m/(.*)\+(\d+)$/) {
        my $offset = $self->_line_offset_for_sub($at_line, $at_subname);
        if ($expected_sub ne $at_subname or $expected_offset != $offset) {
            $should_stop = 1;
            $exp_line = $self->_line_from_sub_and_offset($expected_sub, $expected_offset);
        }

    } elsif( my($file, $line) = $exp_location =~ m/(.*):(\d+)$/) {
        $should_stop = ($file ne $at_file or $line != $at_line);

    } else {
        warn "Trace file format unrecognized on line $.. First column does not look like a trace location";
    }

    if ($should_stop) {
        my($package) = $at_subname =~ m/(.*)::(\w+)$/;
        $package ||= 'main';
        my %diff_data = (
                'package'   => $package,
                filename    => $at_file,
                line        => $at_line,
                subroutine  => $at_subname,
                sub_offset  => $self->_line_offset_for_sub($at_line, $at_subname),

                expected_package    => $exp_package,
                expected_filename   => $exp_file,
                expected_line       => $exp_line,
                expected_subroutine => $exp_subname,
                expected_sub_offset => $self->_line_offset_for_sub($exp_line, $exp_subname) || '',
        );

        $self->cb->(\%diff_data);
    }
}


1;
