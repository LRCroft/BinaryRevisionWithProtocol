package vsn

import (
	"bytes"
	"testing"
)

// newStore builds a store with one file at revision 1.
func newStore(t *testing.T) (*Store, []byte) {
	t.Helper()
	s := Create(ModeModern)
	fid, err := s.CreateFile("a.txt", []byte("v1"))
	if err != nil {
		t.Fatalf("create file: %v", err)
	}
	return s, fid
}

// TestTransactionStagesAndCommits executes staging, precondition checking, and
// commit against a real container.
func TestTransactionStagesAndCommits(t *testing.T) {
	s, fid := newStore(t)
	tx := s.Begin()
	tx.StageCreate("b.txt", []byte("bee"))
	tx.StageUpdate(fid, []byte("v2"))
	if tx.Staged() != 2 {
		t.Fatalf("staged %d, want 2", tx.Staged())
	}
	data, err := tx.Commit(s)
	if err != nil {
		t.Fatalf("commit: %v", err)
	}
	reopened, err := Open(data)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	content, err := reopened.ReadFile(fid)
	if err != nil || string(content) != "v2" {
		t.Fatalf("update not applied: %q %v", content, err)
	}
	bfid, ok := reopened.FileIDByPath("b.txt")
	if !ok {
		t.Fatal("create not applied")
	}
	bc, err := reopened.ReadFile(bfid)
	if err != nil || string(bc) != "bee" {
		t.Fatalf("created content %q %v", bc, err)
	}
}

// TestTransactionCommitTwiceRejected proves a transaction cannot produce two
// accepted states.
func TestTransactionCommitTwiceRejected(t *testing.T) {
	s, fid := newStore(t)
	tx := s.Begin()
	tx.StageUpdate(fid, []byte("v2"))
	if _, err := tx.Commit(s); err != nil {
		t.Fatalf("first commit: %v", err)
	}
	_, err := tx.Commit(s)
	assertCode(t, err, ErrInvalidCanonicalState)
}

// TestTransactionPreconditionRejected proves ExpectedRevision is enforced
// before any change is applied, and is never persisted.
func TestTransactionPreconditionRejected(t *testing.T) {
	s, fid := newStore(t)
	// Current head is revision 1; demand 99.
	tx := s.BeginExpecting(99)
	tx.StageUpdate(fid, []byte("v2"))
	_, err := tx.Commit(s)
	assertCode(t, err, ErrVerificationUnavailable)

	// Nothing must have been applied.
	content, rerr := s.ReadFile(fid)
	if rerr != nil || string(content) != "v1" {
		t.Fatalf("store mutated by failed precondition: %q", content)
	}
	// The precondition must not appear in the committed bytes.
	data, cerr := s.Commit()
	if cerr != nil {
		t.Fatalf("commit: %v", cerr)
	}
	if bytes.Contains(data, []byte("99")) {
		t.Fatal("ExpectedRevision leaked into canonical bytes")
	}
}

// TestTransactionRollbackDiscardsStaging proves rollback drops pending work.
func TestTransactionRollbackDiscardsStaging(t *testing.T) {
	s, fid := newStore(t)
	tx := s.Begin()
	tx.StageUpdate(fid, []byte("discarded"))
	tx.StageCreate("c.txt", []byte("nope"))
	tx.Rollback()
	if tx.Staged() != 0 {
		t.Fatalf("staged %d after rollback", tx.Staged())
	}
	if _, err := tx.Commit(s); err != nil {
		t.Fatalf("commit after rollback: %v", err)
	}
	content, _ := s.ReadFile(fid)
	if string(content) != "v1" {
		t.Fatalf("rollback did not discard: %q", content)
	}
	if _, ok := s.FileIDByPath("c.txt"); ok {
		t.Fatal("rolled-back create was applied")
	}
}

// TestDiffObjectsAndFiles executes both diff levels.
func TestDiffObjectsAndFiles(t *testing.T) {
	od := DiffObjects([]uint64{1, 2, 3}, []uint64{2, 3, 4})
	if !equalUint64(od.Shared, []uint64{2, 3}) {
		t.Fatalf("shared %v", od.Shared)
	}
	if !equalUint64(od.Added, []uint64{4}) {
		t.Fatalf("added %v", od.Added)
	}
	if !equalUint64(od.Removed, []uint64{1}) {
		t.Fatalf("removed %v", od.Removed)
	}

	left, lf := newStore(t)
	left.CreateFile("only-left.txt", []byte("L"))
	right, rf := newStore(t)
	right.CreateFile("only-right.txt", []byte("R"))
	right.WriteFile(rf, []byte("v2")) // same path, different content

	fd, err := DiffFiles(left, right)
	if err != nil {
		t.Fatalf("diff files: %v", err)
	}
	if !contains(fd.Modified, "a.txt") {
		t.Fatalf("a.txt should be modified, got %v", fd.Modified)
	}
	if !contains(fd.Added, "only-right.txt") {
		t.Fatalf("added %v", fd.Added)
	}
	if !contains(fd.Deleted, "only-left.txt") {
		t.Fatalf("deleted %v", fd.Deleted)
	}
	_ = lf
}

