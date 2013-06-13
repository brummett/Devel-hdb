package Devel::hdb::DB::Stack;

our @saved_ARGV;
BEGIN {
    @saved_ARGV = @ARGV;
}

my @caller_values = qw(package filename line subroutine hasargs wantarray
                       evaltext is_require hints bitmask);
sub new {
    my $class = shift;

    my @frames;

    my $discard = 1;  # Don't include calls within the debugger
    my $prev_subname;
    my $next_AUTOLOAD_idx = 0;
    for (my $i = 0; ; $i++) {
        my %caller;
        {
            package DB;
            @caller{@caller_values} = caller($i);
        }
        last unless (defined $caller{line});  # no more frames

        if ($caller{subroutine} eq 'DB::DB') {
            $discard = 0;
        }
        next if $discard;

        # Make a copy of the sub's args
        $caller{args} = [ @DB::args ];

        # subname is the subroutine without the package part
        $caller{subname} = $caller{subroutine} =~ m/\b(\w+$|__ANON__)/ ? $1 : $caller{subroutine};
        if ($caller{subname} eq 'AUTOLOAD') {
            # needs support in DB::sub for storing the names of AUTOLOADed subs
            my($autoload) = $DB::AUTOLOAD_names[ $next_AUTOLOAD_idx++ ] =~ m/::(\w+)$/;
            $caller{autoload} = $autoload;
        }

        $caller{level} = $i;

        # Fixup the frames' subroutines and args, so it becomes a list of stack frames
        # instead of a list of callers
        if (@frames) {
            @{$frames[-1]}{'subroutine','subname','args','autoload'}
                = @caller{'subroutine','subname','args','autoload'};
        }
        push @frames, Devel::hdb::DB::StackFrame->new(%caller);
    }

    # Add info about the main program frame
    @{$frames[-1]}{'subroutine','subname','args','autoload'} = ('MAIN','MAIN', \@saved_ARGV, '');

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
    return $self->[$i];
}


package Devel::hdb::DB::StackFrame;

sub new {
    my($class, %params) = @_;
    $params{subname} = 
    return bless \%params, $class;
}

# Accessors
BEGIN {
    no strict 'refs';
    foreach my $acc ( qw(package filename line subroutine hasargs wantarray
                         evaltext is_require hints bitmask
                         subname autoload level ) ) {
        *{$acc} = sub { return shift->{$acc} };
    }

    *args = sub { my $args = shift->{args}; return @$args };
}

1;
