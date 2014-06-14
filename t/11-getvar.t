use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 33;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp = $client->continue();
is($resp->{line}, 22, 'continue to breakpoint');

check_value('$x', 0, 'hello');

check_value('$y', 0, 2);

check_value('$z', 0, { one => 1, two => 2 });

check_value('$our_var', 0, 'ourvar');

check_value('@bare_var', 0, ['barevar', 'barevar']);

check_value('@_', 0, [1, 2, 3]);

check_value('$_[1]', 0, 2);

check_value('$Other::Package::variable', 0, 'pkgvar');

check_value('@my_list', 0, [0,1,2]);

check_value('$x', 1, 1);

check_value('$y', 1, 2);

check_value('$z', 1, undef);

check_value('$our_var', 1, 'ourvar');

check_value('@bare_var', 1, ['barevar', 'barevar']);

check_value('$Other::Package::variable', 1, 'pkgvar');

check_value('$my_list[1]', 0, 1);

check_value('$my_list[$one]', 0, 1);

check_value('@my_list[1, $two]', 0, [1, 2]);

check_value('@my_list[$zero..3]', 0, [0,1,2,undef]);

check_value(q($my_hash{1}), 0, 'one');

check_value(q(@my_hash{1,2}), 0, ['one','two']);

check_value(q(@my_hash{$one,2}), 0, ['one','two']);

check_value(q(@my_hash{@my_list, 2}), 0, [undef,'one','two','two']);

check_value(q(@my_hash{'1', 2}), 0, ['one','two']);

check_value(q(@my_hash{qw(2 1 )}), 0, ['two','one']);

check_value('$@', 0, "hi there\n");

check_value('$$', 0, $HdbHelper::child_pid);

check_value('$1', 0, 'b');

check_value('$^L', 0, 'aaa');

check_value('@_', 0, [1, 2, 3]);

my $expected = { one => 1, two => 2, subhash => { subkey => 1 } };
$expected->{subhash}->{recursive} = $expected->{subhash};
check_value('%recursive', 0, $expected);

check_value('$vstring', 0, v1.2.3.4);

sub check_value {
    my $varname = shift;
    my $level = shift;
    my $expected = shift;

    my $val = $client->get_var_at_level($varname, $level);
    if (ref $expected) {
        is_deeply($val, $expected, "Get value of $varname at level $level");
    } else {
        is($val, $expected, "Get value of $varname at level $level");
    }
}


__DATA__
our $our_var = 'ourvar';
@bare_var = ('barevar', 'barevar');
$Other::Package::variable = 'pkgvar';
my $x = 1;
my $y = 2;
foo(1,2,3);
sub foo {
    my $x = 'hello',
    my $z = { one => 1, two => 2 };
    my $zero = 0;
    my $one = 1;
    my $two = 2;
    my @my_list = (0,1,2);
    my %my_hash = (1 => 'one', 2 => 'two', 3 => 'three');
    my %recursive = ( one => 1, two => 2, subhash => { subkey => 1 } );
    $recursive{subhash}->{recursive} = $recursive{subhash};
    my $vstring = v1.2.3.4;
    local($^L) = 'aaa';
    "abc" =~ m/^\w(\w)/;
    eval { die "hi there\n" };
    $DB::single=1;
    8;
}
