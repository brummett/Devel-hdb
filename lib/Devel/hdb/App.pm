use warnings;
use strict;

package Devel::hdb::App;

BEGIN {
    our $PROGRAM_NAME = $0;
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
        $_->get("/sourcefile", sub { $self->sourcefile(@_) });
        $_->get("/program_name", sub { $self->program_name(@_) });
        $_->get("/loadedfiles", sub { $self->loaded_files(@_) });
        $_->post("/eval", sub { $self->do_eval(@_) });
        $_->post("/getvar", sub { $self->do_getvar(@_) });
        $_->post("/announce_child", sub { $self->announce_child(@_) });
    }
    require Devel::hdb::App::Stack;
    require Devel::hdb::App::Control;
    require Devel::hdb::App::Ping;
    require Devel::hdb::App::Assets;
    require Devel::hdb::App::Config;
    require Devel::hdb::App::Terminate;
    require Devel::hdb::App::PackageInfo;
    require Devel::hdb::App::Breakpoint;

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

# Evaluate some expression in the debugged program's context.
# It works because when string-eval is used, and it's run from
# inside package DB, then magic happens where it's evaluate in
# the first non-DB-pacakge call frame.
# We're setting up a long_call so we can return back from all the
# web-handler code (which are non-DB packages) before actually
# evaluating the string.
sub do_eval {
    my($self, $env) = @_;
    my $req = Plack::Request->new($env);
    my $eval_string = $req->content();

    my $resp = $self->_resp('evalresult', $env);

    my $result_packager = sub {
        my $data = shift;
        $data->{expr} = $eval_string;
        return $data;
    };
    return $self->_eval_plumbing_closure($eval_string,$resp, $env, $result_packager);
}

sub _eval_plumbing_closure {
    my($self, $eval_string, $resp, $env, $result_packager) = @_;

    $DB::eval_string = $eval_string;
    return sub {
        my $responder = shift;
        my $writer = $responder->([ 200, [ 'Content-Type' => 'application/json' ]]);
        $env->{'psgix.harakiri.commit'} = Plack::Util::TRUE;

        DB->long_call(
            DB->prepare_eval(
                $eval_string,
                sub {
                    my $data = shift;
                    $data->{result} = $self->_encode_eval_data($data->{result}) if ($data->{result});
                    $data = $result_packager->($data);

                    $resp->data($data);
                    $writer->write($resp->encode());
                    $writer->close();
                }
            )
        );
    };
}

sub _encode_eval_data {
    my($self, $value) = @_;

    if (ref $value) {
        my $reftype     = Scalar::Util::reftype($value);
        my $refaddr     = Scalar::Util::refaddr($value);
        my $blesstype   = Scalar::Util::blessed($value);

        if ($reftype eq 'HASH') {
            $value = { map { $_ => $self->_encode_eval_data($value->{$_}) } keys(%$value) };

        } elsif ($reftype eq 'ARRAY') {
            $value = [ map { $self->_encode_eval_data($_) } @$value ];

        } elsif ($reftype eq 'GLOB') {
            my %tmpvalue = map { $_ => $self->_encode_eval_data(*{$value}{$_}) }
                           grep { *{$value}{$_} }
                           qw(HASH ARRAY SCALAR);
            if (*{$value}{CODE}) {
                $tmpvalue{CODE} = *{$value}{CODE};
            }
            if (*{$value}{IO}) {
                $tmpvalue{IO} = 'fileno '.fileno(*{$value}{IO});
            }
            $value = \%tmpvalue;
        } elsif (($reftype eq 'REGEXP')
                    or ($reftype eq 'SCALAR' and defined($blesstype) and $blesstype eq 'Regexp')
        ) {
            $value = $value . '';
        } elsif ($reftype eq 'SCALAR') {
            $value = $self->_encode_eval_data($$value);
        } elsif ($reftype eq 'CODE') {
            (my $copy = $value.'') =~ s/^(\w+)\=//;  # Hack to change CodeClass=CODE(0x123) to CODE=(0x123)
            $value = $copy;
        } elsif ($reftype eq 'REF') {
            $value = $self->_encode_eval_data($$value);
        }

        $value = { __reftype => $reftype, __refaddr => $refaddr, __value => $value };
        $value->{__blessed} = $blesstype if $blesstype;

    } elsif (ref(\$value) eq 'GLOB') {
        # It's an actual typeglob (not a glob ref)
        my $globref = \$value;
        my %tmpvalue = map { $_ => $self->_encode_eval_data(*{$globref}{$_}) }
                       grep { *{$globref}{$_} }
                       qw(HASH ARRAY SCALAR);
        if (*{$globref}{CODE}) {
            $tmpvalue{CODE} = *{$globref}{CODE};
        }
        if (*{$globref}{IO}) {
            $tmpvalue{IO} = 'fileno '.fileno(*{$globref}{IO});
        }
        $value = {  __reftype => 'GLOB',
                    __refaddr => Scalar::Util::refaddr($globref),
                    __value => \%tmpvalue,
                };
    }
    

    return $value;
}


