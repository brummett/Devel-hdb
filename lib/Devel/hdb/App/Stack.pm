package Devel::hdb::App::Stack;

BEGIN {
    our @saved_ARGV = @ARGV;
}

use strict;
use warnings;
use Plack::Request;

use base 'Devel::hdb::App::Base';

use Exporter 'import';
our @EXPORT_OK = qw(_serialize_stack);

use Data::Transform::ExplicitMetadata qw(encode);

__PACKAGE__->add_route('get', qr{(^/stack$)}, \&stack);
__PACKAGE__->add_route('head', qr{^/stack$}, \&stack_head);
__PACKAGE__->add_route('get', qr{(^/stack)/(\d+)$}, \&stack_frame);
__PACKAGE__->add_route('head', qr{^/stack/(\d+)$}, \&stack_frame_head);

sub stack {
    my($class, $app, $env, $base_url) = @_;

    my $req = Plack::Request->new($env);

    my $frames = $class->_serialize_stack($app, $base_url, $req->param('exclude_sub_params'));
    return [ 200,
            [ 'Content-Type' => 'application/json',
              'X-Stack-Depth' => scalar(@$frames),
            ],
            [ $app->encode_json($frames) ],
        ];
}

sub stack_head {
    my($class, $app, $env) = @_;
    my $stack = $app->stack;
    return [ 200,
            [ 'Content-Type' => 'application/json',
              'X-Stack-Depth' => $stack->depth,
            ],
            [],
        ];
}


sub stack_frame {
    my($class, $app, $env, $base_url, $level) = @_;

    my $req = Plack::Request->new($env);

    my $stack = $app->stack;
    my $frame = $stack->frame($level);

    my $rv = _stack_frame_head_impl($app, $frame);
    if ($rv->[0] == 200) {
        my $serialized_frame = _serialize_frame($frame, $base_url, $level, $req->param('exclude_sub_params'));
        $rv->[2] = [ $app->encode_json($serialized_frame) ];
    }
    return $rv;
}

sub stack_frame_head {
    my($class, $app, $env, $level) = @_;

    my $stack = $app->stack;
    my $frame = $stack->frame($level);
    return _stack_frame_head_impl($app, $frame);
}

sub _stack_frame_head_impl {
    my($app, $frame) = @_;

    unless ($frame) {
        return [ 404,
                [ 'Content-Type' => 'application/json' ],
                [ $app->encode_json( { error => 'Stack frame not found' } ) ],
            ];
    }

    return [ 200,
                [   'Content-Type' => 'application/json',
                    'X-Stack-Serial' => $frame->serial,
                    'X-Stack-Line' => $frame->line,
                ],
                [ ]
            ];
}

sub _serialize_stack {
    my($class, $app, $base_url, $exclude_sub_params) = @_;
    my $frames = $app->stack()->iterator;
    my @stack;
    my $level = 0;
    while (my $frame = $frames->()) {
        push @stack, _serialize_frame($frame, $base_url, $level++, $exclude_sub_params);
    }
    return \@stack;
}

sub _serialize_frame {
    my($frame, $base_url, $level, $exclude_sub_params) = @_;

    my %frame = %$frame; # copy

    if ($frame{autoload}) {
        $frame{subname} .= "($frame{autoload})";
    }

    if ($exclude_sub_params) {
        $frame{args} = undef;
    } elsif ($frame{subroutine} eq '(eval)') {
        $frame{args} = [];
    } else {
        my @encoded_args = map { encode($_) } @{$frame{args}};
        $frame{args} = \@encoded_args;
    }

    $frame{href} = join('/', $base_url, $level++);

    return \%frame;
}

1;

=pod

=head1 NAME

Devel::hdb::App::Stack - Get information about the program stack

=head1 DESCRIPTION

=head2 Routes

=over 4

=item GET /stack

=item GET /stack?exclude_sub_params=1

=item HEAD /stack

Get a list of the current program stack.  Does not include any stack frames
within the debugger.  The currently executing frame is the first element in
the list.  Returns a JSON-encoded array where each item is a hash
with the following keys:
  package       Package/namespace
  subroutine    Fully-qualified subroutine name.  Includes the package
  subname       Subroutine name without the package included
  filename      File where the subroutine was defined
  lineno        Line execution is stopped on
  args          Array of arguments to the subroutine
  wantarray     Context this frame was called in
  serial        Unique serial number for this frame

The header X-Stack-Depth will have the number of frames in the stack.  The
caller may request the HEAD to omit the body/data and just get the headers.

The deepest stack frame is reported as being in the subroutine named 'MAIN'.

Values in the args list are encoded using Data::Transform::ExplicitMetadata

If the param exclude_sub_params is true, then the 'args' value will be undef,
useful to avoid serializing/deserializing possibly deep data structures
passed as arguments to functions.

=item GET /stack/<id>

=item GET /stack/<id>?exclude_sub_params=1

=item HEAD /stack/<id>

Get only one stack frame.  0 is the most recent frame in the debugged program,
1 is the frame before that.  Returns a JSON-encoded hash with the same
information as each stack frame returned by GET /stack.  In addition, the header
X-Stack-Line contains the current frame's line number, and the header
X-Stack-Serial contains the current frame's serial.  Returns a 404 error if
there is no frame as deep as was requested.

=back

=head1 SEE ALSO

Devel::hdb, Data::Transform::ExplicitMetadata

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
