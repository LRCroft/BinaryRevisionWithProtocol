// Container builder (Builder capability): the low-level construction path.
//
// Unlike Store it does not derive revisions from file operations, so a caller
// can express any canonical layout exactly, including EXTENTS-1 dependencies.
package vsn

// Builder accumulates records and objects, then produces canonical bytes.
type Builder struct {
	Mode       uint8
	Records    []rawRecord
	Objects    map[uint64][]byte
	serialSet  map[uint64]bool
	revSet     map[uint64]bool
	fileSet    map[string]bool
	nextSerial uint64
}

// NewBuilder returns an empty builder in the given mode.
func NewBuilder(mode uint8) *Builder {
	return &Builder{
		Mode:       mode,
		Objects:    map[uint64][]byte{},
		serialSet:  map[uint64]bool{},
		revSet:     map[uint64]bool{},
		fileSet:    map[string]bool{},
		nextSerial: 1,
	}
}

// AddFile appends a FileIdentity record. fileID must be 16 bytes.
func (b *Builder) AddFile(fileID []byte) error {
	if len(fileID) != 16 {
		return newError(ErrMalformedContainer, "FileId must be 16 bytes")
	}
	k := keyOf(fileID)
	if b.fileSet[k] {
		return newError(ErrDuplicateIdentity, "duplicate FileId")
	}
	b.fileSet[k] = true
	b.Records = append(b.Records, rawRecord{
		rtype:  RecFileIdentity,
		fields: []rawField{{fid: FidFileID, value: append([]byte(nil), fileID...)}},
	})
	return nil
}

// AddRevision appends a Revision record referencing a declared FileId.
func (b *Builder) AddRevision(fileID []byte, revID uint64, serial uint64,
	hasSerial bool, path string, hasPath bool, presence uint8) error {
	if !b.fileSet[keyOf(fileID)] {
		return newError(ErrMissingCanonicalReference, "FileId not declared")
	}
	if b.revSet[revID] {
		return newError(ErrDuplicateIdentity, "duplicate RevisionId")
	}
	b.revSet[revID] = true
	fields := []rawField{
		{fid: FidRevID, value: AppendUvarint(nil, revID)},
		{fid: FidRevFileID, value: append([]byte(nil), fileID...)},
	}
	if hasSerial {
		fields = append(fields, rawField{
			fid: FidRevObjectSerial, value: AppendUvarint(nil, serial)})
	}
	if hasPath {
		fields = append(fields, rawField{fid: FidRevPath, value: []byte(path)})
	}
	fields = append(fields, rawField{fid: FidRevPresence, value: []byte{presence}})
	b.Records = append(b.Records, rawRecord{rtype: RecRevision, fields: fields})
	return nil
}

// AddObject stores content as a DIRECT-1 object and returns its serial.
func (b *Builder) AddObject(content []byte) (uint64, error) {
	return b.AddObjectWithSerial(content, 0, false)
}

// AddObjectWithSerial stores content under an explicit serial.
func (b *Builder) AddObjectWithSerial(content []byte, serial uint64,
	hasSerial bool) (uint64, error) {
	if !hasSerial {
		serial = b.nextSerial
	}
	if b.serialSet[serial] {
		return 0, newError(ErrDuplicateIdentity, "duplicate ObjectSerial")
	}
	b.serialSet[serial] = true
	if serial >= b.nextSerial {
		b.nextSerial = serial + 1
	}
	b.Objects[serial] = Direct1Descriptor(content)
	b.Records = append(b.Records, rawRecord{
		rtype: RecContentObject,
		fields: []rawField{
			{fid: FidObjectSerial, value: AppendUvarint(nil, serial)},
			// 0x0511 declares the LOGICAL length, which for DIRECT-1 equals the
			// content length (SR-27/29).
			{fid: FidObjectSize, value: AppendUvarint(nil, uint64(len(content)))},
		},
	})
	return serial, nil
}

// AddRawObject stores an explicit descriptor under a given serial.
//
// It is used for EXTENTS-1, whose declared logical length is determined by
// materialization and generally differs from the descriptor length. When the
// logical length cannot be resolved (missing dependency, cycle, unsupported
// representation) 0x0511 is omitted, which stays fully valid under SR-27.
func (b *Builder) AddRawObject(descriptor []byte, serial uint64) error {
	if b.serialSet[serial] {
		return newError(ErrDuplicateIdentity, "duplicate ObjectSerial")
	}
	b.serialSet[serial] = true
	if serial >= b.nextSerial {
		b.nextSerial = serial + 1
	}
	b.Objects[serial] = append([]byte(nil), descriptor...)

	fields := []rawField{
		{fid: FidObjectSerial, value: AppendUvarint(nil, serial)},
	}
	if logical, err := b.logicalContent(serial); err == nil {
		fields = append(fields, rawField{
			fid: FidObjectSize, value: AppendUvarint(nil, uint64(len(logical)))})
	}
	b.Records = append(b.Records, rawRecord{rtype: RecContentObject, fields: fields})
	return nil
}

