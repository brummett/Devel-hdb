use warnings;
use strict;

package Devel::hdb::App;

use Devel::Chitin 0.05;
use base 'Devel::Chitin';
use Devel::hdb::Server;
use IO::File;
use LWP::UserAgent;
use Data::Dumper;
use Sys::Hostname;
use IO::Socket::INET;
use JSON qw();
use Data::Transform::ExplicitMetadata;
use Sub::Name qw(subname);

use Devel::hdb::Router;

use vars qw( $parent_pid ); # when running in the test harness

our $APP_OBJ;
sub get {
    return $APP_OBJ if $APP_OBJ;  # get() is a singleton

    my $class = shift;

    my $self = $APP_OBJ = bless {}, $class;

    $self->_make_json_encoder();
    $self->_make_listen_socket();

    $parent_pid = eval { getppid() } if ($Devel::hdb::TESTHARNESS);
    return $self;
}

sub _make_json_encoder {
    my $self = shift;
    $self->{json} = JSON->new->utf8->allow_nonref();
    return $self;
}

sub encode_json {
    my $self = shift;
    my $json = $self->{json};
    return map { $json->encode($_) } @_;
}

sub decode_json {
    my $self = shift;
    my $json = $self->{json};
    my @rv = map { $json->decode($_) } @_;
    return wantarray
        ? @rv
        : $rv[0];
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
    require Devel::hdb::App::Assets;
    require Devel::hdb::App::Config;
    require Devel::hdb::App::Terminate;
    require Devel::hdb::App::PackageInfo;
    require Devel::hdb::App::Breakpoint;
    require Devel::hdb::App::Action;
    require Devel::hdb::App::SourceFile;
    require Devel::hdb::App::Eval;
    require Devel::hdb::App::AnnounceChild;
    require Devel::hdb::App::Watchpoint;

    eval { $self->load_settings_from_file() };

}

sub _gui_url {
    my $self = shift;
    return $self->{base_url} . '/debugger-gui';
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
    $self->{base_url} = sprintf('http://%s:%d',
            $hostname, $s->sockport);

    my $announce_url = $self->_gui_url;

    STDOUT->printflush("Debugger pid $$ listening on $announce_url\n") unless ($Devel::hdb::TESTHARNESS);
}

sub on_notify_stopped {
    my $self = shift;
    if (@_) {
        $self->{at_next_breakpoint} = shift;
    }
    return $self->{at_next_breakpoint};
}

sub notify_stopped {
    my($self, $location) = @_;

    $self->current_location($location);
    my $cb = $self->on_notify_stopped;
    $self->on_notify_stopped(undef);
    $cb && $cb->();
}

sub current_location {
    my $self = shift;
    if (@_) {
        $self->{current_location} = shift;
    }
    return $self->{current_location};
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

{
    my $parent_process_base_url;
    sub _parent_process_base_url {
        my $self = shift;
        if (@_) {
            $parent_process_base_url = shift;
        }
        return $parent_process_base_url;
    }
}

# called in the child process after a fork
sub notify_fork_child {
    my $self = shift;
    my $location = shift;

    $self->on_notify_stopped(undef);
    $self->dequeue_events();

    $parent_pid = undef;
    my $parent_base_url = $self->_parent_process_base_url($self->{base_url});

    my $announced;
    my $when_ready = sub {
        unless ($announced) {
            $announced = 1;
            $self->_announce();
            my $ua = LWP::UserAgent->new();
            my $resp = $ua->post($parent_base_url
                                . '/announce_child', { pid => $$, uri => $self->{base_url}, gui => $self->_gui_url });
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

    $trace_data->{type} = 'trace_diff';
    $self->enqueue_event($trace_data);
}

sub notify_uncaught_exception {
    my $self = shift;
    my $exception = shift;

    my %event = ( type => 'exception',
                  value => Data::Transform::ExplicitMetadata::encode($exception->exception) );
    @event{'subroutine','package','filename','line'}
        = map { $exception->$_ } qw(subroutine package filename line);
    $self->enqueue_event(\%event);

    my $exception_as_comment = '# ' . join("\n# ", split(/\n/, $exception->exception));
    my $stopped = subname '__exception__' => eval qq(sub { \$self->step && (local \$DB::in_debugger = 0);\n# Uncaught exception:\n$exception_as_comment\n1;\n}\n);

    @_ = ();
    goto &$stopped;
}

sub exit_code {
    my $self = shift;
    if (@_) {
        $self->{exit_code} = shift;
    }
    return $self->{exit_code};
}

sub notify_program_terminated {
    my $self = shift;
    my $exit_code = shift;

    $self->exit_code($exit_code);
    $self->enqueue_event({ type => 'exit', value => $exit_code});

    print STDERR "Debugged program pid $$ terminated with exit code $exit_code\n" unless ($Devel::hdb::TESTHARNESS);
}

sub notify_program_exit {
    my $self = shift;
    $self->enqueue_event({ type => 'hangup' });
}

sub enqueue_event {
    my $self = shift;
    my $queue = $self->{'queued_events'} ||= [];
    push @$queue, @_;
}

sub dequeue_events {
    my $self = shift;
    return delete $self->{'queued_events'};
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

    return 0 unless -f $file;

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
            Devel::hdb::App::Breakpoint->set_and_respond($self, $bp);
    }
    foreach my $action ( @{ $settings->{actions}} ) {
        push @set_breakpoints,
            Devel::hdb::App::Action->set_and_respond($self, $action);
    }
    return 1;
}

sub save_settings_to_file {
    my $self = shift;
    my $file = shift;

    unless (defined $file) {
        $file = $self->settings_file();
    }

    my $serializer = sub {
        my %it = map { $_ => $_[0]->$_ } qw(line code inactive);
        $it{filename} = $_[0]->file;
        return \%it;
    };

    my @breakpoints = map { $serializer->($_) } $self->get_breaks();
    my @actions = map { $serializer->($_) } $self->get_actions();
    my $fh = IO::File->new($file, 'w') || die "Can't open $file for writing: $!";
    my $config = { breakpoints => \@breakpoints, actions => \@actions };
    $fh->print( Data::Dumper->new([ $config ])->Terse(1)->Dump());
    return $file;
}

1;
