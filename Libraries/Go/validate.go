// Validation levels (Structural / Semantic / Recovery / Content).
//
// Validation reads canonical VSN state only. Derived indexes and caches are
// never consulted, so they can never become an authority for anything.
package vsn

// ValidateStructural checks framing: magic, versions, lengths, ordering.
func ValidateStructural(data []byte) error {
	_, err := Parse(data)
	return err
}

// ValidateSemantic checks identity uniqueness and reference integrity.
//
// It adds no new protocol identifier: it reports the frozen codes the parser
// already defines (000A duplicate identity, 0008 missing object, 0009 missing
// canonical reference, 0001 reserved value).
func ValidateSemantic(data []byte) error {
	c, err := Parse(data)
	if err != nil {
		return err
	}
	if err := checkMode(c); err != nil {
		return err
	}
	seenFile := map[string]bool{}
	seenRev := map[uint64]bool{}
	seenObj := map[uint64]bool{}
	for i := range c.Records {
		rec := &c.Records[i]
		switch rec.RType {
		case RecFileIdentity:
			f := rec.Field(FidFileID)
			if f == nil {
				return newError(ErrMissingCanonicalReference,
					"FileIdentity missing FileId")
			}
			k := keyOf(f.Value)
			if seenFile[k] {
				return newError(ErrDuplicateIdentity, "duplicate FileIdentity")
			}
			seenFile[k] = true
		case RecRevision:
			f := rec.Field(FidRevID)
			if f == nil {
				return newError(ErrMissingCanonicalReference,
					"Revision missing RevisionId")
			}
			rid := f.UvarintValue()
			if seenRev[rid] {
				return newError(ErrDuplicateIdentity,
					"duplicate RevisionId "+itoaU(rid))
			}
			seenRev[rid] = true
		case RecContentObject:
			f := rec.Field(FidObjectSerial)
			if f == nil {
				return newError(ErrMissingCanonicalReference,
					"ContentObject missing ObjectSerial")
			}
			sid := f.UvarintValue()
			if seenObj[sid] {
				return newError(ErrDuplicateIdentity,
					"duplicate ObjectSerial "+itoaU(sid))
			}
			seenObj[sid] = true
		}
	}
	return checkReferences(c)
}

// checkMode enforces exactly one ModeDeclaration with a reserved, known value,
// and GR-43: ENTERPRISE must not use EXTENTS-1 reconstruction.
func checkMode(c *Container) error {
	count := 0
	for i := range c.Records {
		if c.Records[i].RType == RecModeDeclaration {
			count++
		}
	}
	if count != 1 {
		return newError(ErrInvalidCanonicalState,
			"expected exactly one ModeDeclaration, got "+itoaU(uint64(count)))
	}
	if !c.HasMode {
		return newError(ErrInvalidCanonicalState,
			"ModeDeclaration missing mode value")
	}
	if c.Mode != ModeModern && c.Mode != ModeEnterprise {
		return newError(ErrMalformedContainer,
			"reserved mode value 0x"+hexU16(uint16(c.Mode)))
	}
	if c.Mode == ModeEnterprise {
		for _, o := range c.Objects {
			ident, _, _, err := ParseObjectHeader(o.Descriptor)
			if err != nil {
				return err
			}
			if ident == RepExtents1 {
				return newError(ErrInvalidCanonicalState,
					"ENTERPRISE mode forbids EXTENTS-1 (GR-43)")
			}
		}
	}
	return nil
}

