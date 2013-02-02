use warnings;
use strict;

package Devel::hdb;

use HTTP::Server::PSGI;
use Sub::Install;

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    $self->{server} = HTTP::Server::PSGI->new(
                        host => '127.0.0.1',
                        server_ready => sub { $self->print_listen_socket_to_stdout },
                    );

    return $self;
}

sub print_listen_socket_to_stdout {
    my $self = shift;
    return if $self->{announced};

    $self->{announced} = 1;

    # HTTP::Server::PSGI doesn't have a method to get the listen socket :(
    my $s = $self->{server}->{listen_sock};
    printf("Debugger listening on http://%s:%d/%d\n",
            $s->sockhost, $s->sockport, $$);
}

sub _app {
    my $self = shift;
    my $env = shift;

    my $string = '';
    $string .= 'Env <pre>'.Data::Dumper::Dumper($env).'</pre>';
    $string .= sprintf("<h2>Line %d of %s.  Depth %d</h2>",
                        $self->line, $self->filename, $self->stack_depth);
    $string .= "<table>";
    my $file = $self->source_file($self->filename);
    for (my $lineno = 0; $lineno < @$file; $lineno++) {
        $string .= sprintf("<tr><td>%s</td><td><pre>%s</pre></td></tr>",
                            ($lineno + 1 == $self->line) ? $lineno+1 . ' ==>' : $lineno+1,
                            $file->[$lineno]);
    }
    $string .= "</table>";

    $env->{'psgix.harakiri.commit'} = Plack::Util::TRUE;
    return [    200,
                [ 'Content-Type' => 'text/html' ],
                [ $string ]
            ];
}

sub app {
    my $self = shift;
    unless ($self->{app}) {
        $self->{app} =  sub { unshift @_, $self; &_app; };
    }
    return $self->{app};
}

sub run {
    my $self = shift;
    return $self->{server}->run($self->app);
}

# Return a ref to the list of file content data
sub source_file {
    my($self, $filename) = @_;

    no strict 'refs';
    return $main::{'_<' . $filename};
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

BEGIN {
    $DB::stack_depth    = 0;
    $DB::single         = 0;
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

    $DB::dbline         = ();
}

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

sub DB {
    return unless $ready;
    #return if (! $ready || $in_debugger);

    local $in_debugger = 1;

    local($package, $filename, $line) = caller;

    # set up the context for DB::eval, so it can properly execute
    # code on behalf of the user. We add the package in so that the
    # code is eval'ed in the proper package (not in the debugger!).
    local $usercontext =
        '($@, $!, $^E, $,, $/, $\, $^W) = @saved;' . "package $package;";

    # Create an alias to the active file magical array to simplify
    # the code here.
    local (*dbline) = $main::{ '_<' . $filename };

    #$dbobj = Devel::hdb->new() unless $dbobj;
    unless ($dbobj) {
        print "Creating new dbobj\n";
        $dbobj = Devel::hdb->new();
    }
    $dbobj->run();

}

sub sub {
    &$sub unless $ready;
    #&$sub if (! $ready || $in_debugger);

    # Using the same trick perl5db uses to preserve the single step flag
    # even in the cse where multiple stack frames are unwound, as in an
    # an eval that catches an exception thrown many sub calls down
    local $stack_depth = $stack_depth;
    unless ($in_debugger) {
        $stack_depth++;
        $#stack = $stack_depth;
        $stack[-1] = $single;
    }

    # Turn off all flags except single-stepping
    $single &= 1;

    # If we've gotten really deeply recursed, turn on the flag that will
    # make us stop with the 'deep recursion' message.
    $single |= 4 if $stack_depth == $deep;

    my(@ret,$ret);
    my $wantarray = wantarray;
    {
        no strict 'refs';
        if ($wantarray) {
            @ret = &$sub;
        } elsif (defined $wantarray) {
            $ret = &$sub;
        } else {
            &$sub;
            undef $ret;
        }
    }

    unless ($in_debugger) {
        $single |= $stack[ $stack_depth-- ];
    }

    return $wantarray ? @ret : $ret;
}

BEGIN { $DB::ready = 1; }
END { $DB::ready = 0; }

1;
