// Library-level diff (derived data, never canonical).
//
// Diff output is derived and disposable. It is never a canonical recovery
// dependency and is never consulted to decide acceptance.
package vsn

// ObjectDiff reports the set difference between two ObjectSerial sets.
type ObjectDiff struct {
	Shared  []uint64
	Added   []uint64
	Removed []uint64
}

// FileDiff reports the path-level difference between two stores.
type FileDiff struct {
	Added     []string
	Deleted   []string
	Modified  []string
	Unchanged []string
}

// DiffObjects compares two ObjectSerial sets.
func DiffObjects(left, right []uint64) ObjectDiff {
	l := map[uint64]bool{}
	r := map[uint64]bool{}
	for _, v := range left {
		l[v] = true
	}
	for _, v := range right {
		r[v] = true
	}
	out := ObjectDiff{}
	for v := range l {
		if r[v] {
			out.Shared = append(out.Shared, v)
		} else {
			out.Removed = append(out.Removed, v)
		}
	}
	for v := range r {
		if !l[v] {
			out.Added = append(out.Added, v)
		}
	}
	sortUint64(out.Shared)
	sortUint64(out.Added)
	sortUint64(out.Removed)
	return out
}

// DiffFiles compares two stores by path and logical content.
func DiffFiles(left, right *Store) (FileDiff, error) {
	lp, err := pathIndex(left)
	if err != nil {
		return FileDiff{}, err
	}
	rp, err := pathIndex(right)
	if err != nil {
		return FileDiff{}, err
	}
	seen := map[string]bool{}
	for p := range lp {
		seen[p] = true
	}
	for p := range rp {
		seen[p] = true
	}
	paths := make([]string, 0, len(seen))
	for p := range seen {
		paths = append(paths, p)
	}
	sortStrings(paths)

	out := FileDiff{}
	for _, p := range paths {
		lid, hasL := lp[p]
		rid, hasR := rp[p]
		switch {
		case hasL && !hasR:
			out.Deleted = append(out.Deleted, p)
		case !hasL && hasR:
			out.Added = append(out.Added, p)
		default:
			lc, err := left.ReadFile(lid)
			if err != nil {
				return FileDiff{}, err
			}
			rc, err := right.ReadFile(rid)
			if err != nil {
				return FileDiff{}, err
			}
			if string(lc) == string(rc) {
				out.Unchanged = append(out.Unchanged, p)
			} else {
				out.Modified = append(out.Modified, p)
			}
		}
	}
	return out, nil
}

// pathIndex maps path -> FileId for every path-present file in a store.
func pathIndex(s *Store) (map[string][]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := map[string][]byte{}
	for _, info := range s.files {
		if info.HasPath && info.Path != "" {
			out[info.Path] = append([]byte(nil), info.ID...)
		}
	}
	return out, nil
}

// RevisionDiff reports the content difference between two revisions.
type RevisionDiff struct {
	RevisionA  uint64
	RevisionB  uint64
	ContentA   []byte
	ContentB   []byte
	Changed    bool
	AddedBytes int
}

// DiffRevisions compares two revisions of the same file.
func DiffRevisions(s *Store, fileID []byte, a, b uint64) (RevisionDiff, error) {
	ca, err := s.CheckoutRevision(fileID, a)
	if err != nil {
		return RevisionDiff{}, err
	}
	cb, err := s.CheckoutRevision(fileID, b)
	if err != nil {
		return RevisionDiff{}, err
	}
	d := RevisionDiff{RevisionA: a, RevisionB: b, ContentA: ca, ContentB: cb}
	d.Changed = string(ca) != string(cb)
	if d.Changed {
		d.AddedBytes = len(cb) - len(ca)
	}
	return d, nil
}