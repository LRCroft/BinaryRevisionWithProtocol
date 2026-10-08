// Mutable VSN container: the Library's primary API.
package vsn

import (
	"crypto/rand"
	"encoding/hex"
	"strconv"
	"sync"
)

// FileInfo is the mutable per-file state tracked by a Store.
type FileInfo struct {
	ID      []byte
	Path    string
	HasPath bool
	HeadRev uint64
	HasHead bool
}

// Revision is a single revision: which file it belongs to, which content
// object it names, its path, and its presence.
type Revision struct {
	RevisionID   uint64
	FileID       []byte
	ObjectSerial uint64
	HasObject    bool
	Path         string
	HasPath      bool
	Presence     uint8
}

// Store is the mutable VSN container.
//
// All canonical state lives in files/revisions/objects; `cache` holds only
// materialized content and is purely derived, so clearing it can never change
// an answer.
type Store struct {
	mu sync.Mutex

	files     map[string]*FileInfo // keyed by hex FileId
	revisions map[uint64]*Revision
	objects   map[uint64][]byte // ObjectSerial -> descriptor bytes
	cache     map[uint64][]byte // derived materialized-content cache

	nextSerial    uint64
	nextRevID     uint64
	generation    uint64
	mode          uint8
	storagePolicy StoragePolicy // direct storage policy value (1..4) -- canonical on wire

	data   []byte
	parsed *Container
	closed bool
}

// Create returns an empty container in the given mode.
func Create(mode uint8) *Store {
	return &Store{
		files:      map[string]*FileInfo{},
		revisions:  map[uint64]*Revision{},
		objects:    map[uint64][]byte{},
		cache:      map[uint64][]byte{},
		nextSerial: 1,
		nextRevID:  1,
		mode:       mode,
	}
}

// CreateWithPolicy creates a store with the given StoragePolicy as direct classification.
func CreateWithPolicy(policy StoragePolicy) *Store {
	return &Store{
		files:         map[string]*FileInfo{},
		revisions:     map[uint64]*Revision{},
		objects:       map[uint64][]byte{},
		cache:         map[uint64][]byte{},
		nextSerial:    1,
		nextRevID:     1,
		mode:          ModeModern, // default wire mode for canonical writers
		storagePolicy: policy,
	}
}

// Open parses canonical bytes into a mutable store.
func Open(data []byte) (*Store, error) {
	s := Create(ModeModern)
	if err := s.reopen(data); err != nil {
		return nil, err
	}
	// Extract StoragePolicy from parsed records (if available)
	if s.parsed != nil && s.parsed.StoragePolicy >= 1 && s.parsed.StoragePolicy <= 4 {
		s.storagePolicy = StoragePolicy(s.parsed.StoragePolicy)
	}
	return s, nil
}

// reopen (re)builds all in-memory state from canonical bytes.
func (s *Store) reopen(data []byte) error {
	c, err := Parse(data)
	if err != nil {
		return err
	}
	s.data = append([]byte(nil), data...)
	s.parsed = c
	s.files = map[string]*FileInfo{}
	s.revisions = map[uint64]*Revision{}
	s.objects = map[uint64][]byte{}
	s.cache = map[uint64][]byte{}
	s.nextSerial = 1
	s.nextRevID = 1
	s.generation = 0

	for i := range c.Records {
		rec := &c.Records[i]
		switch rec.RType {
		case RecFileIdentity:
			if f := rec.Field(FidFileID); f != nil {
				id := append([]byte(nil), f.Value...)
				key := hex.EncodeToString(id)
				if _, ok := s.files[key]; !ok {
					s.files[key] = &FileInfo{ID: id}
				}
			}
		case RecRevision:
			ridF := rec.Field(FidRevID)
			fidF := rec.Field(FidRevFileID)
			if ridF == nil || fidF == nil {
				continue
			}
			rid := ridF.UvarintValue()
			fid := append([]byte(nil), fidF.Value...)
			rev := &Revision{
				RevisionID: rid,
				FileID:     fid,
				Presence:   Present,
			}
			if o := rec.Field(FidRevObjectSerial); o != nil {
				rev.ObjectSerial = o.UvarintValue()
				rev.HasObject = true
			}
			if p := rec.Field(FidRevPath); p != nil {
				rev.Path = string(p.Value)
				rev.HasPath = true
			}
			if pr := rec.Field(FidRevPresence); pr != nil && len(pr.Value) > 0 {
				rev.Presence = pr.Value[0]
			}
			s.revisions[rid] = rev
			if rid >= s.nextRevID {
				s.nextRevID = rid + 1
			}
			if info := s.files[hex.EncodeToString(fid)]; info != nil && rev.HasPath {
				info.Path = rev.Path
				info.HasPath = true
			}
		case RecFileHead:
			fidF := rec.Field(FidHeadFileID)
			ridF := rec.Field(FidHeadRevID)
			if fidF == nil || ridF == nil {
				continue
			}
			if info := s.files[hex.EncodeToString(fidF.Value)]; info != nil {
				info.HeadRev = ridF.UvarintValue()
				info.HasHead = true
			}
		case RecCommitMarker:
			if g := rec.Field(FidCommitGen); g != nil {
				s.generation = g.UvarintValue()
			}
		}
	}
	if c.HasMode {
		s.mode = c.Mode
	}
	for _, o := range c.Objects {
		s.objects[o.Serial] = append([]byte(nil), o.Descriptor...)
		if o.Serial >= s.nextSerial {
			s.nextSerial = o.Serial + 1
		}
	}
	return nil
}

