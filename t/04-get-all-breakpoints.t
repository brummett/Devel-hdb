use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;

use Test::More tests => 13;

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
    [ { line => 3, subroutine => 'MAIN' } ],
    'Stopped on line 3');

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 3, c => 1});
ok($resp->is_success, 'Set breakpoint for line 3');

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 4, c => 1});
ok($resp->is_success, 'Set breakpoint for line 4');

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 5, c => 1, a => '$global = 1'});
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
            data => { filename => $filename, lineno => 3, condition => 1 } },
      {     type => 'breakpoint', 
            data => { filename => $filename, lineno => 4, condition => 1 } },
      {     type => 'breakpoint',
            data => { filename => $filename, lineno => 5, condition => 1, action => '$global = 1' } },
      {     type => 'breakpoint',
            data => { filename => 't/TestNothing.pm', lineno => 3, condition => 1 } },
    ],
    'Got all set breakpoints'
);

$resp = $mech->get('breakpoints?f='.$filename);
ok($resp->is_success, 'Get all breakpoints for main file');
@bp = sort { $a->{data}->{lineno} <=> $b->{data}->{lineno} } @{ $json->decode($resp->content)};
is_deeply( \@bp,
    [
      {     type => 'breakpoint',
            data => { filename => $filename, lineno => 3, condition => 1 } },
      {     type => 'breakpoint',
            data => { filename => $filename, lineno => 4, condition => 1 } },
      {     type => 'breakpoint',
            data => { filename => $filename, lineno => 5, condition => 1, action => '$global = 1' } }
    ],
    'Got all set breakpoints'
);

$resp = $mech->post("${url}breakpoint", { f => $filename, l => 4, c => undef});
ok($resp->is_success, 'Remove breakpoint for line 4');

$resp = $mech->get('breakpoints?f='.$filename);
ok($resp->is_success, 'Get all breakpoints for main file');
@bp = sort { $a->{data}->{lineno} <=> $b->{data}->{lineno} } @{ $json->decode($resp->content)};
is_deeply( \@bp,
    [
      {     type => 'breakpoint',
            data => { filename => $filename, lineno => 3, condition => 1 } },
      {     type => 'breakpoint',
            data => { filename => $filename, lineno => 5, condition => 1, action => '$global = 1' } }
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
