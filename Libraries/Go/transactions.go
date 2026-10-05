// Transactions (Library capability).
//
// CommitMarker is the sole acceptance authority. ExpectedRevision is a
// precondition only and is NEVER persisted as canonical state.
package vsn

// StagedOpKind enumerates the staged operations.
type StagedOpKind int

const (
	// OpCreate stages a new file.
	OpCreate StagedOpKind = iota
	// OpUpdate stages new content for an existing file.
	OpUpdate
	// OpDelete stages a delete.
	OpDelete
	// OpRename stages a rename.
	OpRename
)

// StagedChange is one staged mutation.
type StagedChange struct {
	Kind    StagedOpKind
	FileID  []byte
	Path    string
	Content []byte
	NewPath string
}

// Transaction stages changes and applies them atomically at commit.
//
// A committed transaction cannot be reused, and committing twice is rejected
// with INVALID_CANONICAL_STATE so an accepted state is never produced twice.
type Transaction struct {
	// ExpectedRevision, when non-nil, is checked against the current head of
	// the first staged change that names a FileId.
	ExpectedRevision *uint64
	staged           []StagedChange
	committed        bool
}

// Begin starts a transaction with no precondition.
func (s *Store) Begin() *Transaction {
	return &Transaction{}
}

// BeginExpecting starts a transaction guarded by ExpectedRevision.
func (s *Store) BeginExpecting(rev uint64) *Transaction {
	r := rev
	return &Transaction{ExpectedRevision: &r}
}

// StageCreate stages creation of a new file.
func (t *Transaction) StageCreate(path string, content []byte) {
	t.staged = append(t.staged, StagedChange{
		Kind: OpCreate, Path: path, Content: append([]byte(nil), content...)})
}

// StageUpdate stages new content for a file.
func (t *Transaction) StageUpdate(fileID []byte, content []byte) {
	t.staged = append(t.staged, StagedChange{
		Kind: OpUpdate, FileID: append([]byte(nil), fileID...),
		Content: append([]byte(nil), content...)})
}

// StageDelete stages deletion of a file.
func (t *Transaction) StageDelete(fileID []byte) {
	t.staged = append(t.staged, StagedChange{
		Kind: OpDelete, FileID: append([]byte(nil), fileID...)})
}

// StageRename stages a rename.
func (t *Transaction) StageRename(fileID []byte, newPath string) {
	t.staged = append(t.staged, StagedChange{
		Kind: OpRename, FileID: append([]byte(nil), fileID...), NewPath: newPath})
}

// Staged reports how many changes are pending.
func (t *Transaction) Staged() int { return len(t.staged) }

// Rollback discards every staged change. It does NOT undo cleanup that has
// already been applied and committed: once a container is committed, its
// canonical state is the accepted state.
func (t *Transaction) Rollback() {
	t.staged = nil
}

// Commit applies every staged change and commits the store.
//
// The precondition is checked BEFORE any change is applied, so a failed
// precondition leaves the store untouched.
func (t *Transaction) Commit(s *Store) ([]byte, error) {
	if t.committed {
		return nil, newError(ErrInvalidCanonicalState,
			"transaction already committed")
	}
	if err := s.checkOpen(); err != nil {
		return nil, err
	}

	// ExpectedRevision is a precondition only; it is never written to the
	// container. Check it against the first staged change naming a FileId.
	if t.ExpectedRevision != nil {
		for _, c := range t.staged {
			if c.FileID == nil {
				continue
			}
			cur, err := s.CurrentRevision(c.FileID)
			if err != nil {
				return nil, err
			}
			if cur != *t.ExpectedRevision {
				return nil, newError(ErrVerificationUnavailable,
					"ExpectedRevision mismatch: expected "+
						itoaU(*t.ExpectedRevision)+", got "+itoaU(cur))
			}
			break
		}
	}

	// Apply in stage order. A failure mid-apply is reported; the store is not
	// silently left partially committed, because Commit is the only point at
	// which bytes are produced and the caller decides what to persist.
	for _, c := range t.staged {
		var err error
		switch c.Kind {
		case OpCreate:
			_, err = s.CreateFile(c.Path, c.Content)
		case OpUpdate:
			err = s.WriteFile(c.FileID, c.Content)
		case OpDelete:
			err = s.DeleteFile(c.FileID)
		case OpRename:
			err = s.RenameFile(c.FileID, c.NewPath)
		default:
			err = newError(ErrInvalidCanonicalState, "unknown staged operation")
		}
		if err != nil {
			return nil, err
		}
	}
	t.committed = true
	t.staged = nil
	return s.Commit()
}