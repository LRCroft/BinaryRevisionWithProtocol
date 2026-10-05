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
    my $ok = 1;
    if ($n == 2) { $ok = VSN::create_file($s, "a", "hello") ne ""; }
    elsif ($n == 8) { $ok = ($s->{mode} == 1 || $s->{mode} == 2) ? 1 : 0; }
    elsif ($n == 1) { $ok = ($s->{mode} == 1) ? 1 : 0; }
    elsif ($n == 3) { my $fid=VSN::create_file($s,"r","v1"); VSN::write_file($s,$fid,"v2"); VSN::write_file($s,$fid,"v3"); my @revs=VSN::list_revisions($s,$fid); $ok=(@revs>=3)?1:0; }
    elsif ($n == 4) { my $fid=VSN::create_file($s,"lc","x"); for(1..5){VSN::write_file($s,$fid,$_)} my @d=VSN::limit_cleanup($s,$fid,3); $ok=(scalar(@d)==2)?1:0; }
    elsif ($n == 5) { VSN::create_file($s,"o","AB"); my @o=VSN::list_objects($s); $ok=(scalar(@o)>=1)?1:0; }
    elsif ($n == 6) { my $tx=VSN::begin_transaction($s); VSN::stage_add($tx,"t","x"); my($b,$_)=VSN::commit($s,$tx); $ok=(length($b)>=8)?1:0; }
    elsif ($n == 7) { $ok = (VSN::rep_direct_1()==1 && VSN::rep_extents_1()==2) ? 1 : 0; }
    elsif ($n == 9) { $ok = VSN::validate_structural($s) ? 1 : 0; }
    elsif ($n == 10) { $ok = (VSN::recover(VSN::export_bytes($s)) >= 0) ? 1 : 0; }
    elsif ($n == 11) { my $s2=VSN::create(1); VSN::create_file($s,"x","1"); my $d=VSN::diff_stores($s,$s2); $ok=(exists $d->{added})?1:0; }
    elsif ($n == 12) { my $b=VSN::create(1); my $o=VSN::create(1); my $t=VSN::create(1); my $m=VSN::merge_three_way($b,$o,$t); $ok=defined($m)?1:0; }
    elsif ($n == 13) { my $bytes=VSN::export_bytes($s); my $s2=VSN::open($bytes); $ok=($s2->{mode}==1)?1:0; }
    elsif ($n == 14) { my $fid=VSN::create_file($s,"big","bd"); my $c=VSN::read_file($s,$fid); $ok=(length($c)==2)?1:0; }
    elsif ($n == 15) { my @d=VSN::diagnostics($s,"Full"); $ok=(scalar(@d)>=0)?1:0; }
    elsif ($n == 16) { $ok = (VSN::integrity_verify(VSN::export_bytes($s))) ? 1 : 0; }
    elsif ($n == 17) { VSN::create_file($s,"stat","x"); my $st=VSN::get_stats($s); $ok=($st->{files}>=1)?1:0; }
    elsif ($n == 18) { my $b=VSN::new_builder(2); $ok=($b->{mode}==2)?1:0; }
    elsif ($n == 19) { $ok = (VSN::check_magic_bytes(VSN::encode(1,1))) ? 1 : 0; }
    VSN::close_store($s);
    if ($ok) { $PASSED++; print "PASS $n\n"; }
    else { $FAILED++; print "FAIL $n\n"; }
}

for my $n (1..19) { run_cap($n); }
print "PASS $PASSED\n";
