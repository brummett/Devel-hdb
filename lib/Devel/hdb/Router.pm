package Devel::hdb::Router;

use strict;
use warnings;

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub get($$&) {
    my($self, $path, $sub) = @_;

    $self->{GET} //= [];
    push @{ $self->{GET}}, [$path, $sub];
}

sub post($$&) {
    my($self, $path, $sub) = @_;

    $self->{POST} //= [];
    push @{ $self->{POST}}, [$path, $sub];
}

sub put($$&) {
    my($self, $path, $sub) = @_;

    $self->{PUT} //= [];
    push @{ $self->{PUT}}, [$path, $sub];
}

sub delete($$&) {
    my($self, $path, $sub) = @_;

    $self->{DELETE} //= [];
    push @{ $self->{DELETE}}, [$path, $sub];
}

sub route($$) {
    my $self = shift;
    my $env = shift;

    return unless exists $self->{$env->{REQUEST_METHOD}};
    my $matchlist = $self->{$env->{REQUEST_METHOD}};

    my($fire, @matches);
    foreach my $route ( @$matchlist ) {
        my($path,$cb) = @$route;

        if (my $ref = ref($path)) {
            if ($ref eq 'Regexp') {
                $fire = 1 if (@matches = $env->{PATH_INFO} =~ $path);
            } elsif ($ref eq 'CODE') {
                $fire = 1 if ($path->($self, $env));
            }
        } elsif ($env->{PATH_INFO} eq $path) {
            $fire = 1;
        }

        if ($fire) {
            return $cb->($env, @matches);
        }
    }
    return [ 404, [ 'Content-Type' => 'text/html'], ['Not found']];
}

1;