// SetHead appends a FileHead record.
func (b *Builder) SetHead(fileID []byte, revID uint64) error {
	if !b.fileSet[keyOf(fileID)] {
		return newError(ErrMissingCanonicalReference, "FileId not declared")
	}
	if !b.revSet[revID] {
		return newError(ErrMissingCanonicalReference, "RevisionId not declared")
	}
	b.Records = append(b.Records, rawRecord{
		rtype: RecFileHead,
		fields: []rawField{
			{fid: FidHeadFileID, value: append([]byte(nil), fileID...)},
			{fid: FidHeadRevID, value: AppendUvarint(nil, revID)},
		},
	})
	return nil
}

// Build produces canonical bytes, prepending ModeDeclaration and appending the
// CommitMarker so the result always has an accepted state.
func (b *Builder) Build(generation uint64) []byte {
	records := make([]rawRecord, 0, len(b.Records)+2)
	records = append(records, rawRecord{
		rtype:  RecModeDeclaration,
		fields: []rawField{{fid: FidMode, value: []byte{b.Mode}}},
	})
	records = append(records, b.Records...)
	records = append(records, rawRecord{
		rtype:  RecCommitMarker,
		fields: []rawField{{fid: FidCommitGen, value: AppendUvarint(nil, generation)}},
	})
	return Encode(records, b.Objects, generation)
}

// logicalContent materializes an object being built, resolving dependencies
// against descriptors accumulated so far.
func (b *Builder) logicalContent(serial uint64) ([]byte, error) {
	return b.logicalContentVisited(serial, map[uint64]bool{})
}

func (b *Builder) logicalContentVisited(serial uint64,
	visited map[uint64]bool) ([]byte, error) {
	if visited[serial] {
		return nil, newError(ErrInvalidCanonicalState, "dependency cycle")
	}
	desc := b.Objects[serial]
	if desc == nil {
		return nil, newError(ErrMissingObject, "missing object "+itoaU(serial))
	}
	ident, ver, rem, err := ParseObjectHeader(desc)
	if err != nil {
		return nil, err
	}
	switch {
	case ident == RepDirect1 && ver == uint64(RepVersion1):
		return MaterializeDirect(rem), nil
	case ident == RepExtents1 && ver == uint64(RepVersion1):
		next := map[uint64]bool{}
		for k := range visited {
			next[k] = true
		}
		next[serial] = true
		return MaterializeExtents(rem, func(dep uint64) ([]byte, error) {
			return b.logicalContentVisited(dep, next)
		}, next)
	default:
		return nil, newError(ErrUnsupportedRepresentation,
			"unsupported representation 0x"+hexU16(ident)+" v"+itoaU(ver))
	}
}

// --- Interop scenario builder ---

// scenarioFID builds the deterministic 16-byte FileId the scenarios use.
func scenarioFID(b byte) []byte {
	out := make([]byte, 16)
	for i := range out {
		out[i] = b
	}
	return out
}

// Extents1Descriptor builds an EXTENTS-1 v1 descriptor from raw operations.
func Extents1Descriptor(operations [][]byte) []byte {
	out := AppendU16(nil, RepExtents1)
	out = AppendUvarint(out, uint64(RepVersion1))
	out = AppendUvarint(out, uint64(len(operations)))
	for _, op := range operations {
		out = append(out, op...)
	}
	return out
}

// LiteralOperation builds LITERAL(bytes) = [lit, NUMERIC 0] (DR-3, VR-23).
func LiteralOperation(content []byte) []byte {
	out := AppendUvarint(nil, OpNested)
	out = AppendUvarint(out, 2)
	out = AppendUvarint(out, OpLiteralBytes)
	out = AppendUvarint(out, uint64(len(content)))
	out = append(out, content...)
	out = AppendUvarint(out, OpNumeric)
	out = AppendUvarint(out, 0)
	return out
}

