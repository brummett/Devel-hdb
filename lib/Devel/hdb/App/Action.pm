package Devel::hdb::App::Action;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Plack::Request;
use Devel::hdb::Response;
use JSON;

__PACKAGE__->add_route('post', '/action', \&set_action);
__PACKAGE__->add_route('get', '/action', \&get_action);
__PACKAGE__->add_route('get', '/delete-action', \&delete_action);
__PACKAGE__->add_route('get', '/actions', \&get_all_actions);

sub _file_or_line_is_invalid {
    my($class, $app, $filename, $line) = @_;

    if (! $app->is_loaded($filename)) {
        return [ 404, ['Content-Type' => 'text/html'], ["$filename is not loaded"]];
    } elsif (! $app->is_breakable($filename, $line)) {
        return [ 403, ['Content-Type' => 'text/html'], ["line $line of $filename is not breakable"]];
    }
    return;
}

sub set_action {
    my($class, $app, $env) = @_;

    my $params = Plack::Request->new($env)->parameters;
    my($filename, $line) = @$params{'f','l'};

    if (my $error = $class->_file_or_line_is_invalid($app, $filename, $line)) {
        return $error;
    }

    my $resp = Devel::hdb::Response->new('action', $env);

    my %req;
    @req{'file','line'} = @$params{'f','l'};
    $req{code} = $params->{c} if (exists $params->{'c'});
    $req{inactive} = $params->{ci} if (exists $params->{'ci'});

    my $resp_data = $class->set_action_and_respond($app, %req);
    $resp->data( $resp_data );

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
          ];
}

my(%my_actions);

sub delete_action {
    my($class, $app, $env) = @_;

    my $params = Plack::Request->new($env)->parameters;
    my($file, $line) = @$params{'f','l'};

    if (my $error = $class->_file_or_line_is_invalid($app, $file, $line)) {
        return $error;
    }

    my $bp = $my_actions{$file}->{$line};
    unless ($bp) {
        return [ 404,
                    ['Content-Type' => 'text/html'],
                    ["No action on line $line of $file"]];
    }
    $app->remove_action($bp);
    delete $my_actions{$file}->{$line};

    my $resp = Devel::hdb::Response->new('delete-action', $env);
    $resp->data( { filename => $file, lineno => $line } );
    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
          ];
}

sub set_action_and_respond {
    my($class, $app, %params) = @_;

    my($file, $line, $code, $inactive) = @params{'file','line','code','inactive'};

    my $set_inactive = exists($params{inactive})
                        ? sub { shift->inactive($inactive) }
                        : sub {};

    my $changer;
    my $is_add;
    if (exists $params{code}) {
        # setting an action
        $is_add = 1;
        $changer = sub {
                my $bp = $app->add_action(%params);
                $set_inactive->($bp);
                $my_actions{$file}->{$line} = $bp;
            };
    } else {
        # changing an action
        my $bp = $my_actions{$file}->{$line};
        $bp ||= $app->add_action(file => $file, line => $line, code => sub {});
        $changer = sub { $set_inactive->($bp); $bp };
    }

    unless ($app->is_loaded($file)) {
        $app->postpone(
                $file,
                $changer
        );
        return;
    }

    my $bp = $changer->();
    my $resp_data = { filename => $file, lineno => $line };
    if ($is_add) {
        @$resp_data{'action','action_inactive'} = ( $bp->code, $bp->inactive );
    }
    return $resp_data;
}


sub get_action {
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $filename = $req->param('f');
    my $line = $req->param('l');

    my $resp = Devel::hdb::Response->new('action', $env);
    my($bp) = $app->get_actions(file => $filename, line => $line);
    my $resp_data = { filename => $filename, lineno => $line };
    if ($bp) {
        $resp_data->{action} = $bp->code;
        $bp->inactive and do { $resp_data->{action_inactive} = 1 };
    }
    $resp->data($resp_data);

    return [ 200, ['Content-Type' => 'application/json'],
            [ $resp->encode() ]
          ];
}

sub get_all_actions {
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $filename = $req->param('f');
    my $line = $req->param('l');
    my $rid = $req->param('rid');

    my @bp;
    foreach my $bp ( $app->get_actions( file => $filename, line => $line) ) {
        my $this = { type => 'action' };
        $this->{rid} = 1 if (defined $rid);
        $this->{data} = {   filename => $bp->file,
                            lineno => $bp->line,
                            action => $bp->code,
                        };
        $this->{data}->{action_inactive} = 1 if $bp->inactive;
        push @bp, $this;
    }
    return [ 200, ['Content-Type' => 'application/json'],
            [ JSON::encode_json( \@bp ) ]
        ];
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

Copyright 2013, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
