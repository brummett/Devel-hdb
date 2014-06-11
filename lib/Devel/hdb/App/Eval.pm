package Devel::hdb::App::Eval;

use strict;
use warnings;

use Data::Transform::ExplicitMetadata qw(encode);

use base 'Devel::hdb::App::Base';

use Devel::hdb::Response;

__PACKAGE__->add_route('post', '/eval', \&do_eval);
__PACKAGE__->add_route('post', '/getvar', \&do_getvar);

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
    my $eval_string = _fixup_expr_for_eval($params->{code});

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
    my($class, $app, $env) = @_;

    my $req = Plack::Request->new($env);
    my $level = $req->param('l');
    my $varname = $req->param('v');

    my $resp = Devel::hdb::Response->new('getvar', $env);

    if ($perl_special_vars{$varname}) {
        my $result_packager = sub {
            my $data = shift;
            $data->{expr} = $varname;
            $data->{level} = $level;
            return $data;
        };
        return _eval_plumbing_closure($app, $env, $varname, 1);
    }

    my $value = eval { $app->get_var_at_level($varname, $level) };
    my $exception = $@;

    my $resp_data = { expr => $varname, level => $level };
    if ($exception) {
        if ($exception =~ m/Can't locate PadWalker/) {
            $resp->{type} = 'error';
            $resp->data('Not implemented - PadWalker module is not available');

        } elsif ($exception =~ m/Not nested deeply enough/) {
            $resp_data->{result} = undef;
        } else {
            die $exception
        }
    } else {
        $value = encode($value);
        $resp_data->{result} = $value;
    }
    $resp->data($resp_data);
    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
        ];
}

sub _eval_plumbing_closure {
    my($app, $env, $eval_string, $wantarray) = @_;

    $eval_string = _fixup_expr_for_eval($eval_string);
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

# This substitution is done so that we return HASH, as opposed to a list
# An expression of %hash results in a list of key/value pairs that can't
# be distinguished from a list.  A glob gets replaced by a glob ref.
sub _fixup_expr_for_eval {
    my($expr) = @_;

    $expr =~ s/^\s*(?<!\\)([%*])/\\$1/o;
    return $expr;
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
The Perl code to evaluate is in the body of the POST request.

The code is evaluated in the content of the nearest stack frame that
is not part of the debugger.

=item POST /getvar

This route requires 2 parameters:
  l    Number of stack frames above the current one
  v    Name of the variable, including the sigil

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

=back

=head1 SEE ALSO

Devel::hdb, Padwalker

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
