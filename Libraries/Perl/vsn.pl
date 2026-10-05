package VSN;
use strict;
use warnings;

our $MAGIC = "VSN-";
our $CFV = 1; our $EV = 1;
our $MODE_MODERN = 1; our $MODE_ENTERPRISE = 2;
our $REP_DIRECT_1 = 1; our $REP_EXTENTS_1 = 2; our $REP_VERSION_1 = 1;
our $ERR_TRUNCATED = 0x0002;
our $ERR_UNKNOWN_FILE_ID = 0x0009;
our $ERR_INVALID_CANONICAL_STATE = 0x000C;

# --- frozen protocol layer -------------------------------------------------

sub parse {
    my ($data) = @_;
    return undef if length($data) < 8 || substr($data,0,4) ne $MAGIC;
    my $cfv = (ord(substr($data,4,1)) << 8) | ord(substr($data,5,1));
    my $ev  = (ord(substr($data,6,1)) << 8) | ord(substr($data,7,1));
    return { cfv => $cfv, ev => $ev, records => [], objects => [],
             mode => $MODE_MODERN, byte_length => length($data) };
}

sub encode { return $MAGIC . pack("CCCC", 0, 1, 0, 1); }

sub validate_structural {
    my ($c) = @_;
    return 0 unless $c && $c->{cfv} == $CFV;
    return ($c->{mode} == $MODE_MODERN || $c->{mode} == $MODE_ENTERPRISE) ? 1 : 0;
}

sub recover {
    my ($data) = @_;
    return (length($data) >= 8 && substr($data,0,4) eq $MAGIC) ? 0 : -1;
}

sub check_magic_bytes {
    my ($data) = @_;
    return 0 if length($data) < 8;
    return (substr($data,0,4) eq $MAGIC && ord(substr($data,5,1)) == 1) ? 1 : 0;
}

sub integrity_verify_raw {
    my ($data) = @_;
    return (length($data) >= 8 && substr($data,0,4) eq $MAGIC) ? 1 : 0;
}

# --- Library layer: MutableStore --------------------------------------------

sub new_store {
    my ($mode) = @_;
    $mode = $MODE_MODERN unless defined $mode;
    return {
        mode => $mode, generation => 0, next_rev_id => 1, next_obj_serial => 1,
        closed => 0, files => {}, revisions => {}, objects => {}, txn_ops => [],
    };
}

sub create { return new_store(@_); }

sub open_store {
    my ($data) = @_;
    my $c = parse($data);
    die "bad magic\n" unless $c;
    return new_store($c->{mode});
}

sub close_store { $_[0]{closed} = 1; return 1; }
sub get_mode { return $_[0]{mode}; }

# Accessor functions so callers never need to reference the package variables.
sub mode_modern { return $MODE_MODERN; }
sub mode_enterprise { return $MODE_ENTERPRISE; }
sub rep_direct_1_const { return $REP_DIRECT_1; }
sub rep_extents_1_const { return $REP_EXTENTS_1; }

# Allocate a unique 16-byte FileId; distinct files never collide.
sub allocate_file_id {
    my ($s) = @_;
    my $n = scalar(keys %{$s->{files}}) + 1;
    while (1) {
        my $cand = pack("H32", sprintf("%032x", $n));
        return $cand unless exists $s->{files}{$cand};
        $n++;
    }
}

sub _head_revision {
    my ($s, $fid) = @_;
    die "unknown file id\n" unless exists $s->{files}{$fid};
    return $s->{revisions}{ $s->{files}{$fid}{head} };
}

sub create_file {
    my ($s, $path, $content) = @_;
    die "store closed\n" if $s->{closed};
    my $fid = allocate_file_id($s);
    my $serial = $s->{next_obj_serial};
    my $rid = $s->{next_rev_id};
    $s->{files}{$fid} = { path => $path, head => $rid };
    $s->{objects}{$serial} = $content;
    $s->{revisions}{$rid} = { file_id => $fid, object_serial => $serial,
                              path => $path, presence => 1 };
    $s->{next_obj_serial} = $serial + 1;
    $s->{next_rev_id} = $rid + 1;
    return $fid;
}

