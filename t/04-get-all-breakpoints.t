use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 14;
}

my $url = start_test_program();

my $json = JSON->new();
my $stack;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'stack');
ok($resp->is_success, 'Request stack position');
$stack = $json->decode($resp->content);
my $filename = $stack->{data}->[0]->{filename};
$stack = strip_stack($stack);
is_deeply($stack,
    [ { line => 3, subroutine => 'main::MAIN' } ],
    'Stopped on line 3');

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 3, c => 1});
ok($resp->is_success, 'Set breakpoint for line 3');

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 4, c => 1});
ok($resp->is_success, 'Set breakpoint for line 4');

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 5, c => 1 });
ok($resp->is_success, 'Set breakpoint and action for line 5');

$resp = $mech->post("${url}breakpoint", { f => 't/TestNothing.pm', l => 3, c => 1});
ok($resp->is_success, 'Set breakpoint for line TestNothing.pm 3');

$resp = $mech->get('breakpoints');
ok($resp->is_success, 'Get all breakpoints');
my @bp = sort { $a->{data}->{filename} cmp $b->{data}->{filename}
                    or
                $a->{data}->{lineno} <=> $b->{data}->{lineno} }
        @{ $json->decode($resp->content)};
is_deeply( \@bp,
    [
      {     type => 'breakpoint',
            data => { filename => $filename, lineno => 3, code => 1 } },
      {     type => 'breakpoint', 
            data => { filename => $filename, lineno => 4, code => 1 } },
      {     type => 'breakpoint',
            data => { filename => $filename, lineno => 5, code => 1 } },
      {     type => 'breakpoint',
            data => { filename => 't/TestNothing.pm', lineno => 3, code => 1 } },
    ],
    'Got all set breakpoints'
);

$resp = $mech->get('breakpoints?f='.$filename);
ok($resp->is_success, 'Get all breakpoints for main file');
@bp = sort { $a->{data}->{lineno} <=> $b->{data}->{lineno} } @{ $json->decode($resp->content)};
is_deeply( \@bp,
    [
      {     type => 'breakpoint',
            data => { filename => $filename, lineno => 3, code => 1 } },
      {     type => 'breakpoint',
            data => { filename => $filename, lineno => 4, code => 1 } },
      {     type => 'breakpoint',
            data => { filename => $filename, lineno => 5, code => 1 } }
    ],
    'Got all set breakpoints'
);

$resp = $mech->get("${url}delete-breakpoint?f=${filename}&l=4");
ok($resp->is_success, 'Remove breakpoint for line 4');
is_deeply($json->decode($resp->content),
    { type => 'delete-breakpoint', data => { filename => $filename, lineno => 4 }},
    'delete response is ok');

$resp = $mech->get('breakpoints?f='.$filename);
ok($resp->is_success, 'Get all breakpoints for main file');
@bp = sort { $a->{data}->{lineno} <=> $b->{data}->{lineno} } @{ $json->decode($resp->content)};
is_deeply( \@bp,
    [
      {     type => 'breakpoint',
            data => { filename => $filename, lineno => 3, code => 1 } },
      {     type => 'breakpoint',
            data => { filename => $filename, lineno => 5, code => 1 } }
    ],
    'Got all set breakpoints'
);



__DATA__
use lib 't';
use TestNothing;
1;
foo();
3;
sub foo {
    5;
}