// checkOpen rejects use of a closed container.
func (s *Store) checkOpen() error {
	if s.closed {
		return newError(ErrMalformedContainer, "container is closed")
	}
	return nil
}

// Close releases the store; further operations fail with a Library error.
func (s *Store) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.closed = true
	s.cache = map[uint64][]byte{}
	return nil
}

// Closed reports whether the store has been closed.
func (s *Store) Closed() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.closed
}

// Mode returns the container mode (0x01 MODERN, 0x02 ENTERPRISE).
func (s *Store) Mode() uint8 {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.mode
}

// GetStoragePolicy returns the direct StoragePolicy value (1..4), or 0 if unset.
func (s *Store) GetStoragePolicy() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return int(s.storagePolicy)
}

// Generation returns the current accepted generation.
func (s *Store) Generation() uint64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.generation
}

// newFileID returns a fresh 16-byte FileId.
func newFileID() ([]byte, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return nil, newError(ErrMalformedContainer,
			"FileId source failed: "+err.Error())
	}
	return b, nil
}

func keyOf(id []byte) string { return hex.EncodeToString(id) }

func itoaU(v uint64) string { return strconv.FormatUint(v, 10) }

// hexU16 renders a u16 as four lowercase hex digits for diagnostics.
func hexU16(v uint16) string {
	const digits = "0123456789abcdef"
	return string([]byte{
		digits[(v>>12)&0xF], digits[(v>>8)&0xF],
		digits[(v>>4)&0xF], digits[v&0xF],
	})
}

// --- Canonical serialization ---

// ToBytes produces canonical VSN-1 bytes from current state and advances the
// generation. It does not mutate the store's accepted state.
func (s *Store) ToBytes() ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.toBytesLocked()
}

