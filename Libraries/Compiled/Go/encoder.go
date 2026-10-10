// Canonical VSN writer (encoder).
//
// Emits only frozen record types, field ids, and representations. Identity is
// never derived from a hash or a byte offset.
package vsn

// rawField is one (FieldId, value) pair pending encoding.
type rawField struct {
	fid   uint16
	value []byte
}

// rawRecord is one record pending encoding.
type rawRecord struct {
	rtype  uint16
	fields []rawField
}

func appendField(dst []byte, fid uint16, value []byte) []byte {
	dst = AppendU16(dst, fid)
	dst = AppendUvarint(dst, uint64(len(value)))
	return append(dst, value...)
}

func appendRecord(dst []byte, rec rawRecord) []byte {
	var payload []byte
	for _, f := range rec.fields {
		payload = appendField(payload, f.fid, f.value)
	}
	dst = AppendU16(dst, rec.rtype)
	dst = AppendUvarint(dst, uint64(len(payload)))
	return append(dst, payload...)
}

// Encode produces canonical container bytes from records, objects, generation.
func Encode(records []rawRecord, objects map[uint64][]byte, generation uint64) []byte {
	out := append([]byte(nil), Magic...)
	out = AppendU16(out, ContainerFormatVersion)
	out = AppendU16(out, EncodingVersion)
	out = appendField(out, FidRecordsEnd, nil) // RecordsEnd header marker

	for _, rec := range records {
		out = appendRecord(out, rec)
	}
	out = AppendU16(out, RecEndOfRecords)

	serials := make([]uint64, 0, len(objects))
	for serial := range objects {
		serials = append(serials, serial)
	}
	sortUint64(serials)
	for _, serial := range serials {
		desc := objects[serial]
		out = AppendUvarint(out, serial)
		out = AppendUvarint(out, uint64(len(desc)))
		out = append(out, desc...)
	}
	out = AppendUvarint(out, 0) // end-of-objects marker

	// GR-13: canonical record count includes all records (including REC_STORAGE_POLICY).
	count := uint64(len(records))
	out = AppendUvarint(out, count)
	out = AppendUvarint(out, generation)
	return out
}
