use warnings;
use strict;

package Devel::hdb::App;

BEGIN {
    our $PROGRAM_NAME = $0;
    our @saved_ARGV = @ARGV;
}

use Devel::hdb::Server;
use Plack::Request;
use IO::File;
use JSON qw();
use Scalar::Util;

use Devel::hdb::Router;

use vars qw( $parent_pid ); # when running in the test harness

sub new {
    my $class = shift;
    my %server_params = (host => $Devel::hdb::HOST || '127.0.0.1', @_);

    my $self = bless {}, $class;

    $server_params{'port'} = $Devel::hdb::PORT if defined $Devel::hdb::PORT;

    $self->{server} = Devel::hdb::Server->new(
                        %server_params,
                        server_ready => sub { $self->init_debugger },
                    );
    $self->{json} = JSON->new();

    $parent_pid = eval { getppid() } if ($Devel::hdb::TESTHARNESS);
    return $self;
}

sub init_debugger {
    my $self = shift;

    if ($parent_pid and !kill(0, $parent_pid)) {
        # The parent PID for testing is gone
        exit();
    }

    return if $self->{__init__};

    $self->{__init__} = 1;

    # HTTP::Server::PSGI doesn't have a method to get the listen socket :(
    my $s = $self->{server}->{listen_sock};
    #$self->{base_url} = sprintf('http://%s:%d/%d/',
    #        $s->sockhost, $s->sockport, $$);
    $self->{base_url} = sprintf('http://%s:%d/',
            $s->sockhost, $s->sockport);

    select STDOUT;
    local $| = 1;
    print "Debugger listening on ",$self->{base_url},"\n";

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
    }
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
        $writer->write($json->encode({ type => 'hangup' }));
        $writer->close();
        exit();
    };
}

sub _resp {
    my $self = shift;
    return Devel::hdb::App::Response->new(@_);
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
    my $eval_string = $DB::eval_string = $req->content();

    my $resp = $self->_resp('evalresult', $env);

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
                    $data->{expr} = $eval_string;
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
        } elsif ($reftype eq 'SCALAR') {
            $value = $self->_encode_eval_data($$value);
        } elsif ($reftype eq 'CODE') {
            (my $copy = $value.'') =~ s/^(\w+)\=//;  # Hack to change CodeClass=CODE(0x123) to CODE=(0x123)
            $value = $copy;
        } elsif ($reftype eq 'REF') {
            $value = $self->_encode_eval_data($$value);
        } elsif ($reftype eq 'REGEXP') {
            $value = $value . '';
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

# Get the value of a variable, possibly in an upper stack frame
sub do_getvar {
    my($self, $env) = @_;
    my $req = Plack::Request->new($env);
    my $level = $req->param('l');
    my $varname = $req->param('v');

    my $resp = $self->_resp('getvar', $env);
    my $adjust = DB->_first_program_frame();
    my $value = eval { DB->get_var_at_level($varname, $level + $adjust) };

    if ($@) {
        if ($@ =~ m/Can't locate PadWalker/) {
            $resp->{type} = 'error';
            $resp->data('Not implemented - PadWalker module is not available');

        } elsif ($@ =m/Not nested deeply enough/) {
            $resp->data( { expr => $varname, level => $level, result => undef } );
        } else {
            die $@;
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
# Make c=1 for an unconditional bp, c=0 to clear it
sub set_breakpoint {
    my($self, $env) = @_;
    my $req = Plack::Request->new($env);
    my $filename = $req->param('f');
    my $line = $req->param('l');
    my $condition = $req->param('c');
    my $action = $req->param('a');

    if (! DB->is_loaded($filename)) {
        return [ 404, ['Content-Type' => 'text/html'], ["$filename is not loaded"]];
    } elsif (! DB->is_breakable($filename, $line)) {
        return [ 403, ['Content-Type' => 'text/html'], ["line $line of $filename is not breakable"]];
    }

    my $resp = $self->_resp('breakpoint', $env);

    my $params = $req->parameters;
    my %req;
    $req{condition} = $condition if (exists $params->{'c'});
    $req{action} = $action if (exists $params->{'a'});

    DB->set_breakpoint($filename, $line, %req);

    $resp->data( DB->get_breakpoint($filename, $line) );

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $resp->encode() ]
          ];
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

    $DB::single=0;
    return $self->_delay_stack_return_to_client(@_);
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

        my @messages;
        DB->long_call( sub {
            if (@_) {
                # They want to send additional messages
                push @messages, shift;
                return;
            }
            # Purposefully not using a response object since we can't encode a list of them
            unshift @messages, { type => 'stack', rid => $rid, data => $self->_stack };
            $writer->write($json->encode(\@messages));
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

sub encode {
    my $self = shift;

    my %copy = map { exists($self->{$_}) ? ($_ => $self->{$_}) : () } keys %$self;
    return JSON::encode_json(\%copy);
}

sub data {
    my $self = shift;
    if (@_) {
        $self->{data} = shift;
    }
    return $self->{data};
}

1;
