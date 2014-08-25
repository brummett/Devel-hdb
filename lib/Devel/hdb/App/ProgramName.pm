package Devel::hdb::App::ProgramName;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use URI::Escape;

__PACKAGE__->add_route('get', '/', \&overview);
__PACKAGE__->add_route('get', '/program_name', \&program_name);

BEGIN {
    our $PROGRAM_NAME = $0;
}

sub overview {
    my($class, $app, $env) = @_;

    our $PROGRAM_NAME;

    my %data = (
        program_name => $PROGRAM_NAME,
        perl_version => sprintf("v%vd", $^V),
        source => join('/', '/source', URI::Escape::uri_escape($PROGRAM_NAME)),
        loaded_files => '/source',
        stack => '/stack',
        breakpoints => '/breakpoints',
        watchpoints => '/watchpoints',
        actions => '/actions',
        stepin => '/stepin',
        stepover => '/stepover',
        stepout => '/stepout',
        continue => '/continue',
        eval => '/eval',
        getvar => '/getvar',
        packageinfo => '/packageinfo',
        subinfo => '/subinfo',
        exit => '/exit',
        debugger_gui => '/debugger-gui',
        status => '/status',
        loadconfig => '/loadconfig',
        saveconfig => '/saveconfig',
    );

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $app->encode_json(\%data) ]
        ];
}

sub program_name {
    my($class, $app, $env) = @_;

    our $PROGRAM_NAME;

    return [200, ['Content-Type' => 'text/plain'],
                [ $app->encode_json({ program_name => $PROGRAM_NAME }) ],
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

=item GET /program_name

Returns 200 and a JSON-encoded hash with one key:
  program_name => $0 when the program was started

=back

=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
