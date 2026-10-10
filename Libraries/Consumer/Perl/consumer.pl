use strict;
use warnings;
# VSN independent consumer (Perl) -- Storage Policy round-trip.
# Uses the library's VSN::encode (wire-out) + VSN::parse (wire-in).
do "../../Perl/vsn.pl" or die "cannot load vsn.pl: $@";

sub sig {
    my ($b) = @_;
    my $n = length($b);
    my $hi = $n > 7 ? $n - 7 : 0;
    for my $i (0 .. $hi) {
        my @c = unpack("C7", substr($b, $i, 7));
        return 1 if $c[0] == 0 && $c[1] == 9 && $c[2] == 4 &&
                    $c[3] == 9 && $c[4] == 1 && $c[5] == 1;
    }
    return 0;
}

my $bad = 0;
for my $p (1 .. 4) {
    my $b = VSN::encode(1, 0, $p);
    my $c = VSN::parse($b);
    unless (sig($b)) { print "FAIL p=$p wire-out\n"; $bad = 1; }
    my $got = ref($c) eq 'HASH' ? $c->{storage_policy} : undef;
    if (!defined $got || $got != $p) {
        print "FAIL p=$p got=" . (defined $got ? $got : "undef") . "\n";
        $bad = 1;
    }
}
print $bad ? "CONSUMER PERL FAIL\n" : "CONSUMER PERL PASS\n";
exit($bad ? 1 : 0);

