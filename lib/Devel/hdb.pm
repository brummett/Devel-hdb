use warnings;
use strict;

package Devel::hdb;

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

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    $self->{server} = Devel::hdb::Server->new(
                        host => '127.0.0.1',
                        server_ready => sub { $self->init_debugger },
                    );
    $self->{json} = JSON->new();
    return $self;
}

sub init_debugger {
    my $self = shift;
    return if $self->{__init__};

    $self->{__init__} = 1;

    # HTTP::Server::PSGI doesn't have a method to get the listen socket :(
    my $s = $self->{server}->{listen_sock};
    #$self->{base_url} = sprintf('http://%s:%d/%d/',
    #        $s->sockhost, $s->sockport, $$);
    $self->{base_url} = sprintf('http://%s:%d/',
            $s->sockhost, $s->sockport);
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


package DB;
no strict;

use vars qw( %dbline @dbline );

BEGIN {
    $DB::stack_depth    = 0;
    $DB::single         = 0;
    $DB::step_over_depth = -1;
    $DB::dbobj          = undef;
    $DB::ready          = 0;
    @DB::stack          = ();
    $DB::deep           = 100;
    @DB::saved          = ();
    $DB::usercontext    = '';
    $DB::in_debugger    = 0;
    # These are set from caller inside DB::DB()
    $DB::package        = '';
    $DB::filename       = '';
    $DB::line           = '';

    # Controlling program end of life
    $DB::finished       = 0;
    $DB::user_requested_quit = 0;

    # Used to postpone some action between calls to DB::DB:
    $DB::long_call      = undef;
}

#sub stack_depth {
#    my $class = shift;
#    $stack_depth = shift if (@_);
#    return $stack_depth;
#}
#
#sub step_over_depth {
#    my $class = shift;
#    $step_over_depth = shift if (@_);
#    return $step_over_depth;
#}
#
#sub single {
#    my $class = shift;
#    $single = shift if (@_);
#    return $single;
#}

sub save {
    # Save eval failure, command failure, extended OS error, output field
    # separator, input record separator, output record separator and
    # the warning setting.
    @saved = ( $@, $!, $^E, $,, $/, $\, $^W );

    $,  = "";      # output field separator is null string
    $/  = "\n";    # input record separator is newline
    $\  = "";      # output record separator is null string
    $^W = 0;       # warnings are off
}

sub restore {
    ( $@, $!, $^E, $,, $/, $\, $^W ) = @saved;
}

sub is_breakpoint {
    my($package, $filename, $line) = @_;

    if ($single and $step_over_depth >= 0 and $step_over_depth < $stack_depth) {
        # This is from a step-over
        $single = 0;
        return 0;
    }

    if ($single || $signal) {
        $single = $signal = $tracking_step_over = 0;
        return 1;
    }

    local(*dbline) = $main::{'_<' . $filename};

    if ($dbline{$line}) {
        my($is_break) = split("\0", $dbline{$line});
        if ($is_break eq '1') {
            return 1
        } else {
            # eval $is_break in user's context here
        }
    }
    return;
}

sub DB {
    return unless $ready;

    local($package, $filename, $line) = caller;

    if (! is_breakpoint($package, $filename, $line)) {
        return;
    }
    $step_over_depth = -1;
    $DB::saved_stack_depth = $stack_depth;

    # set up the context for DB::eval, so it can properly execute
    # code on behalf of the user. We add the package in so that the
    # code is eval'ed in the proper package (not in the debugger!).
    if ($package eq 'DB::fake') {
        $package = 'main';
    }
    local $usercontext =
        '($@, $!, $^E, $,, $/, $\, $^W) = @saved;' . "package $package;";

    if ($DB::long_call) {
        $DB::long_call->();
        undef $DB::long_call;
    }
    unless ($dbobj) {
        $dbobj = Devel::hdb->new();
    }
    do {
        local($in_debugger) = 1;
        $dbobj->run();
    } while ($finished);
}

sub sub {
    goto &$sub if (! $ready or index($sub, 'hdbStackTracker') == 0);

    my $stack_tracker;
    unless ($in_debugger) {
        my $tmp = $sub;
        $stack_depth++;
        if ($step_over_depth >= 0 and $step_over_depth < $stack_depth) {
            $stack_tracker = \$tmp;
            bless $stack_tracker, 'hdbStackTracker';
        }
    }

    return &$sub;
}

sub hdbStackTracker::DESTROY {
    $DB::stack_depth--;
    $DB::single = 1 if ($DB::step_over_depth > 0 and $DB::step_over_depth >= $stack_depth);
}

sub set_breakpoint {
    my($class, $filename, $line, $condition) = @_;

    local(*dbline) = $main::{'_<' . $filename};

    no warnings 'uninitialized';
    my(undef, $action) = split("\0", $dbline{$line});
    if ($action) {
        $dbline{$line} = "${condition}\0${action}";
    } else {
        $dbline{$line} = $condition;
    }

    return 1;
}

sub get_breakpoint {
    my($class, $filename, $line) = @_;

    no strict 'refs';
    local(*dbline) = $main::{'_<' . $filename};

    my($condition, $action) = split("\0", $dbline{$line});
    return $condition;
}

sub long_call {
    my($class, $cb) = @_;
    $DB::long_call = $cb;
}

sub user_requested_exit {
    $user_requested_exit = 1;
}

END {
    $single=0;
    $finished = 1;
    print "Debugged program terminated with exit code $?\n";

    if ($long_call) {
        if ($user_requested_exit) {
            $long_call->({ type => 'hangup'});
        } else {
            $long_call->({ type => 'termination', data => { exit_code => $? }});
            $exit_code = $?;
            # These two will trigger DB::DB and the event loop
            $single=1;
            DB::fake::at_exit();
        }
    }
}

package DB::fake;
sub at_exit {
    1;
}

package DB;
BEGIN { $DB::ready = 1; }

1;
