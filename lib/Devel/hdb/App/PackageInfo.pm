package Devel::hdb::App::PackageInfo;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Devel::hdb::Response;
use Devel::hdb::DB::PackageInfo;

__PACKAGE__->add_route('get', qr(/pkginfo/((\w+)(::\w+)*)), \&pkginfo);
__PACKAGE__->add_route('get', qr(/subinfo/((\w+)(::\w+)*)), \&subinfo);

# Get data about the packages and subs within the mentioned package
sub pkginfo {
    my($class, $app, $env, $package) = @_;

    my $resp = Devel::hdb::Response->new('pkginfo', $env);
    my $sub_packages = Devel::hdb::DB::PackageInfo::namespaces_in_package($package);
    my @subs = grep { Devel::hdb::DB::PackageInfo::sub_is_debuggable($package, $_) }
                    @{ Devel::hdb::DB::PackageInfo::subs_in_package($package) };

    $resp->data({ packages => $sub_packages, subs => \@subs });
    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
        ];
}

# Get information about a subroutine
sub subinfo {
    my($class, $app, $env, $subname) = @_;

    my $resp = Devel::hdb::Response->new('subinfo', $env);
    $resp->data( Devel::hdb::DB::PackageInfo::sub_info($subname));
    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
        ];
}

1;

=pod

=head1 NAME

Devel::hdb::App::PackageInfo - Get information about packages and subroutines

=head2 Routes

=over 4

=item /pkginfo/<pacakge>

Returns a JSON-encoded hash with two keys: "packages" containing a list of
namespaces within the requested package, and "subs" containing a list of
debuggable subroutine names in the requested package.  Subroutines are
considered debuggable is there is an entry in %DB::sub for them.

=item /subinfo/<subname>

Given a fully-qualified subroutine name, including package, in the format
Package::SubPackage::subroutine, returns a JSON-encoded hash with these keys:
  file   => Filename this subroutine was defined
  start  => Line number in the file the subroutine starts
  end    => Line in the file the subroutine ends
  source => Original source file of the subroutine text
  source_line => Line in the original source file

source and source_line can differ from file and start in the case of
subroutines defined inside of a string eval.  In this case, "file" will
be a string like
  (eval 23)[/some/file/path/module.pm:123]
representing the text that was eval-ed, and "start" will be the line within
that text where the subroutine was defined.  "source" would be
  /some/file/path/module.pm
showing where in the original source code the text came from, and
"source_line" would be 123, the line in the original source file.

=back


=head1 SEE ALSO

Devel::hdb, Devel::hdb::DB::PackageInfo

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2013, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