sub loaded_files {
    my($self, $env) = @_;

    my $resp = $self->_resp('loadedfiles', $env);

    my @files = DB->loaded_files();
    $resp->data(\@files);
    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
        ];
}


my %perl_special_vars = map { $_ => 1 }
    qw( $0 $1 $2 $3 $4 $5 $6 $7 $8 $9 $& ${^MATCH} $` ${^PREMATCH} $'
        ${^POSTMATCH} $+ $^N @+ %+ $. $/ $| $\ $" $; $% $= $- @-
        %- $~ $^ $: $^L $^A $? ${^CHILD_ERROR_NATIVE} ${^ENCODING}
        $! %! $^E $@ $$ $< $> $[ $] $^C $^D ${^RE_DEBUG_FLAGS}
        ${^RE_TRIE_MAXBUF} $^F $^H %^H $^I $^M $^O ${^OPEN} $^P $^R
        $^S $^T ${^TAINT} ${^UNICODE} ${^UTF8CACHE} ${^UTF8LOCALE}
        $^V $^W ${^WARNING_BITS} ${^WIN32_SLOPPY_STAT} $^X @ARGV $ARGV
        @F  @ARG ); # @_ );
$perl_special_vars{q{$,}} = 1;
$perl_special_vars{q{$(}} = 1;
$perl_special_vars{q{$)}} = 1;

# Get the value of a variable, possibly in an upper stack frame
sub do_getvar {
    my($self, $env) = @_;
    my $req = Plack::Request->new($env);
    my $level = $req->param('l');
    my $varname = $req->param('v');

    my $resp = $self->_resp('getvar', $env);

    if ($perl_special_vars{$varname}) {
        my $result_packager = sub {
            my $data = shift;
            $data->{expr} = $varname;
            $data->{level} = $level;
            return $data;
        };
        return $self->_eval_plumbing_closure($varname, $resp, $env, $result_packager);
    }

    my $adjust = DB->_first_program_frame();
    my $value = eval { DB->get_var_at_level($varname, $level + $adjust - 1) };
    my $exception = $@;

    if ($exception) {
        if ($exception =~ m/Can't locate PadWalker/) {
            $resp->{type} = 'error';
            $resp->data('Not implemented - PadWalker module is not available');

        } elsif ($exception =~ m/Not nested deeply enough/) {
            $resp->data( { expr => $varname, level => $level, result => undef } );
        } else {
            die $exception
        }
    } else {
        $value = $self->_encode_eval_data($value);
        $resp->data( { expr => $varname, level => $level, result => $value } );
    }
    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
        ];
}



# Return the name of the program, $o
sub program_name {
    my($self, $env) = @_;

    my $resp = $self->_resp('program_name', $env);

    our $PROGRAM_NAME;
    $resp->data($PROGRAM_NAME);

    return [200, ['Content-Type' => 'text/plain'],
                [ $resp->encode() ]
        ];
}


# send back a list.  Each list elt is a list of 2 elements:
# 0: the line of code
# 1: whether that line is breakable
sub sourcefile {
    my($self, $env) = @_;
    my $req = Plack::Request->new($env);
    my $resp = $self->_resp('sourcefile', $env);

    my $filename = $req->param('f');
    my $file;
    {
        no strict 'refs';
        $file = $main::{'_<' . $filename};
    }

    my @rv;
    if ($file) {
        no warnings 'uninitialized';  # at program termination, the loaded file data can be undef
        #my $offset = $file->[0] =~ m/use\s+Devel::_?hdb;/ ? 1 : 0;
        my $offset = 1;

        for (my $i = $offset; $i < scalar(@$file); $i++) {
            no warnings 'numeric';  # eval-ed "sources" generate "not-numeric" warnings
            push @rv, [ $file->[$i], $file->[$i] + 0 ];
        }
    }

    $resp->data({ filename => $filename, lines => \@rv});

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
        ];
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
    our $PROGRAM_NAME;
    return ((defined($prefix) && $prefix) || $PROGRAM_NAME) . '.hdb';
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
