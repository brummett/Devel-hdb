use warnings;
use strict;

package Devel::hdb::App;

BEGIN {
    our $PROGRAM_NAME = $0;
    our @saved_ARGV = @ARGV;
    our $ORIGINAL_PID = $$;
}

use Devel::hdb::Server;
use Plack::Request;
use IO::File;
use JSON qw();
use Scalar::Util;
use LWP::UserAgent;
use Data::Dumper;

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

sub init_debugger {
    my $self = shift;

    if ($parent_pid and !kill(0, $parent_pid)) {
        # The parent PID for testing is gone
        exit();
    }

    return if $self->{__init__};
    $self->{__init__} = 1;

    eval { $self->load_settings_from_file() };

    $self->_announce();

    $self->{router} = Devel::hdb::Router->new();
    for ($self->{router}) {
        # All the paths we listen for
        $_->get(qr(/db/(.*)), sub { $self->assets(@_) });
        $_->get(qr(/img/(.*)), sub { $self->assets(@_) });
        $_->get("/", sub { $self->assets(shift, 'debugger.html', @_) }); # load the debugger window
        $_->get("/stepin", sub { $self->stepin(@_) });
        $_->get("/stepover", sub { $self->stepover(@_) });
        $_->get("/stepout", sub { $self->stepout(@_) });
        $_->get("/continue", sub { $self->continue(@_) });
        $_->get("/stack", sub { $self->stack(@_) });
        $_->get("/sourcefile", sub { $self->sourcefile(@_) });
        $_->get("/program_name", sub { $self->program_name(@_) });
        $_->post("/breakpoint", sub { $self->set_breakpoint(@_) });
        $_->get("/breakpoint", sub { $self->get_breakpoint(@_) });
        $_->get("/breakpoints", sub { $self->get_all_breakpoints(@_) });
        $_->get("/loadedfiles", sub { $self->loaded_files(@_) });
        $_->get("/exit", sub { $self->do_terminate(@_) });
        $_->post("/eval", sub { $self->do_eval(@_) });
        $_->post("/getvar", sub { $self->do_getvar(@_) });
        $_->post("/announce_child", sub { $self->announce_child(@_) });
        $_->get("/ping", sub { $self->ping(@_) });
        $_->post("/loadconfig", sub { $self->loadconfig(@_) });
        $_->post("/saveconfig", sub { $self->saveconfig(@_) });
    }
}

sub ping {
    my($self,$env) = @_;

    my $resp = $self->_resp('ping', $env);
    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
        ];
}

