package Devel::hdb::App::Breakpoint;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Plack::Request;
use Digest::MD5 qw();
use Time::HiRes qw();

sub response_url_base() { '/breakpoints' };

__PACKAGE__->add_route('post', response_url_base(), 'set');
__PACKAGE__->add_route('get', qr{(/breakpoints/\w+)$}, 'get');
__PACKAGE__->add_route('post', qr{(/breakpoints/\w+)$}, 'change');
__PACKAGE__->add_route('delete', qr{(/breakpoints/\w+)$}, 'delete');
__PACKAGE__->add_route('get', '/breakpoints', 'get_all');

sub actionable_adder() { 'add_break' }
sub actionable_remover() { 'remove_break' }
sub actionable_type() { 'Devel::Chitin::Breakpoint' }

{
    my(%my_breakpoints, %bp_to_id);
    sub storage { \%my_breakpoints; }
    sub lookup_id {
        my($class, $bp) = @_;
        $bp_to_id{$bp};
    }
    sub save_id {
        my($class, $bp, $id) = @_;
        $bp_to_id{$bp} = $id;
    }
    sub forget_id {
        my($class, $bp) = @_;
        delete $bp_to_id{$bp};
    }
}

sub is_file_or_line_invalid {
    my($class, $app, $filename, $line) = @_;

    if (! $app->is_loaded($filename)) {
        return [ 404, ['Content-Type' => 'text/html'], ["$filename is not loaded"]];
    } elsif (! $app->is_breakable($filename, $line)) {
        return [ 403, ['Content-Type' => 'text/html'], ["line $line of $filename is not breakable"]];
    }
    return;
}

sub set {
    my($class, $app, $env) = @_;

    my $body = $class->_read_request_body($env);
    my $params = $app->decode_json( $body );

    if (my $error = $class->is_file_or_line_invalid($app, @$params{'filename','line'})) {
        return $error;
    }

    my $resp_data = $class->set_and_respond($app, $params);

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $app->encode_json($resp_data) ],
          ];
}

sub change {
    my($class, $app, $env, $id) = @_;

    my $body = $class->_read_request_body($env);
    my $params = $app->decode_json( $body );

    foreach my $prop (qw( filename line )) {
        if (exists($params->{$prop})) {
            return [ 403,
                     ['Content-Type' => 'text/html'],
                     ["Cannot change property $prop"] ];
        }
    }

    my $bp = $class->get_stored($id);
    unless ($bp) {
        return [ 404,
                    ['Content-Type' => 'text/html'],
                    ["No breakpoint $id"] ];
    }

    foreach my $prop ( keys %$params ) {
        $bp->$prop( $params->{$prop} );
    }

    my $rv = { href => $id, filename => $bp->file };
    foreach my $prop (qw( line code inactive)) {
        $rv->{$prop} = $bp->$prop;
    }

    return [ 200,
                [ 'Content-Type', 'application/json'],
                [ $app->encode_json($rv) ] ];
}

sub delete {
    my($class, $app, $env, $id) = @_;

    my $bp = $class->get_stored($id);
    unless ($bp) {
        return [ 404,
                    ['Content-Type' => 'text/html'],
                    ["No breakpoint $id"] ];
    }
    my $remover = $class->actionable_remover;
    $app->$remover($bp);
    $class->delete_stored($id);
    $class->forget_id($bp);

    return [ 204,
            [ ],
            [ ],
          ];
}

