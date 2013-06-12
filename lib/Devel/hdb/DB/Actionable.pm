package Devel::hdb::DB::Actionable;

use strict;
use warnings;

use Digest::MD5 qw(md5);
use List::Util;
use Carp;

sub _new {
    my $class = shift;

    my %params = __required([qw(file line code type)], @_);

    my $self = \%params;
    bless $self, $class;
    $self->_insert();
    return $self;
}

sub __required {
    my $required_params = shift;
    my %params = @_;
    do { defined($params{$_}) || Carp::croak("$_ is a required param") }
        foreach @$required_params;
    return %params;
}

sub _get {
    my $class = shift;
    return $class if (ref $class);

    my %params = __required([qw(file type)], @_);

    our %dbline;
    local(*dbline) = $main::{'_<' . $params{file}};
    return unless %dbline;

    my @candidates;

    my $type = $params{type};
    if (!$params{line}) {
        @candidates =
              map { $_->{$type} ? @{$_->{$type}} : () } # only lines with the type we're looking for
              grep { $_ }      # only lines with something
              values %dbline;  # All action/breakpoint data for this file
    } else {
        my $line = $params{line};
        @candidates = ($dbline{$line} && $dbline{$line}->{$type})
                    ? @{ $dbline{$line}->{$type}}
                    : ();
    }
            
    if ($params{code}) {
        @candidates = grep { $_->{code} eq $params{code} }
                        @candidates;
    }

    return @candidates;
}

sub _insert {
    my $self = shift;

    # Setting items in the breakpoint hash only gets
    # its magical DB-stopping abilities if you're in
    # pacakge DB.  Otherwise, you can alter the breakpoint
    # data, other users will see them, but the debugger
    # won't stop
    package DB;
    our %dbline;
    local(*dbline) = $main::{'_<' . $self->file};

    my $bp_info = $dbline{$self->line} ||= {};
    my $type = $self->type;
    $bp_info->{$type} ||= [];
    push @{$bp_info->{$type}}, $self;
}

sub _id {
    my $self = shift;
    md5(join('', @$self{'file', 'line', 'code', 'type'}));
}

sub _delete {
    my $self = shift;

    my($file, $line, $code, $type, $self_ref);
    if (ref $self) {
        ($file, $line, $code, $type) = map { $self->$_ } qw(file line code type);
        $self_ref = $self . '';
    } else {
        my %params = __required([qw(file line code type)], @_);
        ($file, $line, $code, $type) = @params{'file','line','code','type'};
    }

    our %dbline;
    local(*dbline) = $main::{'_<' . $file};
    my $bp_info = $dbline{$line};
    return unless ($bp_info && $bp_info->{$type});

    my $bp_list = $bp_info->{$type};
    for (my $i = 0; $i < @$bp_list; $i++) {
        my($its_file, $its_line, $its_code) = map { $bp_list->[$i]->$_ } qw(file line code);
        if ($file eq $its_file
            and
            $line == $its_line
            and
            $code eq $its_code
            and
            ( defined($self_ref) ? $self_ref eq $bp_list->[$i] : 1 )
        ) {
            splice(@$bp_list, $i, 1);
            last;
        }
    }

    if (! @$bp_list) {
        # last breakpoint/action removed for this line
        delete $bp_info->{$type};
    }

    if (! %$bp_info) {
        # No breakpoints or actions left on this line
        $dbline{$line} = undef;
    }
}

 
sub file    { return shift->{file} }
sub line    { return shift->{line} }
sub code    { return shift->{code} }
sub type    { return shift->{type} }
sub once    { return shift->{once} }

sub inactive {
    my $self = shift;
    if (@_) {
        $self->{inactive} = shift;
    }
    return $self->{inactive};
}

package Devel::hdb::DB::Breakpoint;

use base 'Devel::hdb::DB::Actionable';

sub new {
    shift->SUPER::_new(@_, type => 'condition');
}

sub delete {
    shift->SUPER::_delete(@_, type => 'condition');
}

sub get {
    shift->SUPER::_get(@_, type => 'condition');
}


package Devel::hdb::DB::Action;

use base 'Devel::hdb::DB::Actionable';

sub new {
    shift->SUPER::_new(@_, type => 'action');
}

sub delete {
    shift->SUPER::_delete(@_, type => 'action');
}

sub get {
    shift->SUPER::_get(@_, type => 'action');
}

1;


