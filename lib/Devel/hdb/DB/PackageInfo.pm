package Devel::hdb::DB::PackageInfo;

use strict;
use warnings;

# Get information about packages and subroutines within the given package

sub namespaces_in_package {
    my $pkg = shift;

    no strict 'refs';
    return undef unless %{"${pkg}::"};

    my @packages =  sort
                    map { substr($_, 0, -2) }  # remove '::' at the end
                    grep { m/::$/ }
                    keys %{"${pkg}::"};
    return \@packages;
    
}

sub subs_in_package {
    my $pkg = shift;

    no strict 'refs';
    my @subs =  sort
                grep { defined &{"${pkg}::$_"} }
                keys %{"${pkg}::"};
    return \@subs;
}

sub sub_is_debuggable {
    my($pkg, $sub) = @_;
    no strict 'refs';
    return !! $DB::sub{"${pkg}::${sub}"};
}

sub sub_info {
    my $fqn = shift;

    my $loc = $DB::sub{$fqn};
    unless ($loc) {
        warn "No subroutine info found for $fqn\n";
        return {};
    }
    my($file, $start, $end) = $loc =~ m/(.*):(\d+)-(\d+)$/;
    my($source, $source_line) = $file =~ m/\[(.*):(\d+)/;
    return {
            file => $file,
            start => $start,
            end => $end,
            source => $source || $file,
            source_line => $source_line || $start
        };
}

1;

=pod

=head1 NAME

Devel::hdb::DB::PackageInfo - Get information about packages and subroutines

=head1 SYNOPSIS

  my $pkg_list = namespaces_in_package('Foo');

  my $sub_list = subs_in_pacakge('Foo');

=head2 Functions

=over 4

=item namespaces_in_package($package_name)

Returns a listref of all the namespace names under the given package.  If
package Foo::Bar is loaded, then the namespaces under package "main" is "Foo",
and the namespaces under "Foo" is "Bar".

=item subs_in_package($package_name)

Returns a listref of function names under the given package.

=item sub_info($sub_name)

Given a subroutine name (including package), returns a hashref of information
about where the subroutine was declared:
  file        Filename
  start       Line where the subroutine starts
  end         Line where the subroutine ends
  source      Original source file of the subroutine text
  source_line Line in the original source file

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

L<Devel::hdb>

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2013, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.

