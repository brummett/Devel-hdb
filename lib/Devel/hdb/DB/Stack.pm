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

=head1 SYNOPSIS

  # Get the stack
  my $stack = Devel::hdb::DB::Stack->new();
  my $depth = $stack->depth();

  # Get one particular stack frame
  my $frame = $stack->frame(3);

  # Iterate through the frames from most recent to oldest
  my $iter = $stack->iterator();
  while ($frame = $iter->()) {
      print "Level "        . $frame->level
          . " stopped in "  . $frame->subname
          . " of package "  . $frame->package . "\n";
  }

=head1 DESCTIPTION

The Stack object represents the current execution stack in the debugged
program.  It encapsulates the information from the C<caller()> function,
but differs from the raw caller data in that the stack frame locations
reflect the currently executing line in each frame.  The difference is
subtle, but tailored for what a debugger is likely interested in.

The Stack object is composed of several L<Devel::hdb::DB::StackFrame>
objects, one for each call frame.

=head1 "TOP" AND "BOTTOM" OF THE STACK

The "top" of the stack refers to the most recent call frame in the debugged
program.  The "bottom" of the stack is the oldest frame, usually the main
program not part of any function call.

For example:

  foo();                # bottom is here, frame 2

  sub foo {
      my @a = bar();    # Frame 1
  }

  sub bar {
      $answer = 1 + 2;  # <-- debugger is stopped here
  }

If the debugger is stopped before executing the indicated line, the top of
the stack would report line 8 in subroutine main::bar in array context.

The call frame for the main program will look like this:
  'hasargs'     1
  subroutine    main::MAIN
  package       main
  args          @ARGV as it looks in a BEGIN block when the program starts
  wantarray     0

=head1 CONSTRUCTOR

  my $stack = Devel::hdb::DB::stack->new();

Returns an instance of Devel::hdb::DB::stack.  The call frames it contains
does not include any stack frames within the debugger.

=head1 METHODS

=over 4

=item $stack->depth()

Returns the number of stack frames in the call stack

=item $stack->frame($i)

Return the $i-th call frame.  0 is the top of the stack.

=item $stack->frames()

Return a list of all the call frames.

=item $stack->iterator()

Returns a coderef to iterate through the call frames.  The top of the stack
will be the first frame returned.  After the bottom frame is returned, the
iterator will return undef.

=back

=head1 StackFrame METHODS

These methods may be called on Devel::hdb::StackFrame instances:

=over 4

=item package

The package this frame is in

=item filename

The filename this frame is in.  For string evals, this will be a string like
"(eval 23)[/some/file/path:125]"

=item line

The line within the file for this frame.

=item subroutine

The full name of the subroutine for this frame.  It will include the pacakge.
For the main program's stack frame, subroutine will be "main::MAIN".

For an eval frame, subroutine will be "(eval)"

=item hasargs

True if this frame has its own instance of @_.  In practice, this will be false
for eval frames, and for subroutines called as C<&subname;>, and true otherwise.

=item wantarray

The C<wantarray> context for this frame.  True if in array context, defined
but false for scalar context, and undef for void context.

=item evaltext

For an eval frame, and it was a string eval, this will be the string that is
eval-ed.  Non-string eval and other frames will have the value undef.

=item is_require

For an eval frame, this will be true if the frame is part of a "require" or
"use".

=item evalfile

For a string eval frame, this is the file name the original string appeared
in.  Other frames have the value undef.

=item evalline

For a string eval frame, this is the line the original string appeared
in.  Other frames have the value undef.

=item hints

The hints value returned be C<caller> for this frame

=item bitmask

The bitmask value returned be C<caller> for this frame

=item subname

The subroutine name without the package name prepended to it.

=item autoload

If this call frame was entered because it was handled by an AUTOLOAD function,
the 'autoload' attribute will be the function name that was actually called.
The value is unreliable if called outside of the debugger system.

=item level

The number indicating how deep this call frame actually is.  This number is
not relative to the program being debugged, and so reflects the real number
of frames between the caller and the bottom of the stack, including any
frames within the debugger.

=back

=head1 SEE ALSO

L<Devel::hdb::DB>, L<Devel::StackTrace>

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2013, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.