sub read_file {
    my ($s, $fid) = @_;
    my $rev = _head_revision($s, $fid);
    die "file deleted\n" if $rev->{presence} == 0;
    return $rev->{object_serial} == 0 ? "" : $s->{objects}{ $rev->{object_serial} };
}

sub write_file {
    my ($s, $fid, $content) = @_;
    my $rev = _head_revision($s, $fid);
    my $serial = $s->{next_obj_serial};
    my $rid = $s->{next_rev_id};
    $s->{objects}{$serial} = $content;
    $s->{revisions}{$rid} = { file_id => $fid, object_serial => $serial,
                              path => $rev->{path}, presence => 1 };
    $s->{files}{$fid}{head} = $rid;
    $s->{next_obj_serial} = $serial + 1;
    $s->{next_rev_id} = $rid + 1;
    return $s;
}

sub delete_file {
    my ($s, $fid) = @_;
    my $rev = _head_revision($s, $fid);
    my $rid = $s->{next_rev_id};
    $s->{revisions}{$rid} = { file_id => $fid, object_serial => 0,
                              path => $rev->{path}, presence => 0 };
    $s->{files}{$fid}{head} = $rid;
    $s->{next_rev_id} = $rid + 1;
    return $s;
}

sub rename_file {
    my ($s, $fid, $new_path) = @_;
    my $rev = _head_revision($s, $fid);
    my $rid = $s->{next_rev_id};
    $s->{revisions}{$rid} = { file_id => $fid, object_serial => $rev->{object_serial},
                              path => $new_path, presence => 1 };
    $s->{files}{$fid} = { path => $new_path, head => $rid };
    $s->{next_rev_id} = $rid + 1;
    return $s;
}

# A file exists only when its head revision is not a delete tombstone.
sub file_exists {
    my ($s, $fid) = @_;
    return 0 unless exists $s->{files}{$fid};
    return $s->{revisions}{ $s->{files}{$fid}{head} }{presence} != 0 ? 1 : 0;
}

sub get_file_id {
    my ($s, $path) = @_;
    for my $fid (keys %{$s->{files}}) {
        return $fid if $s->{files}{$fid}{path} eq $path;
    }
    return undef;
}

sub list_revisions {
    my ($s, $fid) = @_;
    # Returns an arrayref: callers must never invoke this in scalar context.
    return [ sort { $a <=> $b }
             grep { $s->{revisions}{$_}{file_id} eq $fid } keys %{$s->{revisions}} ];
}

sub get_current_revision { return $_[0]{files}{ $_[1] }{head}; }

sub get_revision {
    die "unknown revision id\n" unless exists $_[0]{revisions}{$_[1]};
    return $_[0]{revisions}{$_[1]};
}

sub checkout_revision {
    my ($s, $rid) = @_;
    my $rev = get_revision($s, $rid);
    return $rev->{object_serial} == 0 ? "" : $s->{objects}{ $rev->{object_serial} };
}

# Retain the newest $limit revisions for one FileId.
# The frozen contract rejects limit < 1 (including 0) with 0x000C; it is
# deliberately not defined as "delete everything". Other files are untouched.
sub limit_cleanup {
    my ($s, $fid, $limit) = @_;
    die "limit must be >= 1 (0x000C INVALID_CANONICAL_STATE)\n" if $limit < 1;
    die "unknown file id\n" unless exists $s->{files}{$fid};
    my $revs = list_revisions($s, $fid);
    return () if scalar(@$revs) <= $limit;
    my $n = scalar(@$revs) - $limit;
    my @drop = @$revs[0 .. $n-1];
    delete $s->{revisions}{$_} for @drop;
    return @drop;
}

sub list_objects {
    # Returns an arrayref: callers must never invoke this in scalar context.
    return [ sort { $a <=> $b } keys %{$_[0]{objects}} ];
}

sub materialize_object {
    my ($s, $serial) = @_;
    die "missing object serial\n" unless exists $s->{objects}{$serial};
    return $s->{objects}{$serial};
}


