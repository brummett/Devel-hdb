package Devel::hdb::Response;

use warnings;
use strict;

use JSON;
use Plack::Request;

sub new {
    my($class, $type, $env) = @_;

    my $self = { type => $type };

    if ($env) {
        my $req = Plack::Request->new($env);
        my $rid = $req->param('rid');
        if (defined $rid) {
            $self->{rid} = $rid;
        }
    }
    bless $self, $class;
}

our @queued;
sub queue {
    my $class = shift;

    my $self = $class->new(@_);
    push @queued, $self;
    return $self;
}

sub _make_copy {
    my $self = shift;

    my %copy = map { exists($self->{$_}) ? ($_ => $self->{$_}) : () } keys %$self;
    return \%copy;
}

sub encode {
    my $self = shift;

    my $copy = $self->_make_copy();

    my $retval = '';
    if (@queued) {
        foreach ( @queued ) {
            $_ = $_->_make_copy();
        }
        unshift @queued, $copy;
        $retval = eval { JSON::encode_json(\@queued) };
        @queued = ();
    } else {
        $retval = eval { JSON::encode_json($copy) };
    }
    return $retval;
}

sub data {
    my $self = shift;
    if (@_) {
        $self->{data} = shift;
    }
    return $self->{data};
}

1;

=pod

=head1 NAME

Devel::hdb::App::Response - Manage responses from the debugger to the user interface

=head1 SYNOPSIS

  my $queued = Devel::hdb::Response->queue('program_name');
  $queued->data('test.pl');

  my $resp = Devel::hdb::Response->new('ping');
  $io->print $resp->encode();

=head1 DESCRIPTION

This class is used to create and enqueue messages to send to the user interface.

=head2 Constructor

=over 4

=item $resp = new($type [, $env])

Creates a new message with the given 'type' field.  $env is an optional PSGI
environment hash.  If given, and the environment has a parameter 'rid', then
its value is copied to the Response instance.

=item $resp = queue($type [, $env])

Creates a new message just as new() does.  The newly created message is added
to the list of queued messages to be included in some future call to L<encode>.

=back

=head2 Methods

=over 4

=item $resp->data($data)

Mutator for getting or setting the 'data' field of the message.  Accepts only
a single scalar, which may be a reference to a more complicated type.

=item $string = $resp->encode();

Returns a JSON-encoded string representing the message.  If there are any
queued messages, the response is an array of all the messages, with the
invocant first in the array.  After the call to encode(), the queued list
is emptied.

=back

=head1 SEE ALSO

Devel::hdb, JSON

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
