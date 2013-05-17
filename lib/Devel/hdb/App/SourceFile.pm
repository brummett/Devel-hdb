package Devel::hdb::App::SourceFile;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

__PACKAGE__->add_route('get', '/sourcefile', \&sourcefile);

# send back a list.  Each list elt is a list of 2 elements:
# 0: the line of code
# 1: whether that line is breakable
sub sourcefile {
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $resp = $app->_resp('sourcefile', $env);

    my $filename = $req->param('f');
    my $file;
    {
        no strict 'refs';
        $file = $main::{'_<' . $filename};
    }

    my @rv;
    if ($file) {
        no warnings 'uninitialized';  # at program termination, the loaded file data can be undef
        #my $offset = $file->[0] =~ m/use\s+Devel::_?hdb;/ ? 1 : 0;
        my $offset = 1;

        for (my $i = $offset; $i < scalar(@$file); $i++) {
            no warnings 'numeric';  # eval-ed "sources" generate "not-numeric" warnings
            push @rv, [ $file->[$i], $file->[$i] + 0 ];
        }
    }

    $resp->data({ filename => $filename, lines => \@rv});

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
        ];
}


1;

=pod

=head1 NAME

Devel::hdb::App::Control - Control execution of the debugged program

=head1 DESCRIPTION

=head2 Routes

=over 4

=item /stepin

Causes the debugger to execute the current statement and pause before the
next.  If the current statement involves a function call, execution stops
at the first line inside the called function.

=item /stepover

Causes the debugger to execute the current statement and pause before the
next.  If the current statement involves function calls, these functions
are run to completion and execution stops before the next statement at
the current stack level.  If execution of these functions leaves the current
stack frame, usually from an exception caught at a higher frame or a goto,
execution pauses at the first staement following the unwinding.

=item /steoput

Causes the debugger to start running continuously until the current stack
frame exits.

=item /continue

Causes the debugger to start running continuously until it encounters another
breakpoint.  /continue accepts one optional argument C<nostop>; if true, the
debugger gets out of the way of the debugged process and will not stop for
any reason.

=back

=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2013, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