func (s *Store) toBytesLocked() ([]byte, error) {
	if err := s.checkOpen(); err != nil {
		return nil, err
	}
	gen := s.generation + 1

	// Canonical: always emit REC_STORAGE_POLICY (authoritative on wire).
	// NEVER fall back to ModeDeclaration.
	policyVal := uint8(s.storagePolicy)
	if policyVal == 0 {
		policyVal = uint8(StoragePolicyVertical) // default when unset
	}
	records := []rawRecord{{
		rtype:  RecStoragePolicy,
		fields: []rawField{{fid: FidStoragePolicy, value: []byte{policyVal}}},
	}}

	// File identities, ordered by FileId so encoding is deterministic.
	keys := make([]string, 0, len(s.files))
	for k := range s.files {
		keys = append(keys, k)
	}
	sortStrings(keys)
	for _, k := range keys {
		records = append(records, rawRecord{
			rtype:  RecFileIdentity,
			fields: []rawField{{fid: FidFileID, value: s.files[k].ID}},
		})
	}

	// Revisions in ascending RevisionId.
	rids := make([]uint64, 0, len(s.revisions))
	for rid := range s.revisions {
		rids = append(rids, rid)
	}
	sortUint64(rids)
	for _, rid := range rids {
		rev := s.revisions[rid]
		fields := []rawField{
			{fid: FidRevID, value: AppendUvarint(nil, rid)},
			{fid: FidRevFileID, value: rev.FileID},
		}
		if rev.HasObject {
			fields = append(fields, rawField{
				fid: FidRevObjectSerial, value: AppendUvarint(nil, rev.ObjectSerial)})
		}
		if rev.HasPath {
			fields = append(fields, rawField{fid: FidRevPath, value: []byte(rev.Path)})
		}
		fields = append(fields, rawField{fid: FidRevPresence, value: []byte{rev.Presence}})
		records = append(records, rawRecord{rtype: RecRevision, fields: fields})
	}

	// ContentObjects. 0x0511 declares the LOGICAL content length (SR-27/29),
	// never the representation payload length. It is optional and omitted when
	// the logical length cannot be resolved.
	for _, serial := range sortedSerials(s.objects) {
		fields := []rawField{
			{fid: FidObjectSerial, value: AppendUvarint(nil, serial)},
		}
		if logical, err := s.materializeLocked(serial, map[uint64]bool{}); err == nil {
			fields = append(fields, rawField{
				fid: FidObjectSize, value: AppendUvarint(nil, uint64(len(logical)))})
		}
		records = append(records, rawRecord{rtype: RecContentObject, fields: fields})
	}

	for _, k := range keys {
		info := s.files[k]
		if !info.HasHead {
			continue
		}
		records = append(records, rawRecord{
			rtype: RecFileHead,
			fields: []rawField{
				{fid: FidHeadFileID, value: info.ID},
				{fid: FidHeadRevID, value: AppendUvarint(nil, info.HeadRev)},
			},
		})
	}

	records = append(records, rawRecord{
		rtype:  RecCommitMarker,
		fields: []rawField{{fid: FidCommitGen, value: AppendUvarint(nil, gen)}},
	})

	return Encode(records, s.objects, gen), nil
}

// Commit serializes the store, makes the result its accepted state, and
// returns canonical bytes.
func (s *Store) Commit() ([]byte, error) {
	s.mu.Lock()
	data, err := s.toBytesLocked()
	if err != nil {
		s.mu.Unlock()
		return nil, err
	}
	s.generation++
	s.mu.Unlock()

	if err := s.reopen(data); err != nil {
		return nil, err
	}
	return data, nil
}

// Reopen rebuilds the store from bytes (or from the last committed state).
func (s *Store) Reopen() error {
	s.mu.Lock()
	data := s.data
	s.mu.Unlock()
	if len(data) == 0 {
		return newError(ErrInvalidCanonicalState, "no committed state to reopen")
	}
	return s.reopen(data)
}

// sortStrings sorts ascending in place.
func sortStrings(a []string) {
	for i := 1; i < len(a); i++ {
		for j := i; j > 0 && a[j] < a[j-1]; j-- {
			a[j], a[j-1] = a[j-1], a[j]
		}
	}
}

// sortedSerials returns the keys of m in ascending order.
func sortedSerials(m map[uint64][]byte) []uint64 {
	out := make([]uint64, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sortUint64(out)
	return out
}

// --- Object API ---

// addObjectLocked stores content as a DIRECT-1 object and returns its serial.
// The caller must hold s.mu.
func (s *Store) addObjectLocked(content []byte) uint64 {
	serial := s.nextSerial
	s.nextSerial++
	s.objects[serial] = Direct1Descriptor(content)
	return serial
}

// Objects returns ascending ObjectSerials present in the container.
func (s *Store) Objects() []uint64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]uint64, 0, len(s.objects))
	for serial := range s.objects {
		out = append(out, serial)
	}
	sortUint64(out)
	return out
}

// ObjectInfo describes one content object.
type ObjectInfo struct {
	Serial                uint64
	Length                int // payload remainder length, NOT logical length
	RepresentationIdentity uint16
	RepresentationVersion  uint64
}

// ObjectInfo returns metadata for a content object.
func (s *Store) ObjectInfo(serial uint64) (ObjectInfo, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	desc := s.objects[serial]
	if desc == nil {
		return ObjectInfo{}, newError(ErrMissingObject,
			"missing object "+itoaU(serial))
	}
	ident, ver, rem, err := ParseObjectHeader(desc)
	if err != nil {
		return ObjectInfo{}, err
	}
	return ObjectInfo{
		Serial: serial, Length: len(rem),
		RepresentationIdentity: ident, RepresentationVersion: ver,
	}, nil
}

