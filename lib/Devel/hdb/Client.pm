package Devel::hdb::Client;

use strict;
use warnings;

use LWP::UserAgent;
use JSON;

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

sub gui {
    my $self = shift;

    my $response = $self->_GET('debugger-gui');
    _assert_success($response, q(Can't get debugger gui'));
    return $response->content;
}

sub stepin {
    my $self = shift;

    my $response = $self->_POST('stepin');
    _assert_success($response, q(Can't stepin));
    return $response->code == 204;
}

sub _base_url { shift->{base_url} }
sub _http_client { shift->{http_client} }

sub _http_request {
    my $self = shift;
    my $method = shift;
    my $url_ext = shift;
    my $body = shift;

    my $url = join('/', $self->_base_url, $url_ext);
    $self->_dmsg("Sending $method => $url");

    my $request = HTTP::Request->new($method => $url);
    $request->content_type('application/json');

    if (defined $body) {
        $body = $JSON->encode($body) if ref($body);
        $request->content($body);
    }

    my $response = $self->_http_client->request($request);
    $self->_dmsg('Response ' . $response->code . ' ' . $response->message);
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
