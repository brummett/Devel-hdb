package Devel::hdb::App::Eval;

use strict;
use warnings;

use Data::Transform::ExplicitMetadata qw(encode);

use base 'Devel::hdb::App::Base';

use Devel::hdb::Utils;

__PACKAGE__->add_route('post', '/eval', \&do_eval);
__PACKAGE__->add_route('get', qr{/getvar/(\d+)/([^/]+)}, \&do_getvar);
__PACKAGE__->add_route('get', qr{/getvar/(\d+)}, \&list_vars_at_level);

# Evaluate some expression in the debugged program's context.
# It works because when string-eval is used, and it's run from
# inside package DB, then magic happens where it's evaluate in
# the first non-DB-package call frame.
# We're setting up a long_call so we can return back from all the
# web-handler code (which are non-DB packages) before actually
# evaluating the string.
sub do_eval {
    my($class, $app, $env) = @_;

    my $body = $class->_read_request_body($env);
    my $params = $app->decode_json($body);
    my $eval_string = Devel::hdb::Utils::_fixup_expr_for_eval($params->{code});

    return _eval_plumbing_closure($app, $env, $eval_string, $params->{wantarray});
}

my %perl_special_vars = map { $_ => 1 }
    qw( $0 $1 $2 $3 $4 $5 $6 $7 $8 $9 $& ${^MATCH} $` ${^PREMATCH} $'
        ${^POSTMATCH} $+ $^N @+ %+ $. $/ $| $\ $" $; $% $= $- @-
        %- $~ $^ $: $^L $^A $? ${^CHILD_ERROR_NATIVE} ${^ENCODING}
        $! %! $^E $@ $$ $< $> $[ $] $^C $^D ${^RE_DEBUG_FLAGS}
        ${^RE_TRIE_MAXBUF} $^F $^H %^H $^I $^M $^O ${^OPEN} $^P $^R
        $^S $^T ${^TAINT} ${^UNICODE} ${^UTF8CACHE} ${^UTF8LOCALE}
        $^V $^W ${^WARNING_BITS} ${^WIN32_SLOPPY_STAT} $^X @ARGV $ARGV
        @F  @ARG ); # @_ );
$perl_special_vars{q{$,}} = 1;
$perl_special_vars{q{$(}} = 1;
$perl_special_vars{q{$)}} = 1;

# Get the value of a variable, possibly in an upper stack frame
sub do_getvar {
    my($class, $app, $env, $level, $varname) = @_;

    if ($perl_special_vars{$varname}) {
        my $wantarray = substr($varname, 0, 1) eq '$' ? 0 : 1;
        return _eval_plumbing_closure($app, $env, $varname, $wantarray);
    }

    my $value = eval { $app->get_var_at_level($varname, $level) };
    my $exception = $@;

    if ($exception) {
        if ($exception =~ m/Can't locate PadWalker/) {
            return [ 501,
                    [ 'Content-Type' => 'text/html'],
                    [ 'Not implemented - PadWalker module is not available'] ];

        } elsif ($exception =~ m/Not nested deeply enough/) {
            return [ 404,
                    [ 'Content-Type' => 'text/html' ],
                    [ 'Stack level not found' ] ];
        } else {
            die $exception
        }
    }

    my $result = Data::Transform::ExplicitMetadata::encode($value);
    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $app->encode_json($result) ]
        ];
}

sub _eval_plumbing_closure {
    my($app, $env, $eval_string, $wantarray) = @_;

    $eval_string = Devel::hdb::Utils::_fixup_expr_for_eval($eval_string);
    return sub {
        my $responder = shift;
        $env->{'psgix.harakiri.commit'} = Plack::Util::TRUE;

        $app->eval(
            $eval_string,
            $wantarray,
            sub {
                my($eval_result, $exception) = @_;

                my $result = Data::Transform::ExplicitMetadata::encode($exception || $eval_result);
                $responder->([ $exception ? 409 : 200,
                                [ 'Content-Type' => 'application/json' ],
                                [ $app->encode_json($result) ]]);
            }
        );
    };
}

1;

=pod

=head1 NAME

Devel::hdb::App::Eval - Evaluate data in the debugged program's context

=head1 DESCRIPTION

Registers routes for evaluating arbitrary Perl code and for inspecting
variables in the debugged program.

=head2 Routes

=over 4

=item POST /eval

Evaluate a string of Perl code in the context of the debugged process.
The code is evaluated in the content of the nearest stack frame that
is not part of the debugger.  The request body must contain a JSON-encoded
hash with these keys:

  code      => String of Perl code to evaluate
  wantarray => 0, 1 or undef; whether to evaluate the code in scalar list
               or void context

Returns 200 if successful and the result in the body.  The body contents
should be decoded using Data::Transform::ExplicitMetadata
Returns 409 if there was an exception.  The body contents should be decoded
using Data::Transform::ExplicitMetadata

=item GET /getvar/<level>

Get a list of all the lexical variables at the given stack level.
Return a JSON-encoded array containing hashes with these keys:

  name => Name of the variable, including the sigil
  href => URL to use to get the value of the variable

Returns 404 if the requested stack level does not exist.

=item GET /getvar/<level>/<varname>

Searches the requested stack frame for the named variable.  0 is the currently
executing stack frame, 1 is the frame above that, etc.  The variable must
include the sigil, and may be a more complicated expression indicating a
portion of a composite value.  For example:
  $scalar           A simple scalar value
  @array            The entire array
  $array[1]         One element of the array
  $hash{key1}       One element of the hash
  @array[1,2]       Array slice
  @hash{key1,key2}  Hash slice
  @array[1 .. 2]    Array slice with a range

Returns 200 and JSON in the body.  The returned JSON is an
encoded version of whatever the Perl code evaluated to, and should
be decoded with Data::Transform::ExplicitMetadata.

=back

=head1 SEE ALSO

Devel::hdb, Padwalker

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
