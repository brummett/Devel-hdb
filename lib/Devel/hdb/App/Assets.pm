package Devel::hdb::App::Assets;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

__PACKAGE__->add_route('get', qr(^/db/(.*)), \&assets);
__PACKAGE__->add_route('get', qr(^/img/(.*)), \&assets);
__PACKAGE__->add_route('get', '/debugger-gui', sub { assets(@_, 'debugger.html') });

sub assets {
    my($class, $app, $env, $file) = @_;

    $file =~ s/\.\.//g;  # Remove ..  They're unnecessary and a security risk
    $file =~ s/^\/debugger-gui//;
    my $file_path = $INC{'Devel/hdb.pm'};
    $file_path =~ s/\.pm$//;
    $file_path .= '/html/'.$file;
    my $fh = IO::File->new($file_path);
    unless ($fh) {
        return [ 404, ['Content-Type' => 'text/html'], ['Not found']];
    }

    my $type;
    if ($file =~ m/\.js$/) {
        $type = 'application/javascript';
    } elsif ($file =~ m/\.html$/) {
        $type = 'text/html';
    } elsif ($file =~ m/\.css$/) {
        $type = 'text/css';
    } else {
        $type = 'text/plain';
    }

    if ($env->{'psgi.streaming'}) {
        return [ 200, ['Content-Type' => $type], $fh];
    } else {
        local $/;
        my $buffer = <$fh>;
        return [ 200, ['Content-Type' => $type], [$buffer]];
    }
}

1;

=pod

=head1 NAME

Devel::hdb::App::Assets - Handler for file assets

=head1 DESCRIPTION

Registers routes for GET request for /db/.* and /img/.* that serve up files
located un the html subdirectory of Devel::hdb.  The GET /debugger-gui route returns the
file debugger.html.

=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
