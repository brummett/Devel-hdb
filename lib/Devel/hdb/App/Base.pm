package Devel::hdb::App::Base;

use strict;
use warnings;

sub add_route {
    my($class, $method, $path, $cb) = @_;
    my $app = Devel::hdb::App->get();
    $app->router->$method($path, sub { $class->$cb($app, @_) });
}

sub _read_request_body {
    my($class, $env) = @_;

    my $buff = '';
    my $fh = $env->{'psgi.input'};
    while ($fh->read($buff, 4096, length($buff))) {
        1;
    }

    return $buff;
}


1;

=pod

=head1 NAME

Devel::hdb::App::Base - Base class for Devel::hdb Application route modules

=head1 Methods

=over 4

=item $class->add_route($method, $path, $cb)

Register a route to listen on.  The callback $cb is called as

  $class->$cb( $app, $env, [ @matches ]);

$app is the singleton Devel::hdb::App object. $env is the PSGI environment hash.
If the passed-in $path is a regular expression with captures, then @matches
is the list of captured strings.

=back

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
