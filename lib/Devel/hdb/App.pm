use warnings;
use strict;

package Devel::hdb::App;

BEGIN {
    our $PROGRAM_NAME = $0;
}

use Devel::hdb::Server;
use Plack::Request;
use Sub::Install;
use IO::File;
use JSON qw();
use Data::Dumper;

use Devel::hdb::Router;

use vars qw( $parent_pid ); # when running in the test harness

sub new {
    my $class = shift;
    my %server_params = (host => '127.0.0.1', @_);

    my $self = bless {}, $class;

    $server_params{'port'} = $Devel::hdb::PORT if defined $Devel::hdb::PORT;

    $self->{server} = Devel::hdb::Server->new(
                        %server_params,
                        server_ready => sub { $self->init_debugger },
                    );
    $self->{json} = JSON->new();

    $parent_pid = getppid() if ($Devel::hdb::TESTHARNESS);
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
        $_->get("/exit", sub { $self->do_terminate(@_) });
    }
}

sub encode {
    my $self = shift;
    return $self->{json}->encode(shift);
}

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

# sets a breakpoint on line l of file f with condition c
# Make c=1 for an unconditional bp, c=0 to clear it
sub set_breakpoint {
    my($self, $env) = @_;
    my $req = Plack::Request->new($env);
    my $filename = $req->param('f');
    my $line = $req->param('l');
    my $condition = $req->param('c');

    if (! DB->is_loaded($filename)) {
        return [ 404, ['Content-Type' => 'text/html'], ["$filename is not loaded"]];
    } elsif (! DB->is_breakable($filename, $line)) {
        return [ 403, ['Content-Type' => 'text/html'], ["line $line of $filename is not breakable"]];
    }

    DB->set_breakpoint($filename, $line, $condition);

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $self->encode({   type => 'breakpoint',
                                data => {
                                    filename => $filename,
                                    lineno => $line,
                                    condition => $condition,
                                }
                            }) ]];
}

sub get_breakpoint {
    my($self, $env) = @_;
    my $req = Plack::Request->new($env);
    my $filename = $req->param('f');
    my $line = $req->param('l');

    my $condition = DB->get_breakpoint($filename, $line);
    return [ 200, ['Content-Type' => 'application/json'],
            [ $self->encode({   type => 'breakpoint',
                                data => {
                                    filename => $filename,
                                    lineno => $line,
                                    condition => $condition,
                                }
                            }) ]];
}

# Return the name of the program, $o
sub program_name {
    our $PROGRAM_NAME;
    return [200, ['Content-Type' => 'text/plain'],
                [ shift->encode({   type => 'program_name',
                                    data => $PROGRAM_NAME }) ]];
}


# send back a list.  Each list elt is a list of 2 elements:
# 0: the line of code
# 1: whether that line is breakable
sub sourcefile {
    my($self, $env) = @_;
    my $req = Plack::Request->new($env);

    my $filename = $req->param('f');
    my $file;
    {
        no strict 'refs';
        $file = $main::{'_<' . $filename};
    }

    my @rv;
    {
        no warnings 'uninitialized';  # at program termination, the loaded file data can be undef
        my $offset = $file->[0] =~ m/use\s+Devel::_?hdb;/ ? 1 : 0;

        for (my $i = $offset; $i < scalar(@$file); $i++) {
            push @rv, [ $file->[$i], $file->[$i] + 0 ];
        }
    }

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $self->encode({   type => 'sourcefile',
                                data => {
                                    filename => $filename,
                                    lines => \@rv,
                                }
                            }) ]];
}

# Send back a data structure describing the call stack
# stepin, stepover, stepout and run will call this to return
# back to the debugger window the current state
sub _stack {

    my $discard = 1;
    my @stack;
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

#        $caller{args} = \@DB::args;
        $caller{subname} = $caller{subroutine} =~ m/\b(\w+$|__ANON__)/ ? $1 : $caller{subroutine};
        $caller{level} = $i;

        push @stack, \%caller;
    }
    # TODO: put this into the above loop
    for (my $i = 0; $i < @stack-1; $i++) {
        @{$stack[$i]}{'subroutine','subname'} = @{$stack[$i+1]}{'subroutine','subname'};
    }
    $stack[-1]->{subroutine} = 'MAIN';
    $stack[-1]->{subname} = 'MAIN';

    return \@stack;
}

sub stack {
    my($self, $env) = @_;

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $self->encode({   type => 'stack',
                                data => $self->_stack }) ]];
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

sub continue {
    my $self = shift;

    $DB::single=0;
    return $self->_delay_stack_return_to_client(@_);
}

sub _delay_stack_return_to_client {
    my $self = shift;
    my $env = shift;

    my $json = $self->{json};
    return sub {
        my $responder = shift;
        my $writer = $responder->([ 200, [ 'Content-Type' => 'text/html' ]]);
        $env->{'psgix.harakiri.commit'} = Plack::Util::TRUE;

        my @messages;
        DB->long_call( sub {
            if (@_) {
                # They want to send additional messages
                push @messages, shift;
                return;
            }
            unshift @messages, { type => 'stack', data => $self->_stack };
            $writer->write($json->encode(\@messages));
            $writer->close();
        });
    };
}

sub app {
    my $self = shift;
    unless ($self->{app}) {
        #$self->{app} =  sub { print "run route for ".Data::Dumper::Dumper($_[0]);$self->{router}->route(@_); };
        $self->{app} =  sub { $self->{router}->route(@_); };
    }
    return $self->{app};
}

sub run {
    my $self = shift;
    return $self->{server}->run($self->app);
}

# methods to get vars of the same name out of the DB package
# scalars
foreach my $m ( qw( filename line stack_depth ) ) {
    no strict 'refs';
    Sub::Install::install_sub({
        as => $m,
        code => sub { return ${ 'DB::'. $m} }
    });
}


1;