// GetObjectSerial resolves the ObjectSerial a file revision names. With revID
// nil the file's accepted head is used; a revision with no object yields
// (0, false).
func (s *Store) GetObjectSerial(id []byte, revID *uint64) (uint64, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	info := s.files[keyOf(id)]
	if info == nil {
		return 0, false, newError(ErrMissingCanonicalReference, "unknown FileId")
	}
	rid := uint64(0)
	if revID != nil {
		rid = *revID
	} else {
		if !info.HasHead {
			return 0, false, nil
		}
		rid = info.HeadRev
	}
	rev := s.revisions[rid]
	if rev == nil || !rev.HasObject {
		return 0, false, nil
	}
	return rev.ObjectSerial, true, nil
}

// Materialize returns an object's logical content.
func (s *Store) Materialize(serial uint64) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.materializeLocked(serial, map[uint64]bool{})
}

// materializeLocked materializes with cycle detection. The caller holds s.mu.
func (s *Store) materializeLocked(serial uint64, visited map[uint64]bool) ([]byte, error) {
	if visited[serial] {
		return nil, newError(ErrInvalidCanonicalState,
			"cycle at ObjectSerial "+itoaU(serial))
	}
	if cached, ok := s.cache[serial]; ok {
		return cached, nil
	}
	desc := s.objects[serial]
	if desc == nil {
		return nil, newError(ErrMissingObject, "missing object "+itoaU(serial))
	}
	ident, ver, rem, err := ParseObjectHeader(desc)
	if err != nil {
		return nil, err
	}
	var out []byte
	switch {
	case ident == RepDirect1 && ver == uint64(RepVersion1):
		out = MaterializeDirect(rem)
	case ident == RepExtents1 && ver == uint64(RepVersion1):
		nested := map[uint64]bool{}
		for k := range visited {
			nested[k] = true
		}
		nested[serial] = true
		out, err = MaterializeExtents(rem, func(dep uint64) ([]byte, error) {
			return s.materializeLocked(dep, nested)
		}, nested)
		if err != nil {
			return nil, err
		}
	default:
		return nil, newError(ErrUnsupportedRepresentation,
			"unsupported rep 0x"+hexU16(ident)+" v"+itoaU(ver))
	}
	if _, ok := s.cache[serial]; !ok {
		s.cache[serial] = out
	}
	return out, nil
}

// ListRevisions returns ascending revision ids. With a nil FileId every
// revision in the container is returned.
func (s *Store) ListRevisions(id []byte) []uint64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []uint64
	for rid, rev := range s.revisions {
		if id == nil || keyOf(rev.FileID) == keyOf(id) {
			out = append(out, rid)
		}
	}
	sortUint64(out)
	return out
}

// GetRevision returns a copy of a revision's canonical metadata.
func (s *Store) GetRevision(rid uint64) (Revision, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	rev := s.revisions[rid]
	if rev == nil {
		return Revision{}, newError(ErrMissingCanonicalReference,
			"unknown RevisionId "+itoaU(rid))
	}
	c := *rev
	c.FileID = append([]byte(nil), rev.FileID...)
	return c, nil
}

// CurrentRevision returns the file's accepted head revision id.
func (s *Store) CurrentRevision(id []byte) (uint64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	info := s.files[keyOf(id)]
	if info == nil {
		return 0, newError(ErrMissingCanonicalReference, "unknown FileId")
	}
	if !info.HasHead {
		return 0, nil
	}
	return info.HeadRev, nil
}

// CheckoutRevision returns the logical content of a specific revision.
func (s *Store) CheckoutRevision(id []byte, rid uint64) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	rev := s.revisions[rid]
	if rev == nil {
		return nil, newError(ErrMissingCanonicalReference,
			"unknown RevisionId "+itoaU(rid))
	}
	if keyOf(rev.FileID) != keyOf(id) {
		return nil, newError(ErrInvalidRelationship,
			"RevisionId does not belong to FileId")
	}
	if !rev.HasObject {
		return []byte{}, nil
	}
	return s.materializeLocked(rev.ObjectSerial, map[uint64]bool{})
}

// RestoreRevision re-commits a historical revision's content as a new head.
func (s *Store) RestoreRevision(id []byte, rid uint64) error {
	s.mu.Lock()
	rev := s.revisions[rid]
	if rev == nil {
		s.mu.Unlock()
		return newError(ErrMissingCanonicalReference, "unknown RevisionId "+itoaU(rid))
	}
	if keyOf(rev.FileID) != keyOf(id) {
		s.mu.Unlock()
		return newError(ErrInvalidRelationship, "RevisionId does not belong to FileId")
	}
	var content []byte
	if rev.HasObject {
		c, err := s.materializeLocked(rev.ObjectSerial, map[uint64]bool{})
		if err != nil {
			s.mu.Unlock()
			return err
		}
		content = c
	}
	s.mu.Unlock()
	return s.WriteFile(id, content)
}