// checkReferences verifies every Revision/FileHead names an existing identity.
func checkReferences(c *Container) error {
	fileIDs := map[string]bool{}
	revIDs := map[uint64]bool{}
	objIDs := map[uint64]bool{}
	for i := range c.Records {
		rec := &c.Records[i]
		switch rec.RType {
		case RecFileIdentity:
			if f := rec.Field(FidFileID); f != nil {
				fileIDs[keyOf(f.Value)] = true
			}
		case RecRevision:
			if f := rec.Field(FidRevID); f != nil {
				revIDs[f.UvarintValue()] = true
			}
		}
	}
	for _, o := range c.Objects {
		objIDs[o.Serial] = true
	}
	for i := range c.Records {
		rec := &c.Records[i]
		switch rec.RType {
		case RecRevision:
			f := rec.Field(FidRevFileID)
			if f == nil || !fileIDs[keyOf(f.Value)] {
				return newError(ErrMissingCanonicalReference,
					"Revision references missing FileId")
			}
			if o := rec.Field(FidRevObjectSerial); o != nil &&
				!objIDs[o.UvarintValue()] {
				return newError(ErrMissingObject,
					"Revision references missing ObjectSerial")
			}
		case RecFileHead:
			f := rec.Field(FidHeadFileID)
			if f == nil || !fileIDs[keyOf(f.Value)] {
				return newError(ErrMissingCanonicalReference,
					"FileHead references missing FileId")
			}
			r := rec.Field(FidHeadRevID)
			if r == nil || !revIDs[r.UvarintValue()] {
				return newError(ErrMissingCanonicalReference,
					"FileHead references missing RevisionId")
			}
		}
	}
	return nil
}

// ValidateContent checks that every object materializes and that a present
// 0x0511 agrees with the materialized length (DR-6).
//
// Absence of 0x0511 stays fully valid (SR-27). A mismatch is invalid canonical
// state (0x000C), matching frozen vector EXT-12.
func ValidateContent(data []byte) error {
	c, err := Parse(data)
	if err != nil {
		return err
	}
	declared := map[uint64]uint64{}
	for i := range c.Records {
		rec := &c.Records[i]
		if rec.RType != RecContentObject {
			continue
		}
		sf := rec.Field(FidObjectSerial)
		zf := rec.Field(FidObjectSize)
		if sf != nil && zf != nil {
			declared[sf.UvarintValue()] = zf.UvarintValue()
		}
	}
	s, err := Open(data)
	if err != nil {
		return err
	}
	for _, serial := range s.Objects() {
		content, merr := s.Materialize(serial)
		if merr != nil {
			return merr
		}
		if want, ok := declared[serial]; ok && want != uint64(len(content)) {
			return newError(ErrInvalidCanonicalState,
				"declared size "+itoaU(want)+" does not match materialized length "+
					itoaU(uint64(len(content)))+" for ObjectSerial "+itoaU(serial)+
					" (DR-6)")
		}
	}
	return nil
}

// ValidateLevel selects a validation depth, mirroring the reference levels.
type ValidateLevel string

const (
	// LevelStructural checks framing only.
	LevelStructural ValidateLevel = "Structural"
	// LevelSemantic checks identity and references.
	LevelSemantic ValidateLevel = "Semantic"
	// LevelRecovery checks that a CommitMarker can be accepted.
	LevelRecovery ValidateLevel = "Recovery"
	// LevelContent checks materialization and declared sizes.
	LevelContent ValidateLevel = "Content"
	// LevelFull runs every level.
	LevelFull ValidateLevel = "Full"
)

// Validate runs validation at the requested depth.
func Validate(data []byte, level ValidateLevel) error {
	switch level {
	case LevelStructural:
		return ValidateStructural(data)
	case LevelSemantic:
		if err := ValidateStructural(data); err != nil {
			return err
		}
		return ValidateSemantic(data)
	case LevelRecovery:
		if err := ValidateSemantic(data); err != nil {
			return err
		}
		r, err := Recover(data)
		if err != nil {
			return err
		}
		if !r.Recovered {
			return newError(ErrInvalidCanonicalState,
				"recovery status "+r.Status)
		}
		return nil
	case LevelContent:
		if err := ValidateSemantic(data); err != nil {
			return err
		}
		return ValidateContent(data)
	case LevelFull:
		if err := ValidateSemantic(data); err != nil {
			return err
		}
		r, err := Recover(data)
		if err != nil {
			return err
		}
		if !r.Recovered {
			return newError(ErrInvalidCanonicalState,
				"recovery status "+r.Status)
		}
		return ValidateContent(data)
	default:
		return newError(ErrInvalidCanonicalState,
			"unknown validation level "+string(level))
	}
}