sub set_and_respond {
    my($class, $app, $params) = @_;

    my($file, $line, $code, $inactive) = @$params{'filename','line','code','inactive'};
    my $href = join('/',
                $class->response_url_base,
                Digest::MD5::md5_hex($file, $line, Time::HiRes::time)
            );

    my $set_inactive = exists($params->{inactive})
                        ? sub { shift->inactive($inactive) }
                        : sub {};

    my $changer;
    my $adder = $class->actionable_adder;
    if (exists $params->{code}) {
        # setting a breakpoint
        $changer = sub {
                $params->{file} = delete $params->{filename};
                my $bp = $app->$adder(%$params);
                $set_inactive->($bp);
                $class->save_id($bp, $href);
                $class->set_stored($href, $bp);
            };
    } else {
        # changing a breakpoint
        my $bp = $class->get_stored($file, $line);
        $bp ||= $app->$adder(file => $file, line => $line, code => '0');
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
    my $resp_data = {   filename => $file,
                        line => $line,
                        code => $bp->code,
                        inactive => $bp->inactive,
                        href => $href,
                    };
    return $resp_data;
}


sub get {
    my($class, $app, $env, $id) = @_;

    my $bp = $class->get_stored($id);
    my %bp_data = ( href => $class->lookup_id($bp) );
    @bp_data{'href','filename','line','code','inactive'}
        = ( $id,
            map { $bp->$_ } qw(file line code inactive) );

    return [ 200,
            ['Content-Type' => 'application/json'],
            [ $app->encode_json(\%bp_data) ],
          ];
}

sub get_all {
    my($class, $app, $env) = @_;
    my $req = Plack::Request->new($env);

    my %filters;
    foreach my $filter ( qw( line code inactive ) ) {
        $filters{$filter} = $req->param($filter) if defined $req->param($filter);
    }

    my @bp_list =
            map { my %bp_data = (href => $class->lookup_id($_));
                    @bp_data{'filename','line','code','inactive'}
                        = @$_{'file','line','code','inactive'};
                    \%bp_data;
                }
            map { $class->actionable_type->get(file => $_, %filters) }
            defined($req->param('filename'))
                ? ($req->param('filename'))
                : $app->loaded_files;

    return [ 200, ['Content-Type' => 'application/json'],
            [ JSON::encode_json( \@bp_list ) ]
        ];
}

sub delete_stored {
    my($class, $id) = @_;
    my $s = $class->storage;
    delete $s->{$id};
}

sub get_stored {
    my($class, $id) = @_;
    my $s = $class->storage;
    return $s->{$id};
}

sub set_stored {
    my($class, $id, $item) = @_;
    my $s = $class->storage;
    $s->{$id} = $item;
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

=item GET /breakpoints

Get breakpoint information about a particular file and line number.  Accepts
these parameters as filters to limit the returned breakpoint data:
  filename  File name
  line      Line number
  code      Perl code string
  inactive  True if the breakpoint is inactive

Returns 200 and a JSON-encoded array containing hashes with these keys:
  filename  => File name
  lineno    => Line number
  code      => Breakpoint condition, or 1 for an unconditional break
  inactive  => 1 (yes) or undef (no), whether this breakpoint
                        is disabled/inactive
  href      => URL string to uniquely identify this breakpoint

=item POST /breakpoints

Create a breakpoint.  Breakpoint details must appear in the body as JSON hash
with these keys:
  filename  File name
  line      Line number
  code      Breakpoint condition code.  This can be a bit of Perl code to
            represent a conditional breakpoint, or "1" for an unconditional
            breakpoint.
  inactive  Set to true to make the breakpoint condition inactive, false to
            clear the setting.

It responds 200 with the same JSON-encoded hash as GET /breakpoints.
Returns 403 if the line is not breakable.
Returns 404 if the filename is not loaded.

=item GET /breakpoints/<id>

Return the same JSON-encoded hash as GET /breakpoints.
Returns 404 if there is no breakpoint with that id.

=item POST /breakpoints/<id>

Change a breakpoint property.  The body contains a JSON hash of which keys to
change, along with their new values.  Returns 200 and the same JSON hash
as GET /breakpoints, including the new values.

Returns 403 if the given property cannot be changed.
Returns 404 if there is no breakpoint with that id.

=item DELETE /breakpoints/<id>

Delete the breakpoint with the given id.  Returns 204 if successful.
Returns 404 if there is no breakpoint with that id.

=back


=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
