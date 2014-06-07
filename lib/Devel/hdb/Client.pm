package Devel::hdb::Client;

use strict;
use warnings;

use LWP::UserAgent;
use JSON;
use Carp;
use Data::Dumper;

our $VERSION = "1.0";

use Exception::Class (
        'Devel::hdb::Client::Exception' => {
            fields => [qw( http_code http_message http_content )],
        },
);

my $JSON ||= JSON->new();

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
    return $JSON->decode($response->content);
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

{
    my @required_params = qw(filename line);
    my %defaults = ( code => 1, inactive => 0 );
    sub create_breakpoint {
        my $self = shift;
        my %params = @_;

        _verify_required_params_exist(\%params, \@required_params);
        _fill_in_default_params(\%params, \%defaults);

        my $response = $self->_POST('breakpoints', \%params);
        _assert_success($response, q(Can't create_breakpoint));

        my $bp = $JSON->decode($response->content);
        $self->_set_breakpoint($bp);
        return $bp->{href};
    }
}

sub delete_breakpoint {
    my($self, $id) = @_;

    my $url = join('/', 'breakpoints', $id);
    my $response = $self->_DELETE($url);
    _assert_success($response, q(Can't delete breakpoint));
    return 1;
}

sub get_breakpoint {
    my($self, $href) = @_;

    my $url = join('/', 'breakpoints', $href);
    my $response = $self->_GET($href);
    _assert_success($response, q(Can't get breakpoint));

    my $bp = $JSON->decode($response->content);
    return $bp;
}

sub get_breakpoint {
    my($self, $id) = @_;
    return $self->{breakpoints}->{$id};
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
        Devel::hdb::Client::Exception->throw(
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
