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
    $self{debug} = delete $params{debug};
    $self{base_url} =~ s{/$}{};

    $self{http_client} = LWP::UserAgent->new();
    $self{http_client}->agent("Devel::hdb::Client/$VERSION");

    return bless \%self, $class;
}

sub stack {
    my $self = shift;

    my $response = $self->_GET('stack');
    _assert_success($response, q(Can't get stack position));
    my $stack = $JSON->decode($response->content);
    foreach my $frame ( @$stack ) {
        $frame->{args} = [ map { Data::Transform::ExplicitMetadata::decode($_) } @{ $frame->{args} } ];
    }
    return $stack;
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
    print @_,"\n";
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
