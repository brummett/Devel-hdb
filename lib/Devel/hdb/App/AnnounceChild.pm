package Devel::hdb::App::AnnounceChild;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Devel::hdb::Response;

__PACKAGE__->add_route('post', '/announce_child', \&announce_child);

sub announce_child {
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $child_pid = $req->param('pid');
    my $child_uri = $req->param('uri');

    my $resp = Devel::hdb::Response->queue('child_process', $env);
    $resp->{data} = {
            pid => $child_pid,
            uri => $child_uri,
            run => $child_uri . 'continue?nostop=1'
        };

    return [200, [], []];
}


1;

=pod

=head1 NAME

Devel::hdb::App::AnnounceChild - Let the parent process know the URL of a child

=head1 DESCRIPTION

Registers a route to let a child process notify the parent process it is
listening at a particular URL.

=head2 Routes

=over 4

=item POST /announce_child

This route requires two parameters:
  pid   The process ID of the sending process
  url   The URL of the debugger of the sending process

After a child process forks, it should contact the parent process' debugger
at this route to notify the parent what URL it is listening for commands on.
The parent should then pass that information along to the user.

=back

=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
