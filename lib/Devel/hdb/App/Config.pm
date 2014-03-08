package Devel::hdb::App::Config;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Devel::hdb::Response;

__PACKAGE__->add_route('post', '/loadconfig', \&loadconfig);
__PACKAGE__->add_route('post', '/saveconfig', \&saveconfig);

sub loadconfig {
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $file = $req->param('f');

    my @results = eval { $app->load_settings_from_file($file) };
    my $load_resp = Devel::hdb::Response->new('loadconfig', $env);
    if (! $@) {
        foreach (@results) {
            my $resp = Devel::hdb::Response->queue('breakpoint');
            $resp->data($_);
        }

        $load_resp->data({ success => 1, filename => $file });

    } else {
        $load_resp->data({ failed => $@ });
    }
    return [ 200,
            [ 'Content-Type' => 'application/json'],
            [ $load_resp->encode() ]
        ];
}

sub saveconfig {
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $file = $req->param('f');

    $file = eval { $app->save_settings_to_file($file) };
    my $resp = Devel::hdb::Response->new('saveconfig', $env);
    if ($@) {
        $resp->data({ failed => $@ });
    } else {
        $resp->data({ success => 1, filename => $file });
    }
    return [ 200,
            [ 'Content-Type' => 'application/json'],
            [ $resp->encode() ]
        ];
}

1;

=pod

=head1 NAME

Devel::hdb::App::Config - Load and save debugger configuration

=head2 Routes

=over 4

=item /saveconfig&f=<filename>

Save debugger configuration to the file given with request parameter 'f'.
Breakpoint and line-actions are saved.

=item /loadconfig&f=<filename>

Loads debugger configuration from the file given with request parameter 'f'
Breakpoint and line-actions are restored.

=back


=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
