package Devel::hdb::App::Ping;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Devel::hdb::Response;

__PACKAGE__->add_route('get', '/ping', \&ping);

sub ping {
    my($self, $app, $env) = @_;

    my $resp = Devel::hdb::Response->new('ping', $env);
    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
        ];
}
1;

=pod

=head1 NAME

Devel::hdb::App::Ping - Handle a ping response

=head1 DESCRIPTION

Registers a route for GET /ping that just returns 200 OK.

=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
