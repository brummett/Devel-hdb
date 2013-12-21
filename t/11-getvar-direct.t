use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;

use Test::More tests => 28;

use_ok('Devel::hdb::DB::GetVarAtLevel');
*get_var_at_level = \&Devel::hdb::DB::GetVarAtLevel::get_var_at_level;

test_vars();

sub is_var {
    my($varname, $level, $expected, $msg) = @_;
    my $got = get_var_at_level($varname, $level+1);
    if (ref $expected) {
        is_deeply($got, $expected, $msg);
    } else {
        is($got, $expected, $msg);
    }
}

sub test_vars {
    our $our_var = 'ourvar';
    no strict 'vars';
    no warnings 'once';
    @bare_var = ('barevar', 'barevar');
    use strict 'vars';
    $Other::Package::variable = 'pkgvar';
    my $x = 1;
    my $y = 2;
    my $test_vars_2 = sub {
        my $x = 'hello',
        my $z = { one => 1, two => 2 };
        my $zero = 0;
        my $one = 1;
        my $two = 2;
        my @my_list = (0,1,2);
        my %my_hash = (1 => 'one', 2 => 'two', 3 => 'three');
        do_test_vars();
    };
    $test_vars_2->();
}

sub do_test_vars {
    my $x = 'goodbye';

    is_var('$x', 0, 'goodbye', 'Get value of $x at this level');
    is_var('$y', 0, undef, '$y is not available at this level');

    is_var('$x', 1, 'hello', 'Get value of $x one level up');
    is_var('$y', 1, 2, 'Get value of $y one level up');
    is_var('$z', 1,
            { one => 1, two => 2 },
            'Get value of $z one level up');

    is_var('$our_var', 1, 'ourvar', 'Get value of $our_var one level up');
    is_var('@bare_var', 1,
            ['barevar','barevar'],
            'Get value of bare pkg var @bare_var one level up');

    is_var('$Other::Package::variable', 1, 'pkgvar',
        'Get value of pkg global $Other::Package::variable one level up');
    is_var('@my_list', 1, [ 0,1,2 ], 'Get value of my var @my_list one level up');

    is_var('$x', 2, 1, 'Get value of $x two levels up');
    is_var('$y', 2, 2, 'Get value of $y two levels up');
    is_var('$z', 2, undef, '$z is not available two levels up');
    is_var('$our_var', 2, 'ourvar', 'Get value of our var $our_var two levels up');
    is_var('@bare_var', 2,
            ['barevar', 'barevar'],
            'Get value of bare package var @bare_var two levels up');
    is_var('$Other::Package::variable', 2, 'pkgvar',
            'Get value of pkg global $Other::Package::variable two levels up');

    is_var('$my_list[1]', 1, 1, 'Get value of $my_list[1] one level up');
    is_var('$my_list[$one]', 1, 1, 'Get value of $my_list[$one] one level up');
    is_var('@my_list[1, $two]', 1, [1, 2], 'Get value of my var @my_list[1, $two] one level up');
    is_var('@my_list[$zero..3]', 1, [0,1,2,undef],
            'Get value of my var @my_list[$zero..3] two levels up');

    is_var('$my_hash{1}', 1, 'one', 'Get value of $my_hash{1} one level up');
    is_var('@my_hash{1,2}', 1, ['one','two'],
            'Get value of @my_hash{1,2} one level up');
    is_var('@my_hash{$one,2}', 1, ['one','two'],
            'Get value of @my_hash{$one,2} one level up');
    is_var('@my_hash{@my_list, 2}', 1,
            [undef,'one','two','two'],
            'Get value of @my_hash{@my_list,2} one level up');
    is_var('@my_hash{$one,"2"}', 1, ['one','two'],
            'Get value of @my_hash{"1","2"} one level up');
    is_var('@my_hash{qw( 1 2 )}', 1, ['one','two'],
            'Get value of @my_hash{$one,2} one level up');

    test_sub_args(1,2,3);
}

sub test_sub_args {
    is_var('@_', 0, [1,2,3], 'Get @_ at this level');
    eval { is_var('@_', 0, [1,2,3], 'Get @_ at this level inside eval'); };
}