// CopyOperation builds COPY(source, offset, length) = [src, num, num].
func CopyOperation(serial, offset, length uint64) []byte {
	out := AppendUvarint(nil, OpNested)
	out = AppendUvarint(out, 3)
	out = AppendUvarint(out, OpObjectSource)
	out = AppendUvarint(out, serial)
	out = AppendUvarint(out, OpNumeric)
	out = AppendUvarint(out, offset)
	out = AppendUvarint(out, OpNumeric)
	out = AppendUvarint(out, length)
	return out
}

// BuildScenario deterministically builds one of the four shared interop
// scenarios. The bytes must match the reference implementation exactly; the
// corpus probe compares them byte-for-byte, which is what makes this real
// interoperability evidence rather than self-consistency.
func BuildScenario(name string) ([]byte, error) {
	switch name {
	case "basic":
		b := NewBuilder(ModeModern)
		f := scenarioFID(0x01)
		if err := b.AddFile(f); err != nil {
			return nil, err
		}
		s, err := b.AddObject([]byte("hello vsn\n"))
		if err != nil {
			return nil, err
		}
		if err := b.AddRevision(f, 1, s, true, "hello.txt", true, Present); err != nil {
			return nil, err
		}
		if err := b.SetHead(f, 1); err != nil {
			return nil, err
		}
		return b.Build(1), nil

	case "extents":
		b := NewBuilder(ModeModern)
		a, c := scenarioFID(0x02), scenarioFID(0x03)
		for _, f := range [][]byte{a, c} {
			if err := b.AddFile(f); err != nil {
				return nil, err
			}
		}
		s1, err := b.AddObjectWithSerial([]byte("hello vsn\n"), 1, true)
		if err != nil {
			return nil, err
		}
		desc := Extents1Descriptor([][]byte{
			CopyOperation(1, 0, 10),
			LiteralOperation([]byte("!!")),
		})
		if err := b.AddRawObject(desc, 2); err != nil {
			return nil, err
		}
		if err := b.AddRevision(a, 1, s1, true, "a.txt", true, Present); err != nil {
			return nil, err
		}
		if err := b.AddRevision(c, 2, 2, true, "b.txt", true, Present); err != nil {
			return nil, err
		}
		if err := b.SetHead(a, 1); err != nil {
			return nil, err
		}
		if err := b.SetHead(c, 2); err != nil {
			return nil, err
		}
		return b.Build(2), nil

	case "enterprise":
		b := NewBuilder(ModeEnterprise)
		f := scenarioFID(0x04)
		if err := b.AddFile(f); err != nil {
			return nil, err
		}
		s, err := b.AddObject([]byte("enterprise"))
		if err != nil {
			return nil, err
		}
		if err := b.AddRevision(f, 1, s, true, "e.txt", true, Present); err != nil {
			return nil, err
		}
		if err := b.SetHead(f, 1); err != nil {
			return nil, err
		}
		return b.Build(1), nil

	case "multifile":
		// Binary content including NUL and 0xFF, plus an empty object.
		b := NewBuilder(ModeModern)
		f1, f2, f3 := scenarioFID(0x05), scenarioFID(0x06), scenarioFID(0x07)
		for _, f := range [][]byte{f1, f2, f3} {
			if err := b.AddFile(f); err != nil {
				return nil, err
			}
		}
		if _, err := b.AddObjectWithSerial(
			[]byte{0x00, 0x01, 0xFF, 0x00, 0x7F}, 1, true); err != nil {
			return nil, err
		}
		if _, err := b.AddObjectWithSerial(
			[]byte("plain text"), 2, true); err != nil {
			return nil, err
		}
		if _, err := b.AddObjectWithSerial([]byte{}, 3, true); err != nil {
			return nil, err
		}
		// Record order is part of the canonical bytes: every Revision is emitted
		// first, then every FileHead, matching the reference. Fields within a
		// record must stay ascending by FieldId (GR-16).
		for _, spec := range []struct {
			f    []byte
			rev  uint64
			ser  uint64
			path string
		}{
			{f1, 1, 1, "bin.dat"},
			{f2, 2, 2, "text.txt"},
			{f3, 3, 3, "empty.txt"},
		} {
			if err := b.AddRevision(spec.f, spec.rev, spec.ser, true,
				spec.path, true, Present); err != nil {
				return nil, err
			}
		}
		for _, spec := range []struct {
			f   []byte
			rev uint64
		}{
			{f1, 1}, {f2, 2}, {f3, 3},
		} {
			if err := b.SetHead(spec.f, spec.rev); err != nil {
				return nil, err
			}
		}
		return b.Build(3), nil
	}
	return nil, newError(ErrInvalidCanonicalState, "unknown scenario "+name)
}