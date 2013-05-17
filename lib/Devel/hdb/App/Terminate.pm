package Devel::hdb::App::Terminate;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Devel::hdb::Response;

__PACKAGE__->add_route('get', '/exit', \&do_terminate);

# Exit the running program
# Sets up as a long_call so we can send the 'hangup' response
# and then exit()
sub do_terminate {
    my($class, $app, $env) = @_;
    my $json = $app->{json};
    DB->user_requested_exit();
    return sub {
        my $responder = shift;
        my $writer = $responder->([ 200, [ 'Content-Type' => 'application/json' ]]);

        my $resp = Devel::hdb::Response->new('hangup');
        $writer->write($resp->encode);
        $writer->close();
        exit();
    };
}

1;

=pod

=head1 NAME

Devel::hdb::App::Terminate - Terminate the debugged process

=head1 DESCRIPTION

Registers a route for GET /exit that terminates the debugged process, as
well as the HTTP listener.

=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2013, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
