package Devel::hdb::Client;

use strict;
use warnings;

use LWP::UserAgent;
use JSON;
use Carp;
use Data::Dumper;
use URI::Escape qw();
use Data::Transform::ExplicitMetadata '0.02';
use Scalar::Util qw(reftype);

use Devel::hdb::Utils;

our $VERSION = "1.0";

use Exception::Class (
        'Devel::hdb::Client::Exception',
        'Devel::hdb::Client::RequiredParameterMissing' => {
            isa => 'Devel::hdb::Client::Exception',
            description => 'Required parameter missing',
            fields => ['params'],
        },
        'Devel::hdb::Client::Exception::HTTP' => {
            isa => 'Devel::hdb::Client::Exception',
            fields => [qw( http_code http_message http_content )],
        },
        'Devel::hdb::Client::Exception::Eval' => {
            isa => 'Devel::hdb::Client::Exception',
        },
        'Devel::hdb::Client::Exception::Error' => {
            isa => 'Devel::hdb::Client::Exception',
        },
);

my $JSON ||= JSON->new->utf8->allow_nonref();

sub new {
    my $class = shift;
    my %params = @_;

    my %self;
    $self{base_url} = delete $params{url};
    unless ($self{base_url}) {
        Devel::hdb::Client::RequiredParameterMissing->throw(params => ['url']);
    }

    $self{debug} = delete $params{debug};
    $self{base_url} =~ s{/$}{};

    $self{http_client} = LWP::UserAgent->new();
    $self{http_client}->agent("Devel::hdb::Client/$VERSION");

    return bless \%self, $class;
}