// --- History retention: LimitCleanUp (Library capability) ---
//
// LimitCleanUp is a Library capability, NOT a VSN protocol rule. It is scoped
// to one FileId, orders by ascending RevisionId, retains the newest `limit`
// revisions, and never touches the shared object section.
//
// `limit` must be >= 1; a limit of 0 (or a negative limit) is rejected with
// 0x000C so a slipped argument cannot silently destroy an entire history.
func (s *Store) LimitCleanUp(id []byte, limit int64) ([]uint64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.checkOpen(); err != nil {
		return nil, err
	}
	if limit < 1 {
		return nil, newError(ErrInvalidCanonicalState,
			"LimitCleanUp limit must be >= 1, got "+strconv.FormatInt(limit, 10))
	}
	info := s.files[keyOf(id)]
	if info == nil {
		return nil, newError(ErrMissingCanonicalReference, "unknown FileId")
	}

	// Canonical revision ordering is ascending RevisionId, filtered by FileId
	// BEFORE ordering so history never bleeds across files.
	var rids []uint64
	for rid, rev := range s.revisions {
		if keyOf(rev.FileID) == keyOf(id) {
			rids = append(rids, rid)
		}
	}
	sortUint64(rids)
	if int64(len(rids)) <= limit {
		return []uint64{}, nil // nothing to do; no state is touched
	}
	keepFrom := int64(len(rids)) - limit
	keep := map[uint64]bool{}
	for _, rid := range rids[keepFrom:] {
		keep[rid] = true
	}
	var removed []uint64
	for _, rid := range rids {
		if !keep[rid] {
			removed = append(removed, rid)
		}
	}

	// The head is always the newest revision, so limit >= 1 always retains it.
	// Refuse rather than emit a dangling FileHead if that invariant ever breaks.
	if info.HasHead && !keep[info.HeadRev] {
		return nil, newError(ErrInvalidCanonicalState,
			"LimitCleanUp would remove head revision "+itoaU(info.HeadRev))
	}

	// Apply atomically: snapshot, mutate, restore on failure, so a failed
	// cleanup never leaves partially pruned history behind.
	snapshot := make(map[uint64]*Revision, len(s.revisions))
	for k, v := range s.revisions {
		snapshot[k] = v
	}
	cacheSnapshot := make(map[uint64][]byte, len(s.cache))
	for k, v := range s.cache {
		cacheSnapshot[k] = v
	}
	for _, rid := range removed {
		delete(s.revisions, rid)
	}
	s.cache = map[uint64][]byte{}

	if len(s.revisions) != len(snapshot)-len(removed) {
		s.revisions = snapshot
		s.cache = cacheSnapshot
		return nil, newError(ErrInvalidCanonicalState,
			"LimitCleanUp failed and history was restored")
	}
	// Objects are deliberately NOT removed: the object section is a shared
	// content store that retained revisions and EXTENTS-1 COPY operands may
	// still reference. Reclaiming objects is a separate operation.
	return removed, nil
}

// sortUint64 sorts ascending in place.
func sortUint64(a []uint64) {
	for i := 1; i < len(a); i++ {
		for j := i; j > 0 && a[j] < a[j-1]; j-- {
			a[j], a[j-1] = a[j-1], a[j]
		}
	}
}

// CreateFile creates a new file and returns its 16-byte FileId.
func (s *Store) CreateFile(path string, content []byte) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.checkOpen(); err != nil {
		return nil, err
	}
	for _, info := range s.files {
		if info.HasPath && info.Path == path {
			return nil, newError(ErrDuplicateIdentity, "duplicate path "+path)
		}
	}
	id, err := newFileID()
	if err != nil {
		return nil, err
	}
	info := &FileInfo{ID: id, Path: path, HasPath: true}
	s.files[keyOf(id)] = info
	serial := s.addObjectLocked(content)
	rid := s.nextRevID
	s.nextRevID++
	s.revisions[rid] = &Revision{
		RevisionID: rid, FileID: id, ObjectSerial: serial,
		HasObject: true, Path: path, HasPath: true, Presence: Present,
	}
	info.HeadRev = rid
	info.HasHead = true
	return id, nil
}

