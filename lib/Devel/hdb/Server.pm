package Devel::hdb::Server;

use strict;
use warnings;

use HTTP::Server::PSGI;
our @ISA = qw( HTTP::Server::PSGI );

use Socket qw(IPPROTO_TCP TCP_NODELAY);

our $VERSION = '0.23_02';

use Devel::hdb::Logger qw(log);

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

    log('entering accept_loop()');
    $app = Plack::Middleware::ContentLength->wrap($app);
    log("got app $app");

    ACCEPT_LOOP:
    while (1) {
        log('Top of accept_loop() loop');
        local $SIG{PIPE} = 'IGNORE';
        log('Just before accept...');
        if (my $conn = $self->{listen_sock}->accept) {
            log('Connection from ',$conn->peerhost,':',$conn->peerport);
            my $rv = $conn->setsockopt(IPPROTO_TCP, TCP_NODELAY, 1)
                or die "setsockopt(TCP_NODELAY) failed:$!";
            log("setsockopt() returned $rv");
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
            log('back from handle_connection(), harakiri: ' . (!! $env->{'psgix.harakiri.commit'}));
            #$conn->close;
            last ACCEPT_LOOP if $env->{'psgix.harakiri.commit'};
            log('bottom of if-block after accept()');
        } else {
            log("accept() failed: $!");
            my $errno = $! + 0;
            log("   errno $errno");
        }
    }
}

sub _handle_response {
    my($self, $res, $conn) = @_;

    log('Preparing response for code ',$res->[0]);
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

    log('Writing ', scalar(@lines), ' lines of headers');
    $self->write_all($conn, join('', @lines), $self->{timeout})
        or return;

    if (defined $res->[2]) {
        log('Writing ',length($res->[2]),' bytes of body');
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
            log('Done writing; closing connection');
            $conn->close();

        } else {
            if ($err =~ /^failed to send all data\n/) {
                return;
            } else {
                die $err;
            }
        }
    } else {
        log('Setting up for delayed write');
        return Plack::Util::inline_object
            write => sub { $self->write_all($conn, $_[0], $self->{timeout}) },
            close => sub { $conn->close() };
    }
}

1;
