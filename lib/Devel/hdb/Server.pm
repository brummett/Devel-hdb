package Devel::hdb::Server;

use HTTP::Server::PSGI;
our @ISA = qw( HTTP::Server::PSGI );

use Socket qw(IPPROTO_TCP TCP_NODELAY);

sub new {
    my($class, %args) = @_;

    my %supplied_port_arg;
    if (exists $args{port}) {
        $supplied_port_arg{port} = delete $args{port};
    }

    my $self = $class->SUPER::new(%args);
    if (%supplied_port_arg) {
        $self->{port} = $supplied_port_arg{port};
    }

    $self->{listen_sock} = $args{listen_sock} if exists $args{listen_sock};
    return $self;
}

sub accept_loop {
    my($self, $app) = @_;

    $app = Plack::Middleware::ContentLength->wrap($app);

    while (1) {
        local $SIG{PIPE} = 'IGNORE';
        if (my $conn = $self->{listen_sock}->accept) {
            $conn->setsockopt(IPPROTO_TCP, TCP_NODELAY, 1)
                or die "setsockopt(TCP_NODELAY) failed:$!";
            my $env = {
                SERVER_PORT => $self->{port},
                SERVER_NAME => $self->{host},
                SCRIPT_NAME => '',
                REMOTE_ADDR => $conn->peerhost,
                REMOTE_PORT => $conn->peerport || 0,
                'psgi.version' => [ 1, 1 ],
                'psgi.errors'  => *STDERR,
                'psgi.url_scheme' => $self->{ssl} ? 'https' : 'http',
                'psgi.run_once'     => Plack::Util::FALSE,
                'psgi.multithread'  => Plack::Util::FALSE,
                'psgi.multiprocess' => Plack::Util::FALSE,
                'psgi.streaming'    => Plack::Util::TRUE,
                'psgi.nonblocking'  => Plack::Util::FALSE,
                'psgix.harakiri'    => Plack::Util::TRUE,
                'psgix.input.buffered' => Plack::Util::TRUE,
                'psgix.io'          => $conn,
            };

            $self->handle_connection($env, $conn, $app);
            #$conn->close;
            last if $env->{'psgix.harakiri.commit'};
        }
    }
}

sub _handle_response {
    my($self, $res, $conn) = @_;

    my @lines = (
        "Date: @{[HTTP::Date::time2str()]}\015\012",
        "Server: $self->{server_software}\015\012",
    );

    Plack::Util::header_iter($res->[1], sub {
        my ($k, $v) = @_;
        push @lines, "$k: $v\015\012";
    });

    unshift @lines, "HTTP/1.0 $res->[0] @{[ HTTP::Status::status_message($res->[0]) ]}\015\012";
    push @lines, "\015\012";

    $self->write_all($conn, join('', @lines), $self->{timeout})
        or return;

    if (defined $res->[2]) {
        my $err;
        my $done;
        {
            local $@;
            eval {
                Plack::Util::foreach(
                    $res->[2],
                    sub {
                        $self->write_all($conn, $_[0], $self->{timeout})
                            or die "failed to send all data\n";
                    },
                );
                $done = 1;
            };
            $err = $@;
        };
        if ($done) {
            $conn->close();

        } else {
            if ($err =~ /^failed to send all data\n/) {
                return;
            } else {
                die $err;
            }
        }
    } else {
        return Plack::Util::inline_object
            write => sub { $self->write_all($conn, $_[0], $self->{timeout}) },
            close => sub { $conn->close() };
    }
}

1;
