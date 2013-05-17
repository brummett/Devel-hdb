package Devel::hdb::App::Breakpoint;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Plack::Request;
use Devel::hdb::Response;
use JSON;

__PACKAGE__->add_route('post', '/breakpoint', \&set_breakpoint);
__PACKAGE__->add_route('get', '/breakpoint', \&get_breakpoint);
__PACKAGE__->add_route('get', '/breakpoints', \&get_all_breakpoints);

sub set_breakpoint {
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $filename = $req->param('f');
    my $line = $req->param('l');
    my $condition = $req->param('c');
    my $condition_inactive = $req->param('ci');
    my $action = $req->param('a');
    my $action_inactive = $req->param('ai');

    if (! DB->is_loaded($filename)) {
        return [ 404, ['Content-Type' => 'text/html'], ["$filename is not loaded"]];
    } elsif (! DB->is_breakable($filename, $line)) {
        return [ 403, ['Content-Type' => 'text/html'], ["line $line of $filename is not breakable"]];
    }

    my $resp = Devel::hdb::Response->new('breakpoint', $env);

    my $params = $req->parameters;
    my %req;
    $req{condition} = $condition if (exists $params->{'c'});
    $req{condition_inactive} = $condition_inactive if (exists $params->{'ci'});
    $req{action} = $action if (exists $params->{'a'});
    $req{action_inactive} = $action_inactive if (exists $params->{'ai'});

    my $resp_data = $class->set_breakpoint_and_respond($filename, $line, %req);
    $resp->data( $resp_data );

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
          ];
}

sub set_breakpoint_and_respond {
    my($class, $filename, $line, %params) = @_;

    unless (DB->is_loaded($filename)) {
        DB->postpone_until_loaded(
                $filename,
                sub { DB->set_breakpoint($filename, $line, %params) }
        );
        return;
    }

    DB->set_breakpoint($filename, $line, %params);

    my $resp_data = DB->get_breakpoint($filename, $line);
    unless ($resp_data) {
        # This breakpoint was deleted
        $resp_data = { filename => $filename, lineno => $line };
    }
    return $resp_data;
}


sub get_breakpoint {
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $filename = $req->param('f');
    my $line = $req->param('l');

    my $resp = Devel::hdb::Response->new('breakpoint', $env);
    $resp->data( DB->get_breakpoint($filename, $line) );

    return [ 200, ['Content-Type' => 'application/json'],
            [ $resp->encode() ]
          ];
}

sub get_all_breakpoints {
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $filename = $req->param('f');
    my $line = $req->param('l');
    my $rid = $req->param('rid');

    # Purposefully not using a response object because there's not yet
    # clean way to encode a list of them
    my @bp = map {  { type => 'breakpoint', data => $_, defined($rid) ? (rid => $rid) : () } }
            DB->get_breakpoint($filename, $line);
    return [ 200, ['Content-Type' => 'application/json'],
            [ JSON::encode_json( \@bp ) ]
        ];
}

1;

=pod

=head1 NAME

Devel::hdb::App::Breakpoint - Get and set breakpoints

=head2 Routes

=over 4

=item GET /breakpoint

Get breakpoint information about a particular file and line number.  Accepts
these parameters:
  f     File name
  l     Line number

Returns a JSON-encoded hash with these keys:
  filename  => File name
  lineno    => Line number
  condition => Breakpoint condition, or 1 for an unconditional break
  action    => Debugger action
  condition_inactive => 1 (yes) or undef (no), whether this breakpoint
                        is disabled/inactive
  action_inactive    => 1 (yes) or undef (no), whether this debugger
                        action is disabled/inactive

=item POST /breakpoint

Set a breakpoint.  Accepts these parameters:
  f     File name
  l     Line number
  c     Breakpoint condition.  This can be a bit of Perl code to represent
        a conditional breakpoint, or "1" for an unconditional breakpoint.
  a     Debugger action.  This Perl code will be run whenever execution
        reaches this line.  The action is executed before the program line.
  ci    Set to true to make the breakpoint condition inactive, false to
        clear the setting.
  ai    Set to true to make the debugger action inactive, false to clear
        the setting.

It responds with the same JSON-encoded hash as GET /breakpoint.  If both the
condition and action are empty/false (to clear the breakpoint and action),
the response will only include the keys 'filename' and 'lineno'.

=item GET /breakpoints

Request data about all breakpoints.  Return a JSON-encoded array.  Each
item in the array is a hash with the same information returned by GET
/breakpoint.

=back


=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2013, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
