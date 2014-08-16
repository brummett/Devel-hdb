package Devel::hdb::App::SourceFile;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use URI::Escape;

__PACKAGE__->add_route('get', qr{/source/(.+)}, \&sourcefile);
__PACKAGE__->add_route('get', qr{(/source)}, \&loaded_files);

# send back a list.  Each list elt is a list of 2 elements:
# 0: the line of code
# 1: whether that line is breakable
sub sourcefile {
    my($class, $app, $env, $filename) = @_;

    $filename = URI::Escape::uri_unescape($filename);

    my @rv;
    if (my $file = $app->file_source($filename)) {
        no warnings 'uninitialized';  # at program termination, the loaded file data can be undef
        no warnings 'numeric';        # eval-ed "sources" generate "not-numeric" warnings
        @rv = map { [ $_, $_ + 0 ] } @$file;
        shift @rv;  # Get rid of the 0th element

        return [ 200,
                [ 'Content-Type' => 'application/json' ],
                [ $app->encode_json(\@rv) ]
            ];
    } else {
        return [ 404,
                [ 'Content-Type' => 'text/html'],
                [ 'File not found' ] ];
    }
}

sub loaded_files {
    my($class, $app, $env, $base_href) = @_;

    my @files = map { { filename => $_,
                        href => join('/', $base_href, URI::Escape::uri_escape($_)) } }
                $app->loaded_files();
    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $app->encode_json(\@files) ]
        ];
}


1;

=pod

=head1 NAME

Devel::hdb::App::SourceFile - Get Perl source for the running program

=head1 DESCRIPTION

Registers routes for getting the Perl source code for files used by the
debugged program.

=head2 Routes

=over 4

=item GET /source

Get a list of all the source code files loaded by the application.
This list also contains the files used by the debugger, and the file-like
entities for "eval"ed strings.

Returns 200 an a JSON-encoded array containing hashes with these keys:
  filename => Pathname of the file
  href     => URL to get the source code information for this file

=item GET /source/<filename>

Get source code information for the given file.  It returns a JSON-encoded
array of arrays.  The first-level array has one element for each line in
the file.  The second-level elements each have 2 elements.  The first is
the Perl source for that line in the file.  The second element is 0 if the
line is not breakable, and true if it is.

=back

=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
