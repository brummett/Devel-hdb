package Devel::hdb::Router;

use strict;
use warnings;

sub new {
    my $class = shift;
    return bless {}, $class;
}

foreach my $method ( qw(get post put delete head) ) {
    my $key = uc($method);
    my $sub = qq(
        sub {
            my(\$self, \$path, \$sub) = \@_;
            my \$list = \$self->{$key} ||= [];
            #print STDERR "Registering route for \$key \$path\\n";
            push \@\$list, [ \$path, \$sub ];
        };
    );
    $sub =~ s/#// if $ENV{HDB_DEBUG_MSG};
    no strict 'refs';
    *$method = eval $sub;
}

sub route($$) {
    my $self = shift;
    my $env = shift;

    my $req_method = $env->{REQUEST_METHOD};
    print STDERR "Incoming request: $req_method ",$env->{PATH_INFO},"\n" if ($ENV{HDB_DEBUG_MSG});
    return unless exists $self->{$req_method};
    my $matchlist = $self->{$req_method};

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
            print STDERR "  matched!\n" if ($ENV{HDB_DEBUG_MSG});
            my $rv = $cb->($env, @matches);
            my $hooks = $self->{after_hooks}->{$req_method}->{$path};
            if ($hooks && @$hooks) {
                $_->($rv, $env, @matches) foreach @$hooks;
            }
            return $rv;
        }
    }
    print STDERR "  no matching route\n" if ($ENV{HDB_DEBUG_MSG});
    return [ 404, [ 'Content-Type' => 'text/html'], ['Not found']];
}

sub once_after($$$&) {
    my($self, $req, $path, $cb) = @_;

    my $this_list = $self->{after_hooks}->{$req}->{$path} ||= [];

    my $wrapped_as_str;
    my $wrapped = sub {
        &$cb;
        for (my $i = 0; $i < @$this_list; $i++) {
            if ($this_list->[$i] eq $wrapped_as_str) {
                splice(@$this_list, $i, 1);
                return;
           }
        }
    };
    $wrapped_as_str = $wrapped . '';

    push @$this_list, $wrapped;
}

1;