// TestDiffRevisions executes revision-level diff.
func TestDiffRevisions(t *testing.T) {
	s, fid := newStore(t)
	s.WriteFile(fid, []byte("v2-longer"))
	d, err := DiffRevisions(s, fid, 1, 2)
	if err != nil {
		t.Fatalf("diff revisions: %v", err)
	}
	if !d.Changed {
		t.Fatal("revisions reported unchanged")
	}
	if string(d.ContentA) != "v1" || string(d.ContentB) != "v2-longer" {
		t.Fatalf("contents %q %q", d.ContentA, d.ContentB)
	}
	if d.AddedBytes != len("v2-longer")-len("v1") {
		t.Fatalf("added bytes %d", d.AddedBytes)
	}
}

// TestThreeWayMergeAutoMerges executes the non-conflicting merge paths.
//
// Each store is an independent branch from a shared base, so each owns its own
// FileId. Merge is keyed by PATH, which is why the branches must be matched on
// path rather than identity.
func TestThreeWayMergeAutoMerges(t *testing.T) {
	base, baseFid := newStore(t)
	ours, _ := newStore(t)
	theirs, theirsFid := newStore(t)

	// Only ours adds b.txt -> auto-taken. Only theirs changes a.txt -> auto-taken.
	ours.CreateFile("b.txt", []byte("ours-only"))
	theirs.WriteFile(theirsFid, []byte("theirs-only"))

	res, err := ThreeWayMerge(base, ours, theirs)
	if err != nil {
		t.Fatalf("merge: %v", err)
	}
	if res.HasConflicts() {
		t.Fatalf("unexpected conflicts: %v", res.Conflicts)
	}
	if string(res.MergedFiles["a.txt"]) != "theirs-only" {
		t.Fatalf("a.txt = %q", res.MergedFiles["a.txt"])
	}
	if string(res.MergedFiles["b.txt"]) != "ours-only" {
		t.Fatalf("b.txt = %q", res.MergedFiles["b.txt"])
	}
	_ = baseFid
}

// TestThreeWayMergeConflictAndResolve proves a differing change is reported,
// not guessed, and that resolution clears it.
func TestThreeWayMergeConflictAndResolve(t *testing.T) {
	base, _ := newStore(t)
	ours, oursFid := newStore(t)
	theirs, theirsFid := newStore(t)
	ours.WriteFile(oursFid, []byte("ours"))
	theirs.WriteFile(theirsFid, []byte("theirs"))

	res, err := ThreeWayMerge(base, ours, theirs)
	if err != nil {
		t.Fatalf("merge: %v", err)
	}
	if !res.HasConflicts() || len(res.Conflicts) != 1 {
		t.Fatalf("expected 1 conflict, got %d", len(res.Conflicts))
	}
	c := res.Conflicts[0]
	if c.Path != "a.txt" || string(c.OursContent) != "ours" ||
		string(c.TheirsContent) != "theirs" || string(c.BaseContent) != "v1" {
		t.Fatalf("conflict contents wrong: %+v", c)
	}

	res.ResolveConflict("a.txt", []byte("resolved"))
	if res.HasConflicts() {
		t.Fatal("resolve did not clear the conflict")
	}
	if string(res.MergedFiles["a.txt"]) != "resolved" {
		t.Fatalf("resolved content %q", res.MergedFiles["a.txt"])
	}
}

// TestImportExportRoundTrip proves binary safety including NUL and 0xFF.
func TestImportExportRoundTrip(t *testing.T) {
	s := Create(ModeModern)
	binary := []byte{0x00, 0x01, 0xFF, 0x00, 0x7F}
	fid, err := ImportBytes(s, "bin.dat", binary)
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	out, err := ExportBytes(s, fid)
	if err != nil {
		t.Fatalf("export: %v", err)
	}
	if !bytes.Equal(out, binary) {
		t.Fatalf("round trip changed bytes: % X", out)
	}
}

// TestImportExportStreaming proves chunked import/export is lossless.
func TestImportExportStreaming(t *testing.T) {
	s := Create(ModeModern)
	payload := make([]byte, 100000)
	for i := range payload {
		payload[i] = byte(i % 256)
	}
	fid, err := ImportReader(s, "big.bin", bytes.NewReader(payload), 4096)
	if err != nil {
		t.Fatalf("stream import: %v", err)
	}
	var sink bytes.Buffer
	n, err := ExportWriter(s, fid, &sink, 4096)
	if err != nil {
		t.Fatalf("stream export: %v", err)
	}
	if n != len(payload) {
		t.Fatalf("wrote %d, want %d", n, len(payload))
	}
	if !bytes.Equal(sink.Bytes(), payload) {
		t.Fatal("streamed bytes differ from original")
	}
}

