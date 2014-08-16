package Devel::hdb::App::Config;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

__PACKAGE__->add_route('post', qr{/loadconfig/(.+)}, \&loadconfig);
__PACKAGE__->add_route('post', qr{/saveconfig/(.+)}, \&saveconfig);

sub loadconfig {
    my($class, $app, $env, $file) = @_;

    my $result = eval { $app->load_settings_from_file($file) };
    if ($@) {
        return [ 400,
                [ 'Content-Type' => 'text/html' ],
                [ $@ ] ];

    } elsif ($result ) {
        return [ 204, [], [] ];
    } else {
        return [ 404,
                [ 'Content-Type' => 'text/html' ],
                [ "File $file not found" ] ];
    }
}

sub saveconfig {
    my($class, $app, $env, $file) = @_;

    $file = eval { $app->save_settings_to_file($file) };
    if ($@) {
        return [ 400,
                [ 'Content-Type' => 'text/html' ],
                [ "Problem loading $file: $@" ] ];
    } else {
        return [ 204, [], [] ];
    }
}

1;

=pod

=head1 NAME

Devel::hdb::App::Config - Load and save debugger configuration

=head2 Routes

=over 4

=item POST /saveconfig/<filename>

Save debugger configuration to the given file.  Breakpoint and
line-actions are saved.

=item POST /loadconfig/<filename>

Loads debugger configuration from the given file.  Breakpoint and
line-actions are restored.

=back


=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
