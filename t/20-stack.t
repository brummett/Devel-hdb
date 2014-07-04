use strict;
use warnings;

use lib 't';
use HdbHelper;
use Devel::hdb::Client;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 31;
}

my $url = start_test_program();
my $client = Devel::hdb::Client->new(url => $url);

my $resp = $client->continue();
ok($resp, 'continue to breakpoint');
my $filename = $resp->{filename};

my $stack = $client->stack();

my @expected = (
    {   package     => 'Bar',
        filename    => $filename,
        subroutine  => 'Bar::baz',
        line        => 15,
        hasargs     => 1,
        wantarray   => 1,
        evaltext    => undef,
        evalfile    => undef,
        evalline    => undef,
        is_require  => undef,
        autoload    => undef,
        subname     => 'baz',
        args        => [],
        href        => '/stack/0',
    },
    {   package     => 'Bar',
        filename    => qr/\(eval \d+\)\[$filename:10\]/,
        subroutine  => qr/\(eval\)/,
        line        => 1,          # It's line 1 if the eval-ed text
        hasargs     => 0,
        wantarray   => 1,
        evaltext    => "baz();",
        evalfile    => $filename,
        evalline    => 10,
        is_require  => '',     # false but not undef because it is a string eval
        autoload    => undef,
        subname     => qr/\(eval\)/,
        args        => [],
        href        => '/stack/1',
    },
    {   package     => 'Bar',
        filename    => $filename,
        subroutine  => '(eval)',
        line        => 10,
        hasargs     => 0,
        wantarray   => 1,
        evaltext    => undef,
        evalfile    => undef,
        evalline    => undef,
        is_require  => undef,
        autoload    => undef,
        subname     => qr/\(eval\)/,
        args        => [],
        href        => '/stack/2',
    },
    {   package     => 'Bar',
        filename    => $filename,
        subroutine  => 'Bar::bar',
        line        => 9,
        hasargs     => 1,
        wantarray   => 1,
        evaltext    => undef,
        evalfile    => undef,
        evalline    => undef,
        is_require  => undef,
        autoload    => undef,
        subname     => 'bar',
        args        => [],
        href        => '/stack/3',
    },
    {   package     => 'main',
        filename    => $filename,
        subroutine  => 'main::foo',
        line        => 4,
        hasargs     => 1,
        wantarray   => undef,
        evaltext    => undef,
        evalfile    => undef,
        evalline    => undef,
        is_require  => undef,
        autoload    => undef,
        subname     => 'foo',
        args        => [1,2,3],
        href        => '/stack/4',
    },
    {   package     => 'main',
        filename    => $filename,
        subroutine  => 'main::MAIN',
        line        => 1,
        hasargs     => 1,
        wantarray   => undef,
        evaltext    => undef,
        evalfile    => undef,
        evalline    => undef,
        is_require  => undef,
        autoload    => undef,
        subname     => 'MAIN',
        args        => [],
        href        => '/stack/5',
    },
);
for (my $i = 0; $i < @expected; $i++) {
    delete $stack->[$i]->{hints};
    delete $stack->[$i]->{bitmask};
    delete $stack->[$i]->{level};

    my $uuid = delete $stack->[$i]->{uuid};
    my $expected_defined_uuid = $i == $#expected ? '' : 1;
    is(defined($uuid), $expected_defined_uuid, "Frame $i has uuid");

    _compare_frames($stack->[$i], $expected[$i], $i);
}

sub _compare_frames {
    my($frame, $expected, $level) = @_;

    _compare_strings(   delete $frame->{subroutine},
                        delete $expected->{subroutine},
                        "subroutine matches for level $level");

    _compare_strings(   delete $frame->{subname},
                        delete $expected->{subname},
                        "subname matches for level $level");

    _compare_strings(   delete $frame->{filename},
                        delete $expected->{filename},
                        "filename matches for level $level");

    is_deeply($frame,
                $expected,
                "Other stack frame matches for frame $level");
}


sub _compare_strings {
    my($got, $expected, $message) = @_;
    if (ref $expected) {
        like($got, $expected, $message);
    } else {
        is($got, $expected, $message);
    }
}

__DATA__
foo(1,2,3);             # 1

sub foo {
    @a = Bar::bar();    # 4
}

package Bar;
sub bar {
    eval {              # 9
        eval "baz();";  # 10
    }
}
sub baz {
    $DB::single = 1;
    15;
}
