// Three-way merge (Library capability).
//
// Merge is a workflow operation. Merge metadata is temporary Library state
// only; no VSN protocol record is invented to represent a merge.
package vsn

// Conflict records a path where ours and theirs both changed differently.
type Conflict struct {
	Path         string
	BaseContent  []byte
	OursContent  []byte
	TheirsContent []byte
}

// MergeResult is the outcome of a three-way merge.
type MergeResult struct {
	MergedFiles map[string][]byte
	Conflicts   []Conflict
	Added       []string
	Deleted     []string
}

// HasConflicts reports whether any conflict requires resolution.
func (m *MergeResult) HasConflicts() bool { return len(m.Conflicts) > 0 }

// ThreeWayMerge merges ours and theirs relative to base.
//
// A change made on only one side is taken automatically; a change made
// differently on both sides is reported as a conflict rather than guessed.
func ThreeWayMerge(base, ours, theirs *Store) (MergeResult, error) {
	bp, err := pathIndex(base)
	if err != nil {
		return MergeResult{}, err
	}
	op, err := pathIndex(ours)
	if err != nil {
		return MergeResult{}, err
	}
	tp, err := pathIndex(theirs)
	if err != nil {
		return MergeResult{}, err
	}

	seen := map[string]bool{}
	for _, m := range []map[string][]byte{bp, op, tp} {
		for p := range m {
			seen[p] = true
		}
	}
	paths := make([]string, 0, len(seen))
	for p := range seen {
		paths = append(paths, p)
	}
	sortStrings(paths)

	out := MergeResult{MergedFiles: map[string][]byte{}}
	read := func(s *Store, m map[string][]byte, p string) ([]byte, bool) {
		fid, ok := m[p]
		if !ok {
			return nil, false
		}
		c, err := s.ReadFile(fid)
		if err != nil {
			// A deleted head reads as absent, matching the reference merge.
			return nil, false
		}
		return c, true
	}

	for _, p := range paths {
		bc, _ := read(base, bp, p)
		oc, inO := read(ours, op, p)
		tc, inT := read(theirs, tp, p)

		switch {
		case equalBytes(oc, tc):
			// Both sides agree (including both absent).
			if inO {
				out.MergedFiles[p] = oc
			} else {
				out.Deleted = append(out.Deleted, p)
			}
		case equalBytes(oc, bc) && !equalBytes(tc, bc):
			// Only theirs changed.
			if inT {
				out.MergedFiles[p] = tc
			} else {
				out.Deleted = append(out.Deleted, p)
			}
		case equalBytes(tc, bc) && !equalBytes(oc, bc):
			// Only ours changed.
			if inO {
				out.MergedFiles[p] = oc
			} else {
				out.Deleted = append(out.Deleted, p)
			}
		default:
			// Both changed differently: report, never guess.
			out.Conflicts = append(out.Conflicts, Conflict{
				Path: p, BaseContent: orEmpty(bc),
				OursContent: orEmpty(oc), TheirsContent: orEmpty(tc),
			})
		}
	}
	return out, nil
}

// ResolveConflict applies caller-supplied final content for a conflicted path
// and removes it from the conflict list.
func (m *MergeResult) ResolveConflict(path string, content []byte) {
	kept := m.Conflicts[:0]
	for _, c := range m.Conflicts {
		if c.Path != path {
			kept = append(kept, c)
		}
	}
	m.Conflicts = kept
	m.MergedFiles[path] = append([]byte(nil), content...)
}

func equalBytes(a, b []byte) bool {
	if (a == nil) != (b == nil) {
		// Treat nil and empty as different only where it matters; the
		// reference treats absent as absent, so compare length+content.
		if len(a) != len(b) {
			return false
		}
	}
	return string(a) == string(b)
}

func orEmpty(b []byte) []byte {
	if b == nil {
		return []byte{}
	}
	return b
}