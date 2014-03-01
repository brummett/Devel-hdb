use warnings;
use strict;

package Devel::hdb::App;

use Devel::Chitin;
use base 'Devel::Chitin';
use Devel::hdb::Server;
use IO::File;
use LWP::UserAgent;
use Data::Dumper;
use Sys::Hostname;
use IO::Socket::INET;

use Devel::hdb::Router;
use Devel::hdb::Response;

use vars qw( $parent_pid ); # when running in the test harness

our $APP_OBJ;
sub get {
    return $APP_OBJ if $APP_OBJ;  # get() is a singleton

    my $class = shift;

    my $self = $APP_OBJ = bless {}, $class;

    $self->_make_listen_socket();

    $parent_pid = eval { getppid() } if ($Devel::hdb::TESTHARNESS);
    return $self;
}

sub _make_listen_socket {
    my $self = shift;
    my %server_params = @_;

    $Devel::hdb::HOST = $server_params{host} = $Devel::hdb::HOST || '127.0.0.1';
    if (!exists($server_params{port}) and defined($Devel::hdb::PORT)) {
        $server_params{port} = $Devel::hdb::PORT;
    }

    $server_params{listen_sock} = $Devel::hdb::LISTEN_SOCK if defined $Devel::hdb::LISTEN_SOCK;

    unless (exists $server_params{server_ready}) {
        $server_params{server_ready} = sub { $self->init_debugger };
    }

    $Devel::hdb::LISTEN_SOCK = undef;
    $self->{server} = Devel::hdb::Server->new( %server_params );
}

sub router {
    my $self = shift;
    unless (ref $self) {
        $self = $self->get()
    }
    if (@_) {
        $self->{router} = shift;
    }
    return $self->{router};
}

sub init_debugger {
    my $self = shift;

    if ($parent_pid and !kill(0, $parent_pid)) {
        # The parent PID for testing is gone
        exit();
    }

    return if $self->{__init__};
    $self->{__init__} = 1;

    $self->_announce();

    $self->router( Devel::hdb::Router->new() );

    require Devel::hdb::App::Stack;
    require Devel::hdb::App::Control;
    require Devel::hdb::App::ProgramName;
    require Devel::hdb::App::Ping;
    require Devel::hdb::App::Assets;
    require Devel::hdb::App::Config;
    require Devel::hdb::App::Terminate;
    require Devel::hdb::App::PackageInfo;
    require Devel::hdb::App::Breakpoint;
    require Devel::hdb::App::Action;
    require Devel::hdb::App::SourceFile;
    require Devel::hdb::App::Eval;
    require Devel::hdb::App::AnnounceChild;

    eval { $self->load_settings_from_file() };

}

sub _announce {
    my $self = shift;

    # HTTP::Server::PSGI doesn't have a method to get the listen socket :(
    my $s = $self->{server}->{listen_sock};
    my $hostname = $s->sockhost;
    if ($hostname eq '0.0.0.0') {
        $hostname = Sys::Hostname::hostname();
    } elsif ($hostname ne '127.0.0.1') {
        $hostname = gethostbyaddr($s->sockaddr, AF_INET);
    }
    $self->{base_url} = sprintf('http://%s:%d/',
            $hostname, $s->sockport);

    select STDOUT;
    local $| = 1;
    print "Debugger pid $$ listening on ",$self->{base_url},"\n" unless ($Devel::hdb::TESTHARNESS);
}


sub notify_stopped {
    my($self, $location) = @_;

    my $cb = delete $self->{at_next_breakpoint};
    $cb && $cb->();
}

# Called in the parent process after a fork
sub notify_fork_parent {
    my($self, $location, $child_pid) = @_;

    my $gotit = sub {
        my($rv,$env) = @_;
        $env->{'psgix.harakiri.commit'} = Plack::Util::TRUE;
    };
    $self->{router}->once_after('POST','/announce_child', $gotit);
    $self->run();
    $self->step;
}

