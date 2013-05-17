use warnings;
use strict;

package Devel::hdb::App;

BEGIN {
    our $ORIGINAL_PID = $$;
}

use Devel::hdb::Server;
use Plack::Request;
use IO::File;
use JSON qw();
use Scalar::Util;
use LWP::UserAgent;
use Data::Dumper;
use File::Basename;

use Devel::hdb::Router;

use vars qw( $parent_pid ); # when running in the test harness

our $APP_OBJ;
sub get {
    return $APP_OBJ if $APP_OBJ;  # get() is a singleton

    my $class = shift;

    my $self = $APP_OBJ = bless {}, $class;

    $self->_make_listen_socket();
    $self->{json} = JSON->new();

    $parent_pid = eval { getppid() } if ($Devel::hdb::TESTHARNESS);
    return $self;
}

sub _make_listen_socket {
    my $self = shift;
    my %server_params = @_;

    $server_params{host} = $Devel::hdb::HOST || '127.0.0.1';
    if (!exists($server_params{port}) and defined($Devel::hdb::PORT)) {
        $server_params{port} = $Devel::hdb::PORT;
    }

    unless (exists $server_params{server_ready}) {
        $server_params{server_ready} = sub { $self->init_debugger };
    }

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

    for ($self->{router}) {
        # All the paths we listen for
        $_->post("/announce_child", sub { $self->announce_child(@_) });
    }
    require Devel::hdb::App::Stack;
    require Devel::hdb::App::Control;
    require Devel::hdb::App::ProgramName;
    require Devel::hdb::App::Ping;
    require Devel::hdb::App::Assets;
    require Devel::hdb::App::Config;
    require Devel::hdb::App::Terminate;
    require Devel::hdb::App::PackageInfo;
    require Devel::hdb::App::Breakpoint;
    require Devel::hdb::App::SourceFile;
    require Devel::hdb::App::Eval;

    eval { $self->load_settings_from_file() };

}

sub _announce {
    my $self = shift;

    # HTTP::Server::PSGI doesn't have a method to get the listen socket :(
    my $s = $self->{server}->{listen_sock};
    $self->{base_url} = sprintf('http://%s:%d/',
            $s->sockhost, $s->sockport);

    select STDOUT;
    local $| = 1;
    print "Debugger pid $$ listening on ",$self->{base_url},"\n" unless ($Devel::hdb::TESTHARNESS);
}


# Called in the parent process after a fork
sub notify_parent_child_was_forked {
    my($self, $child_pid) = @_;

    my $gotit = sub {
        my($rv,$env) = @_;
        $env->{'psgix.harakiri.commit'} = Plack::Util::TRUE;
    };
    $self->{router}->once_after('POST','/announce_child', $gotit);
    $self->run();
}

# called in the child process after a fork
sub notify_child_process_is_forked {
    my $self = shift;

    $parent_pid = undef;
    our($ORIGINAL_PID) = $$;
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
}

sub encode {
    my $self = shift;
    return $self->{json}->encode(shift);
}

sub _resp {
    my $self = shift;
    return Devel::hdb::App::Response->new(@_);
}

sub announce_child {
    my($self, $env) = @_;
    my $req = Plack::Request->new($env);
    my $child_pid = $req->param('pid');
    my $child_uri = $req->param('uri');

    my $resp = Devel::hdb::App::Response->queue('child_process', $env);
    $resp->{data} = {
            pid => $child_pid,
            uri => $child_uri,
            run => $child_uri . 'continue?nostop=1'
        };

    return [200, [], []];
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
    return $self->{server}->run($self->app);
}

sub notify_trace_diff {
    my($self, $trace_data) = @_;

    my $msg = Devel::hdb::App::Response->queue('trace_diff');
    $msg->{data} = $trace_data;
}

sub notify_program_terminated {
    my $class = shift;
    my $exit_code = shift;
    my $exception_data = shift;

    print STDERR "Debugged program pid $$ terminated with exit code $exit_code\n" unless ($Devel::hdb::TESTHARNESS);
    my $msg = Devel::hdb::App::Response->queue('termination');
    if ($exception_data) {
        $msg->{data} = $exception_data;
    }
    $msg->{data}->{exit_code} = $exit_code;
}

sub notify_program_exit {
    my $msg = Devel::hdb::App::Response->queue('hangup');
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
        my %req;
        foreach my $key ( qw( condition condition_inactive action action_inactive ) ) {
            $req{$key} = $bp->{$key} if (exists $bp->{$key});
        }
        push @set_breakpoints,
            Devel::hdb::App::Breakpoint->set_breakpoint_and_respond($bp->{filename}, $bp->{lineno}, %req);
        #$resp->data( $resp_data );
    }
    return @set_breakpoints;
}

sub save_settings_to_file {
    my $self = shift;
    my $file = shift;

    unless (defined $file) {
        $file = $self->settings_file();
    }

    my @breakpoints = DB->get_breakpoint();
    my $fh = IO::File->new($file, 'w') || die "Can't open $file for writing: $!";
    $fh->print( Data::Dumper->new([{ breakpoints => \@breakpoints}])->Terse(1)->Dump());
    return $file;
}



package Devel::hdb::App::Response;

sub new {
    my($class, $type, $env) = @_;

    my $self = { type => $type };

    if ($env) {
        my $req = Plack::Request->new($env);
        my $rid = $req->param('rid');
        if (defined $rid) {
            $self->{rid} = $rid;
        }
    }
    bless $self, $class;
}

our @queued;
sub queue {
    my $class = shift;

    my $self = $class->new(@_);
    push @queued, $self;
    return $self;
}

sub _make_copy {
    my $self = shift;

    my %copy = map { exists($self->{$_}) ? ($_ => $self->{$_}) : () } keys %$self;
    return \%copy;
}

sub encode {
    my $self = shift;

    my $copy = $self->_make_copy();

    my $retval = '';
    if (@queued) {
        foreach ( @queued ) {
            $_ = $_->_make_copy();
        }
        unshift @queued, $copy;
        $retval = eval { JSON::encode_json(\@queued) };
        @queued = ();
    } else {
        $retval = eval { JSON::encode_json($copy) };
    }
    return $retval;
}

sub data {
    my $self = shift;
    if (@_) {
        $self->{data} = shift;
    }
    return $self->{data};
}

1;
