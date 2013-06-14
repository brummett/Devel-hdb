package Devel::hdb::DB::Stack;

use strict;
use warnings;

our @saved_ARGV;
BEGIN {
    @saved_ARGV = @ARGV;
}

my @caller_values = qw(package filename line subroutine hasargs wantarray
                       evaltext is_require hints bitmask);
sub new {
    my $class = shift;

    my @frames;
    #my $skip = 1;    # Don't include calls within the debugger
    my $next_AUTOLOAD_idx = 0;
    my @prev_loc;

    my $level;
    for($level = 0; ; $level++) {
        my %caller;
        do {
            package DB;
            @caller{@caller_values} = caller($level);
        };
        last unless defined($caller{line});  # no more frames

        {
            my @this = @caller{'filename','line','package'};
            @caller{'filename','line','package'} = @prev_loc;
            @prev_loc = @this;
        }

        if ($caller{subroutine} eq 'DB::DB') {
            # entered the debugger here, start over recording frames
            @frames = ();
            #$skip = 0;
            next;
        }

        #next if $skip;

        $caller{args} = [ @DB::args ];

        # subname is the subroutine without the package part
        $caller{subname} = $caller{subroutine} =~ m/\b(\w+$|__ANON__)/ ? $1 : $caller{subroutine};
        if ($caller{subname} eq 'AUTOLOAD') {
            # needs support in DB::sub for storing the names of AUTOLOADed subs
            my($autoload) = $DB::AUTOLOAD_names[ $next_AUTOLOAD_idx++ ] =~ m/::(\w+)$/;
            $caller{autoload} = $autoload;
        } else {
            $caller{autoload} = undef;
        }

        # if it's a string eval, add info about what file and line the source string
        # came from
        @caller{'evalfile','evalline'} = ($caller{filename} || '')  =~ m/\(eval \d+\)\[(.*?):(\d+)\]/;

        $caller{level} = $level;

        push @frames, Devel::hdb::DB::StackFrame->_new(%caller);
    }

    # fab up a frame for the main program
    push @frames, Devel::hdb::DB::StackFrame->_new(
                    'package'   => 'main',
                    filename    => $prev_loc[0],
                    line        => $prev_loc[1],
                    subroutine  => 'main::MAIN',
                    subname     => 'MAIN',
                    'wantarray' => 0,
                    evaltext    => undef,
                    evalfile    => undef,
                    evalline    => undef,
                    is_require  => undef,
                    hints       => '',   # hints and bitmask here are just the values
                    bitmask     => 256,  # caller() always gives for the top-level caller
                    autoload    => undef,
                    hasargs     => 1,
                    args        => \@saved_ARGV,
                    level       => $level,
                );

    return bless \@frames, $class;
}

sub depth {
    my $self = shift;
    return scalar(@$self);
}

sub iterator {
    my $self = shift;
    my $i = 0;
    return sub {
        return unless $self;

        my $frame = $self->[$i++];
        unless ($frame) {
            undef($self);
        }
        return $frame;
    };
}

sub frame {
    my($self, $i) = @_;
    return ($i < @$self) ? $self->[$i] : ();
}

sub frames {
    my $self = shift;
    return @$self;
}


package Devel::hdb::DB::StackFrame;

sub _new {
    my($class, %params) = @_;
    $params{subname} = 
    return bless \%params, $class;
}

# Accessors
BEGIN {
    no strict 'refs';
    foreach my $acc ( qw(package filename line subroutine hasargs wantarray
                         evaltext is_require hints bitmask
                         subname autoload level evalfile evalline ) ) {
        *{$acc} = sub { return shift->{$acc} };
    }

    *args = sub { my $args = shift->{args}; return @$args };
}

1;

__END__

=pod

=head1 NAME

Devel::hdb::DB::Stack - An object representing the current execution stack

=head1 DESCTIPTION

