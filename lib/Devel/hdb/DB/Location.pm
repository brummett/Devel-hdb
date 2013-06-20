package Devel::hdb::DB::Location;

use strict;
use warnings;

use Carp;

sub new {
    my $class = shift;
    my %props = @_;

    my @props = $class->_required_properties;
    foreach my $prop ( @props ) {
        unless (exists $props{$prop}) {
            Carp::croak("$prop is a required property");
        }
    }

    my $self = bless \%props, $class;
    return $self;
}

sub _required_properties {
    #qw( package filename line subroutine opaddr );
    qw( package filename line subroutine );
}

sub current {
    my $class = shift;
    my %props = @_;

    for (my $i = 0; ; $i++) {
        my @caller = caller($i);
        last unless @caller;
        if ($caller[3] eq 'DB::DB') {
            @props{'package','filename','line'} = @caller[0,1,2];
            $props{subroutine} = (caller($i+1))[3];
            last;
        }
    }
    return $class->new(%props);
}

sub _make_accessors {
    my $package = shift;
    my @accessor_names;
    @accessor_names = $package->_required_properties;
    if ($package ne __PACKAGE__) {
        # called as a class method by a subclass
        my %base_class_accessors = map { $_ => 1 } _required_properties();
        @accessor_names = grep { ! $base_class_accessors{$_} } @accessor_names;
    }
 
    foreach my $acc ( @accessor_names ) {
        my $sub = sub { return shift->{$acc} };
        my $subname = "${package}::${acc}";
        no strict 'refs';
        *{$subname} = $sub;
    }
}


BEGIN {
    __PACKAGE__->_make_accessors();
}

1;

__END__

=pod

=head1 NAME

Devel::hdb::DB::Location - A class to represent an executable location

=head1 SYNOPSIS

  my $loc = Devel::hdb::DB::Location->new(
                package     => 'main',
                subroutine  => 'main::foo',
                filename    => '/usr/local/bin/program.pl',
                line        => 10);
  printf("On line %d of %s, subroutine %s\n",
        $loc->line,
        $loc->filename,
        $loc->subroutine);

=head1 DESCRIPTION

This class is used to represent a location in the debugged program.

=head1 METHODS

  Devel::hdb::DB::Location->new(%params)

Construct a new instnce.  The following parameters are accepted.  The values
should be self-explanatory.  All parameters are required.

=over 4

=item package

=item filename

=item line

=item subroutine

=back

Each construction parameter also has a read-only method to retrieve the value.

=head1 SEE ALSO

L<Devel::hdb::DB::Exception>, L<Devel::hdb::DB>

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2013, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