sub stack {
    my($self, %params) = @_;

    my $url = 'stack';
    if ($params{exclude_sub_params}) {
        $url .= '?exclude_sub_params=1';
    }

    my $response = $self->_GET($url);
    _assert_success($response, q(Can't get stack position));
    my $stack = $JSON->decode($response->content);
    foreach my $frame ( @$stack ) {
        $frame->{args} = _decode_stack_frame_args($frame->{args});
    }
    return $stack;
}

sub stack_depth {
    my $self = shift;

    my $response = $self->_HEAD('stack');
    _assert_success($response, q(Can't get stack depth));
    return $response->header('X-Stack-Depth');
}


sub stack_frame {
    my($self, $level, %params) = @_;

    my $url = join('/', 'stack', $level);
    if ($params{exclude_sub_params}) {
        $url .= '?exclude_sub_params=1';
    }

    my $response = $self->_GET($url);
    _assert_success($response, q(Can't get stack frame));
    my $frame = $JSON->decode($response->content);
    $frame->{args} = _decode_stack_frame_args($frame->{args});

    return $frame;
}

sub _decode_stack_frame_args {
    my $args = shift;
    return unless $args;
    [ map { Data::Transform::ExplicitMetadata::decode($_) } @{$args} ];
}

sub stack_frame_signature {
    my($self, $level) = @_;

    my $response = $self->_HEAD(join('/', 'stack', $level));
    _assert_success($response, q(Can't get stack frame));

    return ( $response->header('X-Stack-Serial'),
             $response->header('X-Stack-Line') );
}


sub _gui_url { 'debugger-gui' }

sub gui {
    my $self = shift;

    my $response = $self->_GET( _gui_url );
    _assert_success($response, q(Can't get debugger gui'));
    return $response->content;
}

sub stepin {
    my $self = shift;

    my $response = $self->_POST('stepin');
    _assert_success($response, q(Can't stepin));
    return $JSON->decode($response->content);
}

sub stepover {
    my $self = shift;

    my $response = $self->_POST('stepover');
    _assert_success($response, q(Can't stepover));
    return $JSON->decode($response->content);
}

sub stepout {
    my $self = shift;

    my $response = $self->_POST('stepout');
    _assert_success($response, q(Can't stepover));
    return $JSON->decode($response->content);
}

sub continue {
    my $self = shift;
    my $nostop = shift;

    my $url = 'continue';
    if ($nostop) {
        $url .= '?nostop=1';
    }

    my $response = $self->_POST($url);
    _assert_success($response, q(Can't continue'));
    return $nostop
                ? 1
                : $JSON->decode($response->content);
}

sub status {
    my $self = shift;

    my $response = $self->_GET('status');
    _assert_success($response, q(Can't get status));
    return $JSON->decode($response->content);
}

sub overview {
    my $self = shift;

    my $response = $self->_GET('');
    _assert_success($response, q(Can't get status));
    return $JSON->decode($response->content);
}

sub  _create_breakpoint_action_sub {
    my($type, $required_params, $default_params) = @_;

    # create_breakpoint() and create_action()
    return sub {
        my $self = shift;
        my %params = @_;

        _verify_required_params_exist(\%params, $required_params);
        _fill_in_default_params(\%params, $default_params);

        my $response = $self->_POST("${type}s", \%params);
        _assert_success($response, "Can't create $type");

        my $bp = $JSON->decode($response->content);
        return $bp->{href};
    };
}

my $create_breakpoint = "create_breakpoint";
my $create_action = "create_action";
{
    no strict 'refs';
    *$create_breakpoint = _create_breakpoint_action_sub(
                                'breakpoint',
                                [qw( filename line )],
                                { code => 1, inactive => 0 } );
    *$create_action = _create_breakpoint_action_sub(
                                'action',
                                [qw( filename line code )],
                                { inactive => 0 } );
}

foreach my $type ( qw(breakpoint action) ) {
    # change_breakpoint() and change_action()
    my $change = sub {
        my($self, $bp, %params) = @_;

        my $response = $self->_POST($bp, \%params);
        _assert_success($response, "Can't change $type");
        return $JSON->decode($response->content);
    };

    # delete_breakpoint() and delete_action()
    my $delete = sub {
        my($self, $href) = @_;

        my $response = $self->_DELETE($href);
        _assert_success($response, "Can't delete $type");
        return 1;
    };

    # get_breakpoint() and get_action()
    my $get_one = sub {
        my($self, $href) = @_;

        my $response = $self->_GET($href);
        _assert_success($response, "Can't get $type");

        my $bp = $JSON->decode($response->content);
        return $bp;
    };

    my $get_multiple = do {
        my @recognized_params = qw(filename line code inactive);

        # get_breakpoints() and get_actions()
        sub {
            my $self = shift;
            my %filters = @_;

            _verify_recognized_params(\%filters, \@recognized_params);

            my $url = "${type}s";
            my $query_string = _encode_query_string_for_hash(%filters);
            $url .= '?' . $query_string if length($query_string);
            my $response = $self->_GET($url);
            _assert_success($response, "Can't get $type");

            return $JSON->decode($response->content);
        };
    };

    my $change_subname = "change_$type";
    my $delete_subname = "delete_$type";
    my $get_one_subname = "get_$type";
    my $get_multiple_subname = "get_${type}s";

    no strict 'refs';
    *$change_subname = $change;
    *$delete_subname = $delete;
    *$get_one_subname = $get_one;
    *$get_multiple_subname = $get_multiple;
}

sub loaded_files {
    my $self = shift;

    my $response = $self->_GET('source');
    _assert_success($response, q(Can't get loaded files));

    return $JSON->decode($response->content);
}

sub file_source_and_breakable {
    my($self, $filename) = @_;

    my $escaped_filename = URI::Escape::uri_escape($filename);
    my $response = $self->_GET(join('/', 'source', $escaped_filename));
    _assert_success($response, "Can't get source for $filename");

    return $JSON->decode($response->content);
}

sub eval {
    my($self, $eval_string) = @_;

    my $string_was_fixed_up = $eval_string ne Devel::hdb::Utils::_fixup_expr_for_eval($eval_string);

    my %params = ( 'wantarray' => wantarray, code => $eval_string );
    my $response = $self->_POST('eval', \%params);

    my $result = Data::Transform::ExplicitMetadata::decode($JSON->decode($response->content));

    if ($response->code == 409) {
        Devel::hdb::Client::Exception::Eval->throw(
            error => $result
        );
    }
    _assert_success($response, q(eval failed));

    return _return_eval_data($result, $string_was_fixed_up);
}

sub _return_eval_data {
    my($result, $string_was_fixed_up) = @_;

    my $reftype = reftype($result);

    if (wantarray and $reftype and $reftype ne 'ARRAY') {
        Devel::hdb::Exception::Error->throw(
            error => "Expected ARRAY ref but got $reftype"
        );
    }

    return _return_unfixed_value_from_eval($string_was_fixed_up, $result);
}

sub _return_unfixed_value_from_eval {
    my $was_fixed_up = shift;
    my $val = shift;

    no warnings 'uninitialized';

    if ($was_fixed_up) {
        if (wantarray and reftype($val->[0]) eq 'HASH') {
            return %{ $val->[0] };
        } elsif (reftype($val) eq 'GLOB') {
            return *$val;
        }
    }

    if (wantarray) {
        return @$val;
    } else {
        return $val;
    }
}

sub list_vars_at_level {
    my($self, $level) = @_;

}

sub get_var_at_level {
    my($self, $varname, $level) = @_;

    my $string_was_fixed_up = $varname ne Devel::hdb::Utils::_fixup_expr_for_eval($varname);

    my $escaped_varname = URI::Escape::uri_escape($varname);
    my $response = $self->_GET(join('/', 'getvar', $level, $escaped_varname));
    _assert_success($response, "Can't get $varname at level $level");

    return Data::Transform::ExplicitMetadata::decode($JSON->decode($response->content));
}

sub load_config {
    my($self, $filename) = @_;

    my $escaped_filename = URI::Escape::uri_escape($filename);
    my $response = $self->_POST(join('/', 'loadconfig', $escaped_filename));
    _assert_success($response, "Loading config from $filename failed: " . $response->content);

    return 1;
}

sub save_config {
    my($self, $filename) = @_;

    my $escaped_filename = URI::Escape::uri_escape($filename);
    my $response = $self->_POST(join('/', 'saveconfig', $escaped_filename));
    _assert_success($response, "Save config to $filename failed: " . $response->content);

    return 1;
}

sub exit {
    my $self = shift;

    my $response = $self->_POST('exit');
    _assert_success($response, q(Can't exit));

    return 1;
}

sub package_info {
    my($self, $package) = @_;

    my $escaped_pkg = URI::Escape::uri_escape($package);
    my $response = $self->_GET(join('/', 'packageinfo', $escaped_pkg));
    _assert_success($response, "Cannot get info for package $package");

    return $JSON->decode($response->content);
}

sub sub_info {
    my($self, $subname) = @_;

    my $escaped_subname = URI::Escape::uri_escape($subname);
    my $response = $self->_GET(join('/', 'subinfo', $escaped_subname));
    _assert_success($response, "Cannot get info for subroutine $subname");

    return $JSON->decode($response->content);
}

sub _encode_query_string_for_hash {
    my @params;
    for(my $i = 0; $i < @_; $i += 2) {
        push @params,
             join('=', map { URI::Escape::uri_escape($_) } @_[$i, $i+1]);
    }
    return join('&', @params);
}

sub _verify_required_params_exist {
    my($param_hash, $required_list) = @_;
    foreach my $required ( @$required_list ) {
        unless (exists $param_hash->{$required}) {
            my $sub_name = (caller())[3];
            Carp::croak("$required is a required param of $sub_name");
        }
    }
    return 1;
}

sub _verify_recognized_params {
    my($param_hash, $recognized_list) = @_;

    my %recognized = map { $_ => 1 } @$recognized_list;

    foreach my $key ( keys %$param_hash ) {
        Carp::croak("Unrecognized param $key") unless exists $recognized{$key};
    }
}

sub _fill_in_default_params {
    my($params_hash, $defaults) = @_;

    foreach my $param_name (keys %$defaults) {
        $params_hash->{$param_name} = $defaults->{$param_name}
            unless (exists $params_hash->{$param_name});
    }
}

sub _base_url { shift->{base_url} }
sub _http_client { shift->{http_client} }

sub _combined_url {
    my $self = shift;
    return join('/', $self->_base_url, @_);
}

sub _http_request {
    my $self = shift;
    my $method = shift;
    my $url_ext = shift;
    my $body = shift;

    my $url = $self->_combined_url($url_ext);
    $self->_dmsg("\nSending $method => $url");

    my $request = HTTP::Request->new($method => $url);

    if (defined $body) {
        $request->content_type('application/json');
        $request->content($JSON->encode($body));
    } else {
        $request->content_type('text/html');
    }

    $self->_dmsg("Request: ",Data::Dumper::Dumper($request));
    my $response = $self->_http_client->request($request);
    $self->_dmsg('Response ', Data::Dumper::Dumper($response));
    return $response;
}

sub _dmsg {
    my $self = shift;
    return unless $self->debug;
    print STDERR @_,"\n";
}

sub _GET {
    my $self = shift;
    $self->_http_request('GET', @_);
}

sub _POST {
    my $self = shift;
    $self->_http_request('POST', @_);
}

sub _HEAD {
    my $self = shift;
    $self->_http_request('HEAD', @_);
}

sub _DELETE {
    my $self = shift;
    $self->_http_request('DELETE', @_);
}

sub _assert_success {
    my $response = shift;
    my $error = shift;
    unless ($response->is_success) {
        Devel::hdb::Client::Exception::HTTP->throw(
                error => $error . ': ' . $response->message,
                http_code => $response->code,
                http_message => $response->message,
                http_content => $response->content,
        );
    }
}

sub debug {
    my $self = shift;
    if (@_) {
        $self->{debug} = shift;
    }
    return $self->{debug};
}

1;

=pod

=head1 NAME

Devel::hdb::Client - Perl bindings for Devel::hdb's REST interface

=head1 DESCRIPTION

Talks to the REST interface of Devel::hdb to control the debugged program.
It uses the same interface the HTML/GUI debugger uses, and has all the same
capabilities.

=head1 SYNOPSIS

  my $client = Devel::hdb::Client->new(url => 'http://localhost:8080');
  my $status = $client->status();
  printf("Stopped in %s at %s:%d\n", @status{'subroutine','filename','line});

  $status = $client->step();

  $client->exit();

=head1 CONSTRUCTOR

  my $client = Devel::hdb::Client->new(url => $url);

Create a new client instance.  C<$url> is the base url the debugger is
listening on.  In particular, it does _not_ include '/debugger-gui'.
new() also accepts the parameter C<debug => 1> to turn on the debugging
flag; when on, it prints messages to STDERR.

=head1 METHODS

All methods will throw an exception if the response from the debugger is not
a successful response.  See L<EXCEPTIONS> below for more info.

=over 4

=item $client->stack();

Perform GET /stack

Return an arrayref of hashrefs.  Each hashref is a caller frame.  It returns
all the same data as L<Devel::Chitin::StackFrame>.  Their keys are the same as
is returned by the caller() built-in:

=over 2

=item filename

=item line

=item package

=item subroutine

=item wantarray

=item hasargs

=item evaltext

=item is_require

=item hints

=item bitmask

=back

and a few derived items

=over 2

=item args

An arrayref of arguments to the function.  See L<PERL VALUES> below.

=item autoload

If this frame is a call to &AUTOLOAD, then this will be the
name this function was called as.

=item evalfile

If this frame is a string eval, this is the file the string eval appears.

=item evalline

If this frame is a string eval, this is the line the string eval appears.

=item subname

The subroutine name without the package name.

=item level

A number indicating how deep this caller frame actually is.

=item serial

A unique identifier for this caller frame.  It will stay the same as long
as this frame is still active.

=back

=item $client->stack_frame($level);

Perform GET /stack/$level

Get a single caller frame.  Returns a hashref representing the requested
frame.  Frames are numbered starting with 0.  Frame 0 is the point the debugged
program is stopped at.  If using this method to scan for frames by repetedly
calling stack_frame() with larger numbers, remember that it will throw an
exception when retrieving a frame that does not exist (eg. getting frame 10
when the stack is only 9 deep).

=item $client->stack_frame_signature($level)

Perform HEAD /stack/$level

Return a 2-element list for the given frame: serial and line.  If a particular
frame's serial number changes, it is a new function call.  If the serial is
the same, but the line changes, then the same function call has moved on to
a different line.

=item $client->gui()

Perform GET /debugger-gui and return a string.

=item $client->status()

Perform GET /status

Return a hashref with short information about the debugged program.  It has
these keys:

=over 2

=item running - Boolean, true if the program has not yet terminated

=item subroutine - Subroutine name the program is stopped in

=item filename - File the program is stopped in

=item line - Line the program is stopped in

=back

Additionally, if there were any asynchronous events since the last status-like
call, there's a key 'events' containing a listref of hashrefs, one for each
event.  See the section L<EVENTS> below.

=item $client->stepin()

Perform POST /stepin

Tell the debugger to step into the next statement, including function calls.
Returns the same hashref as status().

=item $client->stepover()

Perform POST /stepover

Tell the debugger to step over one statement.  If the next statment is a
function call, it stops immediately after that subroutine returns.  Returns
the same hashref as status().

=item $client->stepout()

Perform POST /stepout

Tell the debugger to continue until the current function returns.  The
debugger stops before the next statment after the function call.  Returns
the same hashref as status().

=item $client->continue()

Perform POST /continue

Tell the debugger to continue running the program.  The next time the debugger
stops, the call returns the same hashref as status().

=item $client->exit()

Perform POST /exit

Tell the debugger to exit.  Returns true.

=item $client->create_breakpoint(filename => $file, line => $line, code => $expr, inactive => $bool)

=item $client->create_action(filename => $file, line => $line, code => $expr, inactive => $bool)

Perform POST /breakpoints or POST /actions

Create a breakpoint or action on the given file and line, which are required
arguments.

'code' is a Perl expression to execute before the actual program line.  For
breakpoints, if this expression evaluates to true, the debugger will stop
before executing that line.  It defaults to '1' to create an unconditional
breakpoint.  For actions, the result is ignored, but 'code' is a required
argument.

If 'inactive' is true, the breakpoint/action will be saved, but not actually
evaluated.  Defaults to false.

Returns a scalar value representing the breakpoint/action.

=item $client->get_breakpoint($bp)

=item $client->get_action($bp)

Perform GET /breakpoints/<id> or GET /actions/<id>

Return a hashref containing information about the requested breakpoint/action.
The arg, $bp, is the scalar returned by create_breakpoint() or create_action().
The returned hashref has these keys:

=over 2

=item filename

=item line

=item code

=item inactive

=item href

=back

=item $client->delete_breakpoint($bp)

=item $client->delete_action($bp)

Perform DELETE /breakpoints/<id> or DELETE /actions/<id>

Removes the given breakpoint or action.  Returns true.  Throws an exception if
the given breakpoint/action does not exist.

=item $client->change_breakpoint($bp, %changes)

=item $client->change_breakpoint($bp, %changes)

Perform POST /breakpoints/<id> or POST /actions/<id>

Changes parameters for the given breakpoint or action.  The only 'code' and
'inactive' may be changed.

=item $client->get_breakpoints(%filter)

=item $client->get_actions(%filter)

Perform GET /breakpoints or GET /actions with parameters

Find breakpoints or actions matching the given parameters.  The %filter
is a list of key/value pairs describing what you're looking for.  For example:

      $client->get_breakpoints(filename => 'main.pl')

Will return all the breakpoints in the file main.pl.

      $client->get_breakpoints(inactive => 0)

Will return all active breakpoints in the program.

You can filter on filename, line, code or inactive.  If no filters are used,
then it returns all breakpoints or actions.

The return value is a listref of hashrefs.

=item $client->loaded_files()

Perform GET /source

Return a listref of hashrefs, one for each file currently loaded in the
program.  Each hashref has a key 'filename' with the name of the file.

=item $client->file_source_and_breakable()

Perform GET /source/<filename>

Return a listref of 2-element listrefs.  For each 2-elt list, the first
element is a string containing the perl source code for that line.  The
second element is true if that line may contain a breakpoint.

=item $client->eval($expr)

Perform POST /eval

Evaluate an expression in the most recent caller frame of the debugged
program.  The expression is evaluated in the same context as the call to
this method: void, scalar or list.

Returns whatever the expression evaluated to.  See L<PERL VALUES> below.

=item $client->get_var_at_level($varname, $level)

Perform GET /getvar/<level>/<varname>

Get the value of the given variable at the given caller frame depth.  The
variable must contain the sigil.  If the frame does not exist, or the variable
does not exist at that depth, it will throw an exception.

Returns the value of the variable.  See L<PERL VALUES> below.

=item $client->load_config($filename)

Load configuration information from the given filename.

=item $client->save_config($filename)

Save configuration such as breakpoints, to the given filename.

=item $client->package_info($package)

Perform GET /packageinfo/$package

Get information about the given package.  Returns a hashref with these keys

=over 2

=item name

Name of the pckage

=item packages

Listref of hashrefs, one for each package inside this one.  Each hashref has
a 'name' key with the name of the package.

=item subroutines

Listref of hashrefs, one for each subroutine inside this package.  Each hashref has
a 'name' key with the name of the sub.

=back

=item $client->sub_info($sub_name)

Perform GET /subinfo/$sub_name

Return a hashref with information about the named sub.  $sub_name should
include the package, or 'main::' is assummed.

=over 2

=item suboroutine

Subroutine name, not including the package

=item package

Package name

=item filename

File the sub is in

=item line

Line the subroutine is defined

=item end

Last line where the sub is defined

=item source

If the sub was created in a string eval, this is the file the eval happened in

=item source_line

Line the string eval happened at

=back

=back

=head1 EVENTS

The control methods (stepin, stepout, stepover, continue) and status() all
return a data structure that may contain a listref for the key 'events'.
Events are asynchronous events that happened since the last status report.
They all have a 'type' key.  Other keys are type specific.

=head2 fork event

When the debugged program fork()s, this event is generated in the parent
process.

=over 2

=item pid

The processID of the child process

=item href

URL for the debugger in the child process.  You may use this URL to construct
another Devel::hdb::Client.

=item gui_href

URL to bring up the graphical debugger in a browser.

=item href_continue

URL to POST to tell the child to run without stopping.

=back

=head2 exception event

When the program throws an uncaught exception.

=over 2

=item value

The "value" of the exception.  Either the string passed to C<die>, or perhaps
an exception object

=item package

=item filename

=item line

=item subroutine

Location information about where the exception was thrown

=back

=head2 exit event

When the debugged program has finished.  The debugger is still running.

=over 2

=item exit_code

The process exit code

=back

=head2 hangup event

When the debugger has exited and is no longer listening for requests.

=head2 trace_diff event

When execution has differed from the previous run, when run in follow mode.

=over 2

=item filename

=item line

=item package

=item subroutine

=item sub_offset

Where the program is currently stopped.  sub_offset is the line number within
the subroutine.

=item expected_filename

=item expected_line

=item expected_package

=item expected_subroutine

=item expected_sub_offset

Where the debugger expected the program to be.

=back

=head1 PERL VALUES

For methods that return Perl values such as eval(), get_var_at_level(), or the
argument lists in a stack frame, the data is deserialized with
Data::Transform::ExplicitMetadata::decode().  If the variable has special Perl
attributes (such as blessed, tied, filehandle), decode() will try to re-create
that specialness.

=head1 EXCEPTIONS

This class uses Exception classes.  They stringify to something reasonable.

Devel::hdb::Client::RequiredParameterMissing is thrown when a method requires
a parameter that was missing.  The exception's attribute 'params' is a listref
of parameter names that were missing.

Devel::hdb::Client::Exception::Eval is thrown by eval() when the evaluated
code throws an exception.

Devel::hdb::Client::Exception::Error is thrown when data returned from the
debugger is not formatted as expected.

Devel::hdb::Client::Exception::HTTP is thrown when a response is an
unsuccessful response code (4XX, 5XX).  The exception's attributes 
http_code, http_message and http_content store the code, message
and content from the response.

=head1 SEE ALSO

Devel::hdb, Data::Transform::ExplicitMetadata

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
