// Canonical primitives (GR-08, GR-21..GR-26) and the parsed semantic model.
package vsn

import "strconv"

// withRecover runs fn, converting the internal panic-based failure signalling
// used by the primitive decoders into an ordinary Go error.
//
// Panics are used internally so that deeply nested decode paths do not have to
// thread an error return through every helper. Every exported entry point runs
// its body through withRecover, so a caller can never observe the panic: it
// always receives an *Error (or, for truncation, an *Error carrying the frozen
// TRUNCATED identifier). A panic that is not one of ours is re-raised so genuine
// programming errors are never swallowed.
func withRecover(fn func() error) (err error) {
	defer func() {
		r := recover()
		if r == nil {
			return
		}
		if e, ok := r.(*Error); ok {
			err = e
			return
		}
		panic(r)
	}()
	return fn()
}

// AppendU16 appends a big-endian u16 (GR-22).
func AppendU16(dst []byte, v uint16) []byte {
	return append(dst, byte(v>>8), byte(v))
}

// AppendU32 appends a big-endian u32.
func AppendU32(dst []byte, v uint32) []byte {
	return append(dst, byte(v>>24), byte(v>>16), byte(v>>8), byte(v))
}

// AppendU64 appends a big-endian u64.
func AppendU64(dst []byte, v uint64) []byte {
	return append(dst,
		byte(v>>56), byte(v>>48), byte(v>>40), byte(v>>32),
		byte(v>>24), byte(v>>16), byte(v>>8), byte(v))
}

// AppendUvarint appends a minimal LEB128 uvarint (GR-21, GR-23..GR-25).
// Encoding is at most 10 bytes with 7 payload bits per byte.
func AppendUvarint(dst []byte, v uint64) []byte {
	for v >= 0x80 {
		dst = append(dst, byte(v&0x7F)|0x80)
		v >>= 7
	}
	return append(dst, byte(v))
}

// UvarintLen reports how many bytes AppendUvarint would emit.
func UvarintLen(v uint64) int {
	n := 1
	for v >= 0x80 {
		v >>= 7
		n++
	}
	return n
}

// AppendBool appends a single-byte boolean.
func AppendBool(dst []byte, v bool) []byte {
	if v {
		return append(dst, 1)
	}
	return append(dst, 0)
}

// Cursor is a bounds-checked reader over a byte slice. Every read is checked so
// that physical end-of-data is reported as truncation (GR-47) rather than
// silently yielding short data.
type Cursor struct {
	data []byte
	pos  int
}

// NewCursor returns a Cursor positioned at the start of data.
func NewCursor(data []byte) *Cursor { return &Cursor{data: data} }

// Sub returns a Cursor over a sub-slice, used for record payloads.
func (c *Cursor) Sub(length int) *Cursor {
	return &Cursor{data: c.Read(length)}
}

// Remaining reports how many bytes are left.
func (c *Cursor) Remaining() int { return len(c.data) - c.pos }

// Pos reports the current absolute offset within the underlying slice.
func (c *Cursor) Pos() int { return c.pos }

// Read consumes and returns n bytes.
//
// Reaching the physical end of data mid-unit is truncation (GR-47) and is
// signalled by panicking with an *Error carrying ErrTruncated; withRecover
// turns that into a returned error at every public boundary.
func (c *Cursor) Read(n int) []byte {
	if n < 0 || c.Remaining() < n {
		panic(newError(ErrTruncated,
			"need "+strconv.Itoa(n)+" bytes, "+strconv.Itoa(c.Remaining())+" remain"))
	}
	out := c.data[c.pos : c.pos+n]
	c.pos += n
	return out
}

// ReadU16 reads a big-endian u16.
func (c *Cursor) ReadU16() uint16 {
	b := c.Read(2)
	return uint16(b[0])<<8 | uint16(b[1])
}

// ReadU32 reads a big-endian u32.
func (c *Cursor) ReadU32() uint32 {
	b := c.Read(4)
	return uint32(b[0])<<24 | uint32(b[1])<<16 | uint32(b[2])<<8 | uint32(b[3])
}

// ReadU64 reads a big-endian u64.
func (c *Cursor) ReadU64() uint64 {
	b := c.Read(8)
	var v uint64
	for _, x := range b {
		v = v<<8 | uint64(x)
	}
	return v
}

// ReadUvarint reads a minimal LEB128 uvarint and rejects non-minimal
// encodings (GR-24) and overflow past 10 bytes (GR-25).
func (c *Cursor) ReadUvarint() uint64 {
	var value uint64
	var shift uint
	for idx := 0; idx < 10; idx++ {
		b := c.Read(1)[0]
		if idx == 9 {
			// The 10th byte must carry exactly one value bit (0x01).
			// 0x00 is non-minimal; anything larger overflows 64 bits.
			if b == 0x01 {
				return value | (1 << 63)
			}
			panic(newError(ErrMalformedContainer, "uvarint 10th byte invalid"))
		}
		value |= uint64(b&0x7F) << shift
		if b&0x80 == 0 {
			if b == 0 && shift > 0 {
				// A trailing zero group means a shorter canonical encoding exists.
				panic(newError(ErrMalformedContainer, "non-minimal uvarint"))
			}
			return value
		}
		shift += 7
	}
	panic(newError(ErrMalformedContainer, "uvarint exceeds 10 bytes"))
}

// Field is a single record field: a frozen FieldId and its raw value bytes.
type Field struct {
	Fid   uint16
	Value []byte
}

// UvarintValue decodes the field value as a uvarint.
func (f Field) UvarintValue() uint64 {
	c := NewCursor(f.Value)
	v := c.ReadUvarint()
	return v
}

// Record is a parsed record: frozen record type, payload, and decoded fields.
type Record struct {
	RType      uint16
	Payload    []byte
	Fields     []Field
	ByteOffset int
}

// Field returns the field with the given FieldId, or nil when absent.
func (r *Record) Field(fid uint16) *Field {
	for i := range r.Fields {
		if r.Fields[i].Fid == fid {
			return &r.Fields[i]
		}
	}
	return nil
}

// ObjectEntry is a content object located in the object section.
type ObjectEntry struct {
	Serial     uint64
	Length     uint64
	Descriptor []byte
	ByteOffset int
}

// Container is a parsed VSN-1 container.
type Container struct {
	ContainerFormatVersion uint16
	EncodingVersion        uint16
	Records                []Record
	Objects                []ObjectEntry
	TrailerRecordCount     uint64
	TrailerGeneration      uint64
	Mode                   uint8
	HasMode                bool
	ByteLength             int
}