// ReadFile returns the logical content at the file's accepted revision.
func (s *Store) ReadFile(id []byte) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.checkOpen(); err != nil {
		return nil, err
	}
	info := s.files[keyOf(id)]
	if info == nil {
		return nil, newError(ErrMissingCanonicalReference, "unknown FileId")
	}
	if !info.HasHead {
		return nil, newError(ErrMissingCanonicalReference, "no accepted revision")
	}
	rev := s.revisions[info.HeadRev]
	if rev == nil {
		return nil, newError(ErrMissingCanonicalReference, "no accepted revision")
	}
	if rev.Presence == Deleted {
		return nil, newError(ErrMissingCanonicalReference, "file is deleted")
	}
	if !rev.HasObject {
		return []byte{}, nil
	}
	return s.materializeLocked(rev.ObjectSerial, map[uint64]bool{})
}

// WriteFile replaces file content, producing a new revision.
func (s *Store) WriteFile(id []byte, content []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.checkOpen(); err != nil {
		return err
	}
	info := s.files[keyOf(id)]
	if info == nil {
		return newError(ErrMissingCanonicalReference, "unknown FileId")
	}
	serial := s.addObjectLocked(content)
	rid := s.nextRevID
	s.nextRevID++
	s.revisions[rid] = &Revision{
		RevisionID: rid, FileID: info.ID, ObjectSerial: serial,
		HasObject: true, Path: info.Path, HasPath: info.HasPath, Presence: Present,
	}
	info.HeadRev = rid
	info.HasHead = true
	return nil
}

// DeleteFile marks a file deleted via a new revision.
func (s *Store) DeleteFile(id []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.checkOpen(); err != nil {
		return err
	}
	info := s.files[keyOf(id)]
	if info == nil {
		return newError(ErrMissingCanonicalReference, "unknown FileId")
	}
	rid := s.nextRevID
	s.nextRevID++
	s.revisions[rid] = &Revision{
		RevisionID: rid, FileID: info.ID,
		Path: info.Path, HasPath: info.HasPath, Presence: Deleted,
	}
	info.HeadRev = rid
	info.HasHead = true
	return nil
}

// RenameFile moves a file to a new path, producing a new revision.
func (s *Store) RenameFile(id []byte, newPath string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.checkOpen(); err != nil {
		return err
	}
	info := s.files[keyOf(id)]
	if info == nil {
		return newError(ErrMissingCanonicalReference, "unknown FileId")
	}
	self := keyOf(id)
	for k, other := range s.files {
		if k != self && other.HasPath && other.Path == newPath {
			return newError(ErrDuplicateIdentity, "duplicate path "+newPath)
		}
	}
	var serial uint64
	hasObject := false
	presence := uint8(Present)
	if info.HasHead {
		if old := s.revisions[info.HeadRev]; old != nil {
			presence = old.Presence
			if old.HasObject {
				serial = old.ObjectSerial
				hasObject = true
			}
		}
	}
	rid := s.nextRevID
	s.nextRevID++
	s.revisions[rid] = &Revision{
		RevisionID: rid, FileID: info.ID, ObjectSerial: serial,
		HasObject: hasObject, Path: newPath, HasPath: true, Presence: presence,
	}
	info.Path = newPath
	info.HasPath = true
	info.HeadRev = rid
	info.HasHead = true
	return nil
}

// ListFiles returns every (hexFileId, path) pair; a pathless file yields "".
func (s *Store) ListFiles() [][2]string {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([][2]string, 0, len(s.files))
	for _, info := range s.files {
		p := ""
		if info.HasPath {
			p = info.Path
		}
		out = append(out, [2]string{keyOf(info.ID), p})
	}
	return out
}

// FileExists reports whether the file is present at its accepted revision.
func (s *Store) FileExists(id []byte) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	info := s.files[keyOf(id)]
	if info == nil || !info.HasHead {
		return false
	}
	rev := s.revisions[info.HeadRev]
	return rev != nil && rev.Presence != Deleted
}

// FileIDByPath resolves a path to its FileId.
func (s *Store) FileIDByPath(path string) ([]byte, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, info := range s.files {
		if info.HasPath && info.Path == path {
			return append([]byte(nil), info.ID...), true
		}
	}
	return nil, false
}