// TestStreamChunksReassemblesExactly proves chunking never alters content.
func TestStreamChunksReassemblesExactly(t *testing.T) {
	s, fid := newStore(t)
	payload := make([]byte, 5000)
	for i := range payload {
		payload[i] = byte(i % 7)
	}
	s.WriteFile(fid, payload)
	chunks, err := StreamChunks(s, fid, 1024)
	if err != nil {
		t.Fatalf("chunk: %v", err)
	}
	if len(chunks) != 5 {
		t.Fatalf("got %d chunks, want 5", len(chunks))
	}
	var joined []byte
	for _, c := range chunks {
		joined = append(joined, c...)
	}
	if !bytes.Equal(joined, payload) {
		t.Fatal("reassembly differs")
	}
}

// TestDiagnosticsReportFrozenCodes proves diagnostics carry protocol
// identifiers, and library warnings deliberately do not impersonate them.
func TestDiagnosticsReportFrozenCodes(t *testing.T) {
	// A buffer long enough to hold a magic but with the wrong signature.
	diags := ValidateWithDiagnostics([]byte("XS--rest"), LevelFull)
	if len(diags) == 0 {
		t.Fatal("expected a diagnostic for bad magic")
	}
	d := diags[0]
	if d.Code != ErrMalformedContainer {
		t.Fatalf("code %04X, want 0001", d.Code)
	}
	if d.Category != CategoryProtocol || d.Severity != SeverityError {
		t.Fatalf("category/severity %v/%v", d.Category, d.Severity)
	}
	if d.Operation != string(LevelStructural) {
		t.Fatalf("operation %q", d.Operation)
	}

	w := LibraryWarning("ADVISORY", "something worth noting")
	if w.Category != CategoryLibrary || w.Code == ErrMalformedContainer {
		t.Fatalf("library warning must not impersonate a protocol code: %+v", w)
	}

	// A clean container must produce no diagnostics at all.
	data, err := BuildScenario("basic")
	if err != nil {
		t.Fatalf("build scenario: %v", err)
	}
	if got := ValidateWithDiagnostics(data, LevelFull); len(got) != 0 {
		t.Fatalf("clean container produced %d diagnostics: %v", len(got), got[0])
	}
}

// TestIntegrityVerifiesCleanContainer executes integrity on real bytes.
func TestIntegrityVerifiesCleanContainer(t *testing.T) {
	for _, name := range []string{"basic", "extents", "enterprise", "multifile"} {
		data, err := BuildScenario(name)
		if err != nil {
			t.Fatalf("%s: build: %v", name, err)
		}
		res, verr := VerifyIntegrity(data)
		if verr != nil {
			t.Fatalf("%s: verify: %v", name, verr)
		}
		if !res.OK || res.Status != "VERIFIED" {
			t.Fatalf("%s: integrity %+v", name, res)
		}
		if res.ObjectCount == 0 {
			t.Fatalf("%s: no objects counted", name)
		}
	}
}

// TestIntegrityRejectsCorruptBytes proves integrity is not a rubber stamp.
func TestIntegrityRejectsCorruptBytes(t *testing.T) {
	data, _ := BuildScenario("basic")
	bad := append([]byte(nil), data...)
	bad[0] = 'X'
	if _, err := VerifyIntegrity(bad); err == nil {
		t.Fatal("integrity accepted corrupt bytes")
	}
}

// TestStorageManagementIsDerivedOnly proves indexes and caches can be dropped
// and rebuilt without changing any canonical answer, and that recovery works
// with none of them present.
func TestStorageManagementIsDerivedOnly(t *testing.T) {
	s, fid := newStore(t)
	for i := 2; i <= 4; i++ {
		s.WriteFile(fid, []byte{byte('0' + i)})
	}
	data, err := s.Commit()
	if err != nil {
		t.Fatalf("commit: %v", err)
	}
	before, rerr := s.ReadFile(fid)
	if rerr != nil {
		t.Fatalf("read: %v", rerr)
	}

	m := NewStorageManager()
	if m.IsValid() {
		t.Fatal("fresh manager must not claim valid")
	}
	if err := m.BuildIndexes(s); err != nil {
		t.Fatalf("build: %v", err)
	}
	st, serr := m.Stats(s)
	if serr != nil {
		t.Fatalf("stats: %v", serr)
	}
	if st.FileCount != 1 || st.RevisionCount != 4 || st.ObjectCount != 4 {
		t.Fatalf("stats wrong: %+v", st)
	}
	if st.IndexEntries == 0 {
		t.Fatalf("no index entries: %+v", st)
	}

	// Dropping all derived data must not change any canonical answer.
	m.Invalidate()
	after, aerr := s.ReadFile(fid)
	if aerr != nil || !bytes.Equal(before, after) {
		t.Fatalf("derived data changed canonical read: %q %v", after, aerr)
	}
	if rr, _ := Recover(data); !rr.Recovered {
		t.Fatal("recovery failed with no derived data present")
	}
	if err := m.Rebuild(s); err != nil || !m.IsValid() {
		t.Fatalf("rebuild: %v", err)
	}
}

func equalUint64(a, b []uint64) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func contains(list []string, want string) bool {
	for _, v := range list {
		if v == want {
			return true
		}
	}
	return false
}

