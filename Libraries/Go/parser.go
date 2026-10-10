// VSN container parser: streaming, framing-exact, mode-independent.
//
// Parsing never consults a hash, index, cache, checkpoint, or any other
// derived data: the accepted state is derivable from canonical bytes alone.
package vsn

import "strconv"

// ParseStructural decodes the container purely to check framing. It is the
// structural validation entry point and is exposed so callers can validate
// without constructing a Store.
func ParseStructural(data []byte) (*Container, error) { return Parse(data) }

// parseFields decodes a record payload's field stream and enforces the
// strictly-ascending FieldId ordering required by GR-16. `base` is the byte
// offset of the payload within the container, used only for diagnostics.
func parseFields(payload []byte, base int) ([]Field, error) {
	var fields []Field
	err := withRecover(func() error {
		cur := &Cursor{data: payload}
		last := -1
		for cur.Remaining() > 0 {
			start := base + cur.Pos()
			fid := cur.ReadU16()
			ln := cur.ReadUvarint()
			val := cur.Read(int(ln))
			if int(fid) <= last {
				return newErrorAt(ErrInvalidFieldOrdering,
					"FieldId "+strconv.Itoa(int(fid))+" not strictly ascending", start)
			}
			last = int(fid)
			fields = append(fields, Field{Fid: fid, Value: append([]byte(nil), val...)})
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return fields, nil
}

// Parse decodes canonical VSN container bytes.
//
// Unknown records and fields are skipped by their declared length so that a
// format-preserving rewrite remains possible (GR-29..GR-33).
func Parse(data []byte) (*Container, error) {
	var c *Container
	err := withRecover(func() error {
		cur := &Cursor{data: data}
		if cur.Remaining() < 4 {
			panic(newErrorAt(ErrTruncated, "container shorter than magic", 0))
		}
		if string(cur.Read(4)) != string(Magic) {
			panic(newErrorAt(ErrMalformedContainer, "bad magic", 0))
		}
		cfv := cur.ReadU16()
		if cfv != ContainerFormatVersion {
			panic(newError(ErrUnsupportedContainerVersion,
				"unsupported container format version "+strconv.Itoa(int(cfv))))
		}
		ev := cur.ReadU16()
		if ev != EncodingVersion {
			panic(newError(ErrUnsupportedEncodingVersion,
				"unsupported encoding version "+strconv.Itoa(int(ev))))
		}

		// Header fields up to the RecordsEnd marker (FieldId 0x0000).
		for {
			fid := cur.ReadU16()
			ln := cur.ReadUvarint()
			if fid == FidRecordsEnd {
				if ln != 0 {
					panic(newError(ErrMalformedContainer,
						"RecordsEnd length must be 0"))
				}
				break
			}
			cur.Read(int(ln)) // structural header fields are skipped by length
		}

		recs := []Record{}
		for {
			start := cur.Pos()
			rt := cur.ReadU16()
			if rt == RecEndOfRecords {
				break // bare 2-byte end-of-records marker (GR-10/11)
			}
			rl := cur.ReadUvarint()
			payload := cur.Read(int(rl))
			rec := Record{
				RType:      rt,
				Payload:    append([]byte(nil), payload...),
				ByteOffset: start,
			}
			if rt >= RecFileIdentity && rt <= RecStoragePolicy {
				fields, ferr := parseFields(payload, start+2)
				if ferr != nil {
					return ferr
				}
				rec.Fields = fields
			}
			recs = append(recs, rec)
		}

		objs := []ObjectEntry{}
		for {
			start := cur.Pos()
			serial := cur.ReadUvarint()
			if serial == 0 {
				break // end-of-objects marker (GR-37)
			}
			ol := cur.ReadUvarint()
			desc := cur.Read(int(ol))
			objs = append(objs, ObjectEntry{
				Serial:     serial,
				Length:     ol,
				Descriptor: append([]byte(nil), desc...),
				ByteOffset: start,
			})
		}

		rc := cur.ReadUvarint()
		gen := cur.ReadUvarint()

		c = &Container{
			ContainerFormatVersion: cfv,
			EncodingVersion:        ev,
			Records:                recs,
			Objects:                objs,
			TrailerRecordCount:     rc,
			TrailerGeneration:      gen,
			ByteLength:             len(data),
		}
		for i := range recs {
			if recs[i].RType == RecModeDeclaration {
				if m := recs[i].Field(FidMode); m != nil && len(m.Value) > 0 {
					c.Mode = m.Value[0]
					c.HasMode = true
				}
			}
			if recs[i].RType == RecStoragePolicy {
				if sp := recs[i].Field(FidStoragePolicy); sp != nil && len(sp.Value) > 0 {
					c.StoragePolicy = int(sp.Value[0])
				}
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return c, nil
}