sub _announce {
    my $self = shift;

    # HTTP::Server::PSGI doesn't have a method to get the listen socket :(
    my $s = $self->{server}->{listen_sock};
    $self->{base_url} = sprintf('http://%s:%d/',
            $s->sockhost, $s->sockport);

    select STDOUT;
    local $| = 1;
    print "Debugger pid $$ listening on ",$self->{base_url},"\n";
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

# Exit the running program
# Sets up as a long_call so we can send the 'hangup' response
# and then exit()
sub do_terminate {
    my $json = shift->{json};
    DB->user_requested_exit();
    return sub {
        my $responder = shift;
        my $writer = $responder->([ 200, [ 'Content-Type' => 'application/json' ]]);

        my $resp = Devel::hdb::App::Response->new('hangup');
        $writer->write($resp->encode);
        $writer->close();
        exit();
    };
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


# sets a breakpoint on line l of file f with condition c
# Make c=1 for an unconditional bp, c='' to clear it
sub set_breakpoint {
    my($self, $env) = @_;
    my $req = Plack::Request->new($env);
    my $filename = $req->param('f');
    my $line = $req->param('l');
    my $condition = $req->param('c');
    my $condition_inactive = $req->param('ci');
    my $action = $req->param('a');
    my $action_inactive = $req->param('ai');

    if (! DB->is_loaded($filename)) {
        return [ 404, ['Content-Type' => 'text/html'], ["$filename is not loaded"]];
    } elsif (! DB->is_breakable($filename, $line)) {
        return [ 403, ['Content-Type' => 'text/html'], ["line $line of $filename is not breakable"]];
    }

    my $resp = $self->_resp('breakpoint', $env);

    my $params = $req->parameters;
    my %req;
    $req{condition} = $condition if (exists $params->{'c'});
    $req{condition_inactive} = $condition_inactive if (exists $params->{'ci'});
    $req{action} = $action if (exists $params->{'a'});
    $req{action_inactive} = $action_inactive if (exists $params->{'ai'});

    my $resp_data = $self->_set_breakpoint_and_respond($filename, $line, %req);
    $resp->data( $resp_data );

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
          ];
}

sub _set_breakpoint_and_respond {
    my($self, $filename, $line, %params) = @_;

    unless (DB->is_loaded($filename)) {
        DB->postpone_until_loaded(
                $filename,
                sub { DB->set_breakpoint($filename, $line, %params) }
        );
        return;
    }

    DB->set_breakpoint($filename, $line, %params);

    my $resp_data = DB->get_breakpoint($filename, $line);
    unless ($resp_data) {
        # This breakpoint was deleted
        $resp_data = { filename => $filename, lineno => $line };
    }
    return $resp_data;
}



sub get_breakpoint {
    my($self, $env) = @_;
    my $req = Plack::Request->new($env);
    my $filename = $req->param('f');
    my $line = $req->param('l');

    my $resp = $self->_resp('breakpoint', $env);
    $resp->data( DB->get_breakpoint($filename, $line) );

    return [ 200, ['Content-Type' => 'application/json'],
            [ $resp->encode() ]
          ];
}

sub get_all_breakpoints {
    my($self, $env) = @_;
    my $req = Plack::Request->new($env);
    my $filename = $req->param('f');
    my $line = $req->param('l');
    my $rid = $req->param('rid');

    # Purposefully not using a response object because there's not yet
    # clean way to encode a list of them
    my @bp = map {  { type => 'breakpoint', data => $_, defined($rid) ? (rid => $rid) : () } }
            DB->get_breakpoint($filename, $line);
    return [ 200, ['Content-Type' => 'application/json'],
            [ $self->encode( \@bp ) ]
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
sub _stack {
    my $self = shift;

    my $discard = 1;
    my @stack;
    my $next_AUTOLOAD_name = $#DB::AUTOLOAD_names;
    our @saved_ARGV;

    for (my $i = 0; ; $i++) {
        my %caller;
        {
            package DB;
            @caller{qw( package filename line subroutine hasargs wantarray
                        evaltext is_require )} = caller($i);
        }
        last unless defined ($caller{line});
        # Don't include calls within the debugger
        if ($caller{subroutine} eq 'DB::DB') {
            $discard = 0;
        }
        next if $discard;

        $caller{args} = [ map { $self->_encode_eval_data($_) } @DB::args ]; # unless @stack;
        $caller{subname} = $caller{subroutine} =~ m/\b(\w+$|__ANON__)/ ? $1 : $caller{subroutine};
        if ($caller{subname} eq 'AUTOLOAD') {
            $caller{subname} .= '(' . ($DB::AUTOLOAD_names[ $next_AUTOLOAD_name-- ] =~ m/::(\w+)$/)[0] . ')';
        }
        $caller{level} = $i;

        push @stack, \%caller;
    }
    # TODO: put this into the above loop
    for (my $i = 0; $i < @stack-1; $i++) {
        @{$stack[$i]}{'subroutine','subname','args'} = @{$stack[$i+1]}{'subroutine','subname','args'};
    }
    $stack[-1]->{subroutine} = 'MAIN';
    $stack[-1]->{subname} = 'MAIN';
    $stack[-1]->{args} = \@saved_ARGV; # These are guaranteed to be simple scalars, no need to encode

    return \@stack;
}

sub stack {
    my($self, $env) = @_;

    my $resp = $self->_resp('stack', $env);
    $resp->data( $self->_stack );

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
        ];
}


# send back a file located in the 'html' subdirectory
sub assets {
    my($self, $env, $file) = @_;

    $file =~ s/\.\.//g;  # Remove ..  They're unnecessary and a security risk
    my $file_path = $INC{'Devel/hdb.pm'};
    $file_path =~ s/\.pm$//;
    $file_path .= '/html/'.$file;
    my $fh = IO::File->new($file_path);
    unless ($fh) {
        return [ 404, ['Content-Type' => 'text/html'], ['Not found']];
    }

    my $type;
    if ($file =~ m/\.js$/) {
        $type = 'application/javascript';
    } elsif ($file =~ m/\.html$/) {
        $type = 'text/html';
    } elsif ($file =~ m/\.css$/) {
        $type = 'text/css';
    } else {
        $type = 'text/plain';
    }

    if ($env->{'psgi.streaming'}) {
        return [ 200, ['Content-Type' => $type], $fh];
    } else {
        local $/;
        my $buffer = <$fh>;
        return [ 200, ['Content-Type' => $type], [$buffer]];
    }
}

sub stepover {
    my $self = shift;

    $DB::single=1;
    $DB::step_over_depth = $DB::stack_depth;
    return $self->_delay_stack_return_to_client(@_);
}

sub stepin {
    my $self = shift;

    $DB::single=1;
    return $self->_delay_stack_return_to_client(@_);
}

sub stepout {
    my $self = shift;

    $DB::single=0;
    $DB::step_over_depth = $DB::stack_depth - 1;
    return $self->_delay_stack_return_to_client(@_);
}
    

sub continue {
    my $self = shift;
    my $env = shift;

    my $req = Plack::Request->new($env);
    my $nostop = $req->param('nostop');

    $DB::single=0;
    if ($nostop) {
        DB->disable_debugger();
        my $resp = Devel::hdb::App::Response->new('continue', $env);
        $resp->data({ nostop => 1 });
        $env->{'psgix.harakiri.commit'} = Plack::Util::TRUE;
        return [ 200,
                    [ 'Content-Type' => 'application/json'],
                    [ $resp->encode() ]
                ];
    }

    return $self->_delay_stack_return_to_client($env);
}

sub _delay_stack_return_to_client {
    my $self = shift;
    my $env = shift;

    my $req = Plack::Request->new($env);
    my $rid = $req->param('rid');

    my $json = $self->{json};
    return sub {
        my $responder = shift;
        my $writer = $responder->([ 200, [ 'Content-Type' => 'application/json' ]]);
        $env->{'psgix.harakiri.commit'} = Plack::Util::TRUE;

        DB->long_call( sub {
            my $resp = Devel::hdb::App::Response->new('stack', $env);
            $resp->data( $self->_stack );
            $writer->write( $resp->encode );
            $writer->close();
        });
    };
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
    return $self->{server}->run($self->app);
}


sub notify_program_terminated {
    my $class = shift;
    my $exit_code = shift;

    my $msg = Devel::hdb::App::Response->queue('termination');
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

sub loadconfig {
    my($self, $env) = @_;

    my $req = Plack::Request->new($env);
    my $file = $req->param('f');

    my @results = eval { $self->load_settings_from_file($file) };
    my $load_resp = Devel::hdb::App::Response->new('loadconfig', $env);
    if (! $@) {
        foreach (@results) {
            my $resp = Devel::hdb::App::Response->queue('breakpoint');
            $resp->data($_);
        }

        $load_resp->data({ success => 1, filename => $file });

    } else {
        $load_resp->data({ failed => $@ });
    }
    return [ 200,
            [ 'Content-Type' => 'application/json'],
            [ $load_resp->encode() ]
        ];
}

sub saveconfig {
    my($self, $env) = @_;

    my $req = Plack::Request->new($env);
    my $file = $req->param('f');

    $file = eval { $self->save_settings_to_file($file) };
    my $resp = Devel::hdb::App::Response->new('saveconfig', $env);
    if ($@) {
        $resp->data({ failed => $@ });
    } else {
        $resp->data({ success => 1, filename => $file });
    }
    return [ 200,
            [ 'Content-Type' => 'application/json'],
            [ $resp->encode() ]
        ];
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
             $self->_set_breakpoint_and_respond($bp->{filename}, $bp->{lineno}, %req);
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

    my $retval;
    if (@queued) {
        foreach ( @queued ) {
            $_ = $_->_make_copy();
        }
        unshift @queued, $copy;
        $retval = JSON::encode_json(\@queued);
        @queued = ();
    } else {
        $retval = JSON::encode_json($copy);
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
