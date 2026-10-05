// Structured diagnostics and derived storage management.
//
// Diagnostics carry error identity, severity, category, and context. Library
// diagnostics are explicitly distinguished from frozen protocol diagnostics, so
// a tool can tell "this container is invalid" apart from "this call was wrong".
package vsn

import "fmt"

// Severity classifies a diagnostic.
type Severity string

const (
	// SeverityError marks a hard failure.
	SeverityError Severity = "error"
	// SeverityWarning marks a recoverable problem.
	SeverityWarning Severity = "warning"
	// SeverityInfo marks an advisory note.
	SeverityInfo Severity = "info"
)

// Category states where a diagnostic originates.
type Category string

const (
	// CategoryProtocol means the diagnostic maps to a frozen VSN identifier.
	CategoryProtocol Category = "protocol"
	// CategoryLibrary means the diagnostic is library-only and carries no
	// frozen identifier.
	CategoryLibrary Category = "library"
	// CategoryDerived means the diagnostic concerns derived data.
	CategoryDerived Category = "derived"
)

// Diagnostic is one structured diagnostic.
type Diagnostic struct {
	Code       uint16
	Name       string
	Severity   Severity
	Category   Category
	Message    string
	ByteOffset int
	Operation  string
}

// String renders the diagnostic for logs.
func (d Diagnostic) String() string {
	return fmt.Sprintf("[%s/%s] %04X %s at %s: %s",
		d.Severity, d.Category, d.Code, d.Name, d.Operation, d.Message)
}

// diagnosticFromError converts a Library error into a protocol diagnostic.
func diagnosticFromError(e *Error, operation string) Diagnostic {
	return Diagnostic{
		Code: e.Code, Name: e.Name(), Severity: SeverityError,
		Category: CategoryProtocol, Message: e.Message,
		ByteOffset: e.ByteOffset, Operation: operation,
	}
}

// ValidateWithDiagnostics runs validation and returns diagnostics instead of
// raising. The first failing level stops the run, so the returned slice always
// names the earliest real problem rather than a cascade.
func ValidateWithDiagnostics(data []byte, level ValidateLevel) []Diagnostic {
	levels := validationLevels(level)
	var out []Diagnostic
	for _, lvl := range levels {
		var err error
		switch lvl {
		case LevelStructural:
			err = ValidateStructural(data)
		case LevelSemantic:
			err = ValidateSemantic(data)
		case LevelRecovery:
			var r *RecoveryResult
			r, err = Recover(data)
			if err == nil && !r.Recovered {
				err = newError(ErrInvalidCanonicalState,
					"recovery status "+r.Status+": "+r.Message)
			}
		case LevelContent:
			err = ValidateContent(data)
		}
		if err != nil {
			if e, ok := err.(*Error); ok {
				out = append(out, diagnosticFromError(e, string(lvl)))
			} else {
				out = append(out, Diagnostic{
					Code: 0xFFFF, Name: "LIBRARY_ERROR", Severity: SeverityError,
					Category: CategoryLibrary, Message: err.Error(),
					Operation: string(lvl),
				})
			}
			break
		}
	}
	return out
}

// validationLevels expands a level into the ordered levels it implies.
func validationLevels(level ValidateLevel) []ValidateLevel {
	switch level {
	case LevelStructural:
		return []ValidateLevel{LevelStructural}
	case LevelSemantic:
		return []ValidateLevel{LevelStructural, LevelSemantic}
	case LevelRecovery:
		return []ValidateLevel{LevelStructural, LevelSemantic, LevelRecovery}
	case LevelContent:
		return []ValidateLevel{LevelStructural, LevelSemantic, LevelContent}
	case LevelFull:
		return []ValidateLevel{LevelStructural, LevelSemantic, LevelRecovery, LevelContent}
	default:
		return nil
	}
}

// LibraryWarning builds a library-only advisory diagnostic. It deliberately
// carries no frozen identifier, because it is not a protocol condition.
func LibraryWarning(name, message string) Diagnostic {
	return Diagnostic{
		Code: 0xFFFF, Name: name, Severity: SeverityWarning,
		Category: CategoryLibrary, Message: message,
	}
}

// --- Derived storage management ---

// StorageStats reports container and derived-storage statistics.
type StorageStats struct {
	ContainerBytes int
	RecordCount    int
	ObjectCount    int
	FileCount      int
	RevisionCount  int
	IndexEntries   int
	CacheEntries   int
	CacheBytes     int
}

// StorageManager owns derived indexes and a content cache.
//
// Everything here is rebuildable from canonical VSN content, and recovery works
// with none of it present. It can therefore never become an acceptance
// authority.
type StorageManager struct {
	objectIndex map[uint64]ObjectInfo
	fileIndex   map[string][]byte
	cache       map[uint64][]byte
	valid       bool
}

// NewStorageManager returns an empty, invalid storage manager.
func NewStorageManager() *StorageManager {
	m := &StorageManager{}
	m.Invalidate()
	return m
}

// BuildIndexes derives indexes from canonical state.
func (m *StorageManager) BuildIndexes(s *Store) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.checkOpen(); err != nil {
		return err
	}
	m.objectIndex = map[uint64]ObjectInfo{}
	m.fileIndex = map[string][]byte{}
	for _, serial := range sortedSerials(s.objects) {
		desc := s.objects[serial]
		ident, ver, rem, err := ParseObjectHeader(desc)
		if err != nil {
			return err
		}
		m.objectIndex[serial] = ObjectInfo{
			Serial: serial, Length: len(rem),
			RepresentationIdentity: ident, RepresentationVersion: ver,
		}
	}
	for _, info := range s.files {
		if info.HasPath && info.Path != "" {
			m.fileIndex[info.Path] = append([]byte(nil), info.ID...)
		}
	}
	m.valid = true
	return nil
}

// Rebuild discards derived data and rebuilds it from canonical state.
func (m *StorageManager) Rebuild(s *Store) error {
	m.Invalidate()
	return m.BuildIndexes(s)
}

// Invalidate drops all derived data. The container remains fully usable.
func (m *StorageManager) Invalidate() {
	m.objectIndex = map[uint64]ObjectInfo{}
	m.fileIndex = map[string][]byte{}
	m.cache = map[uint64][]byte{}
	m.valid = false
}

// GC drops cached materialized content and reports how many entries went.
func (m *StorageManager) GC() int {
	n := len(m.cache)
	m.cache = map[uint64][]byte{}
	return n
}

// IsValid reports whether indexes are currently built.
func (m *StorageManager) IsValid() bool { return m.valid }

// Stats reports container and derived-storage statistics.
func (m *StorageManager) Stats(s *Store) (StorageStats, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.checkOpen(); err != nil {
		return StorageStats{}, err
	}
	st := StorageStats{
		ObjectCount:   len(s.objects),
		FileCount:     len(s.files),
		RevisionCount: len(s.revisions),
		IndexEntries:  len(m.objectIndex) + len(m.fileIndex),
		CacheEntries:  len(m.cache),
	}
	if s.parsed != nil {
		st.RecordCount = len(s.parsed.Records)
	}
	st.ContainerBytes = len(s.data)
	for _, v := range m.cache {
		st.CacheBytes += len(v)
	}
	return st, nil
}