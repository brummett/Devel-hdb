package Devel::hdb::App::WatchPoint;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Plack::Request;
use Data::Transform::ExplicitMetadata;
use URI::Escape qw(uri_escape);

sub response_url_base() { '/watchpoints' };

__PACKAGE__->add_route('put', qr{/watchpoints/(.+)}, 'set');
__PACKAGE__->add_route('get', qr{/watchpoints/(.+)$}, 'get');
__PACKAGE__->add_route('delete', qr{/watchpoints/(.+)$}, 'delete');
__PACKAGE__->add_route('get', '/watchpoints', 'get_all');

my %watchpoint_exprs;

sub set {
    my($class, $app, $env, $expr) = @_;

    $app->add_watchexpr($expr);
    $watchpoint_exprs{$expr} = undef;

    return [ 201,
            ['Content-Type' => 'application/json'],
            [ '{}' ], # JQuery requires _something_ in the response
          ];
}

sub delete {
    my($class, $app, $env, $expr) = @_;

    my $watchpoint;
    if (exists $watchpoint_exprs{$expr}) {
        $watchpoint = $app->remove_watchexpr($expr);
    }
    
    if ($watchpoint) {
        return [ 204, [], [] ];
    } else {
        return _not_found();
    }
}

sub _not_found {
    my $expr = shift;
    
    return [ 404,
            ['Content-Type' => 'text/html'],
            ["No watchpoint $expr"] ];
}
    

sub get {
    my($class, $app, $env, $expr) = @_;

    if (exists $watchpoint_exprs{$expr}) {
        my $wp_data = $class->_get_one($expr);
        return [ 200,
            ['Content-Type' => 'application/json'],
            [ $app->encode_json($wp_data) ],
          ];
    } else {
        return _not_found();
    }
}

sub _get_one {
    my($class, $expr) = @_;

    return { expr => $expr, href => join('/','/watchpoints', uri_escape($expr)) };
}

sub get_all {
    my($class, $app, $env) = @_;

    my @wp_list = map { $class->_get_one($_) } keys(%watchpoint_exprs);

    return [ 200, ['Content-Type' => 'application/json'],
            [ JSON::encode_json( \@wp_list ) ]
        ];
}

sub Devel::hdb::App::notify_watch_expr {
    my($app, $location, $expr, $old, $new) = @_;

    my %event = ( type => 'watchpoint',
                  expr => $expr,
                  old => Data::Transform::ExplicitMetadata::encode($old),
                  new => Data::Transform::ExplicitMetadata::encode($new),
                );
    @event{qw(subroutine package filename line)} =
        map { $location->$_ } qw(subroutine package filename line);
    $app->enqueue_event(\%event);
    $app->step;
}

1;

=pod

=head1 NAME

Devel::hdb::App::WatchPoint - Get and set watchpoints

=head1 DESCRIPTION

Watchpoints are perl code snippets run just before executable statements in
the debugged program.  If the expression's value changes, then the debugger
will stop before that program statement is executed, and the 'events' list
of the next status report will contain a "watchpoint" event reporting where
the debugged program was immediately before the changed was detected.

The value is considered changed if the value's length changes, or of any of
the values changes when evaluated as strings.  It does not do a deep
comparison of contained values.

These code snippets are run in list context in the context of the debugged
program and have access to any of its variables, lexical included.

=head2 Routes

=over 4

=item GET /watchpoints

Get a list of all the currently set watchpoint expressions.

Returns 200 and a JSON-encoded array containing hashes with these keys:
  expr  => The Perl expression
  href  => A URL you can use to delete it

=item PUT /watchpoints/<expr>

Create a watchpoint.

It responds 201.

=item GET /watchpoints/<expr>

Returns 200 and a JSON-encoded hash with these keys:
  expr  => The Perl expression
  href  => A URL you can use to delete it

Returns 404 if there is no watchpoint with that expression.

=item DELETE /watchpoints/<expr>

Delete the given watchpoint.  Returns 204 if successful.
Returns 404 if there is no watchpoint with that expr.

=back

=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
