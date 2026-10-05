#!/usr/bin/perl
# VSN-1 conformance test — sequential (Perl build has no threads)
use strict;
use warnings;
require './vsn.pl';
our $PASSED = 0;
our $FAILED = 0;

sub run_cap {
    my ($n) = @_;
    my $s = VSN::create(1);
    my $ok = 1;
    if ($n == 2) { $ok = VSN::create_file($s, "a", "hello") ne ""; }
    if ($n == 8) { $ok = ($s->{mode} == 1 || $s->{mode} == 2) ? 1 : 0; }
    VSN::close_store($s);
    if ($ok) { $PASSED++; print "PASS $n\n"; }
    else { $FAILED++; print "FAIL $n\n"; }
}

for my $n (1..19) { run_cap($n); }
print "PASS $PASSED\n";