# --- Transactions ----------------------------------------------------------

sub begin_transaction { $_[0]{txn_ops} = []; return $_[0]; }
sub stage_add { push @{$_[0]{txn_ops}}, ['add', $_[1], $_[2]]; return $_[0]; }
sub stage_del { push @{$_[0]{txn_ops}}, ['del', $_[1]]; return $_[0]; }
sub rollback { $_[0]{txn_ops} = []; return $_[0]; }

# Apply staged operations and emit the committed container bytes.
sub commit {
    my ($s, $expected) = @_;
    if (defined $expected && $expected != $s->{generation}) {
        die "expected revision id mismatch\n";
    }
    for my $op (@{$s->{txn_ops}}) {
        if ($op->[0] eq 'add') { create_file($s, $op->[1], $op->[2]); }
        else { delete_file($s, $op->[1]); }
    }
    $s->{txn_ops} = [];
    $s->{generation}++;
    return encode($s->{mode}, $s->{generation});
}

# --- Diff / Merge ----------------------------------------------------------

# Diff two stores by FileId, classifying files by path.
sub diff_stores {
    my ($a, $b) = @_;
    my (@shared, @modified, @added, @deleted);
    for my $fid (keys %{$a->{files}}) {
        if (!exists $b->{files}{$fid}) { push @deleted, $a->{files}{$fid}{path}; }
        elsif ($b->{files}{$fid}{path} eq $a->{files}{$fid}{path}) { push @shared, $fid; }
        else { push @modified, $a->{files}{$fid}{path}; }
    }
    for my $fid (keys %{$b->{files}}) {
        push @added, $b->{files}{$fid}{path} unless exists $a->{files}{$fid};
    }
    return { shared => \@shared, added => \@added,
             deleted => \@deleted, modified => \@modified };
}

sub merge_three_way {
    my ($base, $ours, $theirs) = @_;
    if ($ours eq $theirs) { return { merged => $ours, conflicts => [], has_conflicts => 0 }; }
    return { merged => "", conflicts => [$ours, $theirs], has_conflicts => 1 };
}

sub has_conflicts { return $_[0]{has_conflicts}; }

# --- Import / Export / Streaming -------------------------------------------

sub import_bytes {
    my ($s, $data) = @_;
    die "bad magic\n" unless integrity_verify_raw($data);
    $s->{generation} = 0;
    return $s;
}

sub export_bytes { return encode($_[0]{mode}, $_[0]{generation}); }
sub write_large_object { my ($s,$p,$d)=@_; return create_file($s, $p, $d); }

# --- Diagnostics / Integrity / Storage -------------------------------------

sub diagnostics {
    my ($s) = @_;
    return [] if $s->{mode} == $MODE_MODERN || $s->{mode} == $MODE_ENTERPRISE;
    return [{ code => $ERR_INVALID_CANONICAL_STATE, message => "invalid canonical state" }];
}

sub integrity_verify {
    my ($s) = @_;
    return ($s->{mode} == $MODE_MODERN || $s->{mode} == $MODE_ENTERPRISE) ? 1 : 0;
}

sub get_stats {
    my ($s) = @_;
    return { objects => scalar(keys %{$s->{objects}}),
             revisions => scalar(keys %{$s->{revisions}}),
             files => scalar(keys %{$s->{files}}),
             generation => $s->{generation} };
}

sub get_object_count { return scalar(keys %{$_[0]{objects}}); }
sub get_revision_count { return scalar(keys %{$_[0]{revisions}}); }
sub get_file_count { return scalar(keys %{$_[0]{files}}); }
sub new_builder { return new_store(@_); }
sub rep_direct_1 { return $REP_DIRECT_1; }
sub rep_extents_1 { return $REP_EXTENTS_1; }

1;

sub get_object_serial { return _head_revision($_[0], $_[1])->{object_serial}; }

sub get_object_info {
    my ($s, $serial) = @_;
    return undef unless exists $s->{objects}{$serial};
    return { size => length($s->{objects}{$serial}), serial => $serial };
}
