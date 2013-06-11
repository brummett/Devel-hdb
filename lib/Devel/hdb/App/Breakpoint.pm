package Devel::hdb::App::Breakpoint;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Plack::Request;
use Devel::hdb::Response;
use JSON;

__PACKAGE__->add_route('post', '/breakpoint', \&set_breakpoint);
__PACKAGE__->add_route('get', '/breakpoint', \&get_breakpoint);
__PACKAGE__->add_route('get', '/delete-breakpoint', \&delete_breakpoint);
__PACKAGE__->add_route('get', '/breakpoints', \&get_all_breakpoints);


sub _file_or_line_is_invalid {
    my($class, $app, $filename, $line) = @_;

    if (! $app->is_loaded($filename)) {
        return [ 404, ['Content-Type' => 'text/html'], ["$filename is not loaded"]];
    } elsif (! $app->is_breakable($filename, $line)) {
        return [ 403, ['Content-Type' => 'text/html'], ["line $line of $filename is not breakable"]];
    }
    return;
}

sub set_breakpoint {
    my($class, $app, $env) = @_;

    my $params = Plack::Request->new($env)->parameters;
    my($filename, $line) = @$params{'f','l'};

    if (my $error = $class->_file_or_line_is_invalid($app, $filename, $line)) {
        return $error;
    }

    my $resp = Devel::hdb::Response->new('breakpoint', $env);

    my %req;
    @req{'file','line'} = @$params{'f','l'};
    $req{code} = $params->{c} if (exists $params->{'c'});
    $req{inactive} = $params->{ci} if (exists $params->{'ci'});

    my $resp_data = $class->set_breakpoint_and_respond($app, %req);
    $resp->data( $resp_data );

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
          ];
}

my(%my_breakpoints);

sub delete_breakpoint {
    my($class, $app, $env) = @_;

    my $params = Plack::Request->new($env)->parameters;
    my($file, $line) = @$params{'f','l'};

    if (my $error = $class->_file_or_line_is_invalid($app, $file, $line)) {
        return $error;
    }

    my $bp = $my_breakpoints{$file}->{$line};
    unless ($bp) {
        return [ 404,
                    ['Content-Type' => 'text/html'],
                    ["No breakpoint on line $line of $file"]];
    }
    $app->remove_break($bp);
    delete $my_breakpoints{$file}->{$line};

    my $resp = Devel::hdb::Response->new('delete-breakpoint', $env);
    $resp->data( { filename => $file, lineno => $line } );
    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
          ];
}

sub set_breakpoint_and_respond {
    my($class, $app, %params) = @_;

    my($file, $line, $code, $inactive) = @params{'file','line','code','inactive'};

    my $set_inactive = exists($params{inactive})
                        ? sub { shift->inactive($inactive) }
                        : sub {};

    my $changer;
    my $is_add;
    if (exists $params{code}) {
        # setting a breakpoint
        $changer = sub {
                my $bp = $app->add_break(%params);
                $set_inactive->($bp);
                $my_breakpoints{$file}->{$line} = $bp;
            };
    } else {
        # changing a breakpoint
        my $bp = $my_breakpoints{$file}->{$line};
        $bp ||= $app->add_break(file => $file, line => $line, code => sub {});
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
    @$resp_data{'condition','condition_inactive'} = ( $bp->code, $bp->inactive );
    return $resp_data;
}


sub get_breakpoint {
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $filename = $req->param('f');
    my $line = $req->param('l');

    my $resp = Devel::hdb::Response->new('breakpoint', $env);
    my($bp) = $app->get_breaks(file => $filename, line => $line);
    my $resp_data = { filename => $filename, lineno => $line };
    if ($bp) {
        $resp_data->{condition} = $bp->code;
        $bp->inactive and do { $resp_data->{condition_inactive} = 1 };
    }
    $resp->data($resp_data);

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

    my @bp;
    foreach my $bp ( $app->get_breaks( file => $filename, line => $line) ) {
        my $this = { type => 'breakpoint' };
        $this->{rid} = 1 if (defined $rid);
        $this->{data} = {   filename => $bp->file,
                            lineno => $bp->line,
                            condition => $bp->code,
                        };
        $this->{data}->{condition_inactive} = 1 if $bp->inactive;
        push @bp, $this;
    }
    return [ 200, ['Content-Type' => 'application/json'],
            [ JSON::encode_json( \@bp ) ]
        ];
}

1;

=pod

=head1 NAME

Devel::hdb::App::Breakpoint - Get and set breakpoints

=head1 DESCRIPTION

Breakpoints are perl code snippets run just before executable statements in
the debugged program.  If the code returns a true value, then the debugger
will stop before that program statement is executed.

These code snippets are run in the context of the debugged program and have
access to any of its variables, lexical included.

Unconditional breakpoints are usually stored as "1".  

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
  condition_inactive => 1 (yes) or undef (no), whether this breakpoint
                        is disabled/inactive

=item POST /breakpoint

Set a breakpoint.  Accepts these parameters:
  f     File name
  l     Line number
  c     Breakpoint condition code.  This can be a bit of Perl code to
        represent a conditional breakpoint, or "1" for an unconditional
        breakpoint.
  ci    Set to true to make the breakpoint condition inactive, false to
        clear the setting.

It responds with the same JSON-encoded hash as GET /breakpoint.  If the
condition is empty/false (to clear the breakpoint) the response will only
include the keys 'filename' and 'lineno'.

=item GET /delete-breakpoint

Delete a breakpoint on a particular file ane line number.  Requires these
parameters:
  f     File name
  l     Line number

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
