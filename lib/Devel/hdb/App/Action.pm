package Devel::hdb::App::Action;

use strict;
use warnings;

use base 'Devel::hdb::App::Breakpoint';

__PACKAGE__->add_route('post', '/action', 'set');
__PACKAGE__->add_route('get', '/action', 'get');
__PACKAGE__->add_route('get', '/delete-action', 'delete');
__PACKAGE__->add_route('get', '/actions', 'get_all');

sub response_type() { 'action' };
sub delete_response_type { 'delete-action' }
sub actionable_getter() { 'get_actions' }
sub actionable_adder() { 'add_action' }
sub actionable_remover() { 'remove_action' }

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

=item GET /action

Get line action information about a particular file and line number.  Accepts
these parameters:
  f     File name
  l     Line number

Returns a JSON-encoded hash with these keys:
  filename  => File name
  lineno    => Line number
  action    => Debugger action
  action_inactive    => 1 (yes) or undef (no), whether this debugger
                        action is disabled/inactive

=item POST /action

Set an action.  Accepts these parameters:
  f     File name
  l     Line number
  c     Debugger action code.  This Perl code will be run whenever execution
        reaches this line.  The action is executed before the program line.
  ci    Set to true to make the action code inactive, false to clear the
        setting.

It responds with the same JSON-encoded hash as GET /action.  If both the
action code is empty/false (to clear the action), the response will only
include the keys 'filename' and 'lineno'.

=item GET /delete-action

Delete an action on a particular file ane line number.  Requires these
parameters:
  f     File name
  l     Line number

=item GET /actions

Request data about all actions.  Return a JSON-encoded array.  Each
item in the array is a hash with the same information returned by GET
/action.

=back


=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
