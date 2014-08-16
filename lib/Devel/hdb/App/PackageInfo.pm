package Devel::hdb::App::PackageInfo;

use strict;
use warnings;

use URI::Escape qw(uri_escape);

use base 'Devel::hdb::App::Base';

__PACKAGE__->add_route('get', qr(/packageinfo/((\w+)(::\w+)*)), \&pkginfo);
__PACKAGE__->add_route('get', qr(/subinfo/((\w+)(::\w+)*)), \&subinfo);

# Get data about the packages and subs within the mentioned package
sub pkginfo {
    my($class, $app, $env, $package) = @_;

    my $stash_exists = do {
        my $stash = "${package}::";
        no strict 'refs';
        scalar(%$stash);
    };

    unless ($stash_exists) {
        return [404,
                [ 'Content-Type' => 'text/html' ],
                [ "Package $package not found" ] ];
    }

    my @sub_packages = map { { name => $_, href => '/packageinfo/' . uri_escape($_) } }
                        _namespaces_in_package($package);
    my @subs =  map { { name => $_, href => '/subinfo/' . uri_escape(join('::', $package, $_)) } }
                grep { $app->subroutine_location("${package}::$_") }
                    @{ _subs_in_package($package) };

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $app->encode_json({ name => $package, packages => \@sub_packages, subroutines => \@subs }) ]
        ];
}

# Get information about a subroutine
sub subinfo {
    my($class, $app, $env, $subname) = @_;

    my $loc = $app->subroutine_location($subname);

    if ($loc) {
        my @keys = qw( filename line end source source_line package subroutine );
        my %data;
        @data{@keys} = map { $loc->$_ } @keys;

        return [ 200,
                [ 'Content-Type' => 'application/json' ],
                [ $app->encode_json(\%data) ],
            ];
    } else {
        return [ 404,
                [ 'Content-Type' => 'text/html' ],
                [ "$subname not found" ],
            ];
    }
}

sub _namespaces_in_package {
    my $pkg = shift;

    no strict 'refs';
    return () unless %{"${pkg}::"};

    my @packages =  sort
                    map { substr($_, 0, -2) }  # remove '::' at the end
                    grep { m/::$/ }
                    keys %{"${pkg}::"};
    return @packages;
}

sub _subs_in_package {
    my $pkg = shift;

    no strict 'refs';
    my @subs =  sort
                grep { defined &{"${pkg}::$_"} }
                keys %{"${pkg}::"};
    return \@subs;
}



1;

=pod

=head1 NAME

Devel::hdb::App::PackageInfo - Get information about packages and subroutines

=head2 Routes

=over 4

=item GET /packageinfo/<package>

Get information about the named package, or 'main::' if no package is given.

Returns 200 and a JSON in the body:
  {
    name: String - package name
    packages: [ // list of packages under this package
        {
            name: String - package name
            href: URL (/packageinfo/<That::package::name>)
        },
        ...
    ],
    subroutines: [ // List of subroutine names in this package
        {
            name: String - subroutine name including package
            href: URL (/subinfo/<That::package::subname>)
        },
        ...
    ],
  }

Returns 400 if the named package is not a valid package name
Returns 404 if the named package is not present

=item GET /subinfo/<subname>

Get information about the named subroutine.  If the subname has no package
included, package main:: is assummed.

Returns 200 and a JSON-encoded hash in the body with these keys:

subroutine: String - subroutine name, not including package
    package     => Package the subroutine is in
    filename    => File the sub was defined
    line        => What line the sub is defined
    end         => Last line where the sub is defined
    source      => If the sub was created in an eval, this is the file the
                   eval happened in
    source_line => Line the eval happened in

Returns 404 if the given subroutine was not found.

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

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
