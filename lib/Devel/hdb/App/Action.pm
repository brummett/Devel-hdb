package Devel::hdb::App::Action;

use strict;
use warnings;

use base 'Devel::hdb::App::Breakpoint';

sub response_url_base() { '/actions' }

__PACKAGE__->add_route('post', response_url_base(), 'set');
__PACKAGE__->add_route('get', qr{(/actions/\w+)$}, 'get');
__PACKAGE__->add_route('post', qr{(/actions/\w+)$}, 'change');
__PACKAGE__->add_route('delete', qr{(/actions/\w+)$}, 'delete');
__PACKAGE__->add_route('get', '/actions', 'get_all');

sub actionable_adder() { 'add_action' }
sub actionable_remover() { 'remove_action' }
sub actionable_type() { 'Devel::Chitin::Action' }

{
    my(%my_actions);
    sub storage { \%my_actions; }
}

1;

=pod

=head1 NAME

Devel::hdb::App::Action - Get and set line actions

=head1 DESCRIPTION

Line actions are perl code snippets run just before executable statements in
the debugged program.  The return value is ignored.  These code snippets are
run in the context of the debugged program, and can change the program's
state, including lexical variables.

=head2 Routes

=over 4

=item GET /actions

Get action information about a particular file and line number.  Accepts
these parameters as filters to limit the returned breakpoint data:
  filename  File name
  line      Line number
  code      Perl code string
  inactive  True if the breakpoint is inactive

Returns 200 and a JSON-encoded array containing hashes with these keys:
  filename  => File name
  lineno    => Line number
  code      => Code to execute for this action
  inactive  => 1 (yes) or undef (no), whether this action
                        is disabled/inactive
  href      => URL string to uniquely identify this action

=item POST /actions

Create an action.  Action details must appear in the body as JSON hash
with these keys:
  filename  File name
  line      Line number
  code      Action code to run before this line executes.
  inactive  Set to true to make the action inactive, false to
            clear the setting.

It responds 200 with the same JSON-encoded hash as GET /actions.
Returns 403 if the line is not breakable.
Returns 404 if the filename is not loaded.

=item GET /actions/<id>

Return the same JSON-encoded hash as GET /breakpoints.
Returns 404 if there is no breakpoint with that id.

=item POST /actions/<id>

Change an action property.  The body contains a JSON hash of which keys to
change, along with their new values.  Returns 200 and the same JSON hash
as GET /actions, including the new values.

Returns 403 if the given property cannot be changed.
Returns 404 if there is no action with that id.

=item DELETE /actions/<id>

Delete the action with the given id.  Returns 204 if successful.
Returns 404 if there is no action with that id.

=back


=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
