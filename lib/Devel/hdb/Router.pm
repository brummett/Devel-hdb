package Devel::hdb::Router;

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

print "request method ".$env->{REQUEST_METHOD},"\n";
    return unless exists $self->{$env->{REQUEST_METHOD}};
    my $matchlist = $self->{$env->{REQUEST_METHOD}};
print "path ".$env->{PATH_INFO},"\n";

    my $fire;
    foreach my $route ( @$matchlist ) {
        my($path,$cb) = @$route;
print "route $path\n";

        if (my $ref = ref($path)) {
            if ($ref eq 'Regexp') {
                $fire = 1 if ($env->{PATH_INFO} =~ $path);
            } elsif ($ref eq 'CODE') {
                $fire = 1 if ($path->($self, $env));
            }
        } elsif ($env->{PATH_INFO} eq $path) {
            $fire = 1;
        }

print "fire $fire\n";
        if ($fire) {
print "firing callback\n";
            return $cb->($env);
        }
    }
print "path $path not found\n";
    return [ 404, [ 'Content-Type' => 'text/html'], ['Not found']];
}

1;
    
