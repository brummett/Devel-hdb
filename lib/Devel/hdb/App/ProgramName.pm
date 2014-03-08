package Devel::hdb::App::ProgramName;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Devel::hdb::Response;

__PACKAGE__->add_route('get', '/program_name', \&program_name);

BEGIN {
    our $PROGRAM_NAME = $0;
}

sub program_name {
    my($class, $app, $env) = @_;

    my $resp = Devel::hdb::Response->new('program_name', $env);

    our $PROGRAM_NAME;
    $resp->data($PROGRAM_NAME);

    return [200, ['Content-Type' => 'text/plain'],
                [ $resp->encode() ]
        ];
}


1;

=pod

=head1 NAME

Devel::hdb::App::ProgramName - Get the name of the running program

=head1 DESCRIPTION

Registers a route used to get the name of the running program, $0

=head2 Routes

=over 4

=item /program_name

Returns the program name as a string

=back

=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
