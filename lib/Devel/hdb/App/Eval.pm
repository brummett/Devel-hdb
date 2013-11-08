package Devel::hdb::App::Eval;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Devel::hdb::Response;
use Devel::hdb::App::EncodePerlData qw(encode_perl_data);

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

    my $req = Plack::Request->new($env);
    my $eval_string = $req->content();

    my $resp = Devel::hdb::Response->new('evalresult', $env);

    my $result_packager = sub {
        my $data = shift;
        $data->{expr} = $eval_string;
        return $data;
    };
    return _eval_plumbing_closure($eval_string,$resp, $env, $result_packager);
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
        return _eval_plumbing_closure($varname, $resp, $env, $result_packager);
    }

    my $adjust = DB->_first_program_frame();
    my $value = eval { DB->get_var_at_level($varname, $level + $adjust - 1) };
    my $exception = $@;

    if ($exception) {
        if ($exception =~ m/Can't locate PadWalker/) {
            $resp->{type} = 'error';
            $resp->data('Not implemented - PadWalker module is not available');

        } elsif ($exception =~ m/Not nested deeply enough/) {
            $resp->data( { expr => $varname, level => $level, result => undef } );
        } else {
            die $exception
        }
    } else {
        $value = encode_perl_data($value);
        $resp->data( { expr => $varname, level => $level, result => $value } );
    }
    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
        ];
}

sub _eval_plumbing_closure {
    my($eval_string, $resp, $env, $result_packager) = @_;

    $DB::eval_string = $eval_string;
    return sub {
        my $responder = shift;
        my $writer = $responder->([ 200, [ 'Content-Type' => 'application/json' ]]);
        $env->{'psgix.harakiri.commit'} = Plack::Util::TRUE;

        DB->long_call(
            DB->prepare_eval(
                $eval_string,
                sub {
                    my $data = shift;
                    $data->{result} = encode_perl_data($data->{result}) if ($data->{result});
                    $data = $result_packager->($data);

                    $resp->data($data);
                    $writer->write($resp->encode());
                    $writer->close();
                }
            )
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

Copyright 2013, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