# called in the child process after a fork
sub notify_fork_child {
    my $self = shift;
    my $location = shift;

    delete $self->{at_next_breakpoint};

    $parent_pid = undef;
    my $parent_base_url = $self->{base_url};

    my $announced;
    my $when_ready = sub {
        unless ($announced) {
            $announced = 1;
            $self->_announce();
            my $ua = LWP::UserAgent->new();
            my $resp = $ua->post($parent_base_url
                                . 'announce_child', { pid => $$, uri => $self->{base_url} });
            unless ($resp->is_success()) {
                print STDERR "sending announce failed... exiting\n";
                exit(1) if ($Devel::hdb::TESTHARNESS);
            }
        }
    };

    # Force it to pick a new port
    $self->_make_listen_socket(port => undef, server_ready => $when_ready);
    $self->step;
}


# Send back a data structure describing the call stack
# stepin, stepover, stepout and run will call this to return
# back to the debugger window the current state
sub app {
    my $self = shift;
    unless ($self->{app}) {
        $self->{app} =  sub { $self->{router}->route(@_); };
    }
    return $self->{app};
}

sub run {
    my $self = shift;
    $self->{server}->run($self->app);
    1;
}
*idle = \&run;

# If we're in trace mode, then don't stop
sub poll {
    my $self = shift;
    return ! $self->{trace};
}

sub notify_trace_diff {
    my($self, $trace_data) = @_;

    my $follower = delete $self->{follow};
    $follower->shutdown();
    $self->step();

    my $msg = Devel::hdb::Response->queue('trace_diff');
    $msg->{data} = $trace_data;
}

sub notify_uncaught_exception {
    my $self = shift;
    my $exception = shift;

    $self->{__exception__} = $exception;
}

sub notify_program_terminated {
    my $self = shift;
    my $exit_code = shift;

    print STDERR "Debugged program pid $$ terminated with exit code $exit_code\n" unless ($Devel::hdb::TESTHARNESS);
    my $msg = Devel::hdb::Response->queue('termination');
    my $data = { exit_code => $exit_code };

    if ($self->{__exception__}) {
        foreach my $prop ( qw(package line filename exception subroutine)) {
            $data->{$prop} = $self->{__exception__}->$prop;
        }
    }
    $msg->data($data);
}

sub notify_program_exit {
    my $msg = Devel::hdb::Response->queue('hangup');
}

sub settings_file {
    my $class = shift;
    my $prefix = shift;
    return ((defined($prefix) && $prefix) || $0) . '.hdb';
}

sub load_settings_from_file {
    my $self = shift;
    my $file = shift;

    unless (defined $file) {
        $file = $self->settings_file();
    }

    my $buffer;
    {
        local($/);
        my $fh = IO::File->new($file, 'r') || die "Can't open file $file for reading: $!";
        $buffer = <$fh>;
    }
    my $settings = eval $buffer;
    die $@ if $@;


    my @set_breakpoints;
    foreach my $bp ( @{ $settings->{breakpoints}} ) {
        push @set_breakpoints,
            Devel::hdb::App::Breakpoint->set_and_respond($self, %$bp);
    }
    foreach my $action ( @{ $settings->{actions}} ) {
        push @set_breakpoints,
            Devel::hdb::App::Action->set_and_respond($self, %$action);
    }
    return @set_breakpoints;
}

sub save_settings_to_file {
    my $self = shift;
    my $file = shift;

    unless (defined $file) {
        $file = $self->settings_file();
    }

    my @breakpoints = $self->get_breaks();
    my @actions = $self->get_actions();
    my $fh = IO::File->new($file, 'w') || die "Can't open $file for writing: $!";
    my $config = { breakpoints => \@breakpoints, actions => \@actions };
    $fh->print( Data::Dumper->new([ $config ])->Terse(1)->Dump());
    return $file;
}

1;
