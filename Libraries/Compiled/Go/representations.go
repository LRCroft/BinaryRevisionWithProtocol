// DIRECT-1 and EXTENTS-1 materialization (DR-0..DR-12).
//
// An object descriptor payload begins with Representation Identity (u16be)
// followed by Representation Version (uvarint); the remainder is the
// representation payload. Materialization never depends on a
// RepresentationDescriptor record.
package vsn

// Resolver returns the logical content of a dependency object.
type Resolver func(serial uint64) ([]byte, error)

// ParseObjectHeader splits a descriptor into (identity, version, remainder).
func ParseObjectHeader(desc []byte) (ident uint16, version uint64, rem []byte, err error) {
	e := withRecover(func() error {
		c := &Cursor{data: desc}
		ident = c.ReadU16()
		version = c.ReadUvarint()
		rem = desc[c.Pos():]
		return nil
	})
	return ident, version, rem, e
}

// Direct1Descriptor builds a DIRECT-1 v1 descriptor (DR-0 header + content).
func Direct1Descriptor(content []byte) []byte {
	out := AppendU16(nil, RepDirect1)
	out = AppendUvarint(out, uint64(RepVersion1))
	return append(out, content...)
}

// MaterializeDirect returns the DIRECT-1 payload verbatim.
//
// The result is always a non-nil slice: a zero-length logical content is valid
// (an empty file) and must materialize to an empty byte sequence, not nil.
func MaterializeDirect(rem []byte) []byte {
	out := make([]byte, len(rem))
	copy(out, rem)
	return out
}

// operand is one EXTENTS-1 operand.
type operand struct {
	kind    uint64
	literal []byte
	num     uint64
	nested  []operand
}

// readOperand decodes a single operand (VR-23).
func readOperand(c *Cursor) operand {
	kind := c.ReadUvarint()
	switch kind {
	case OpLiteralBytes:
		ln := c.ReadUvarint()
		return operand{kind: kind, literal: append([]byte(nil), c.Read(int(ln))...)}
	case OpObjectSource:
		return operand{kind: kind, num: c.ReadUvarint()}
	case OpNumeric:
		return operand{kind: kind, num: c.ReadUvarint()}
	case OpNested:
		n := c.ReadUvarint()
		nested := make([]operand, 0, n)
		for i := uint64(0); i < n; i++ {
			nested = append(nested, readOperand(c))
		}
		return operand{kind: kind, nested: nested}
	default:
		panic(newError(ErrUnsupportedRepresentation,
			"unknown operand kind "+itoaU(kind)))
	}
}

// applyOperation executes one operation's operand list.
//
//	COPY(source, offset, length) = [src, num, num]
//	LITERAL(bytes)               = [lit, num(0)]  (the reserved NUMERIC 0)
func applyOperation(ops []operand, resolve Resolver, visited map[uint64]bool) ([]byte, error) {
	var out []byte
	err := withRecover(func() error {
		if len(ops) == 0 {
			panic(newError(ErrInvalidCanonicalState, "empty operation"))
		}
		head := ops[0]
		switch head.kind {
		case OpObjectSource:
			if len(ops) != 3 || ops[1].kind != OpNumeric || ops[2].kind != OpNumeric {
				panic(newError(ErrInvalidCanonicalState, "malformed COPY operation"))
			}
			source := head.num
			if visited[source] {
				panic(newError(ErrInvalidCanonicalState,
					"dependency cycle at ObjectSerial "+itoaU(source)))
			}
			src, rerr := resolve(source)
			if rerr != nil {
				return rerr
			}
			off, length := ops[1].num, ops[2].num
			if off+length > uint64(len(src)) {
				panic(newError(ErrInvalidCanonicalState, "COPY range out of bounds"))
			}
			out = append(out, src[off:off+length]...)
			return nil
		case OpLiteralBytes:
			out = append(out, head.literal...)
			return nil
		default:
			panic(newError(ErrInvalidCanonicalState,
				"unknown operation head kind "+itoaU(head.kind)))
		}
	})
	return out, err
}

// MaterializeExtents materializes an EXTENTS-1 operation collection. The
// dependency graph must be finite and acyclic; the caller supplies `visited`.
func MaterializeExtents(rem []byte, resolve Resolver, visited map[uint64]bool) (out []byte, err error) {
	err = withRecover(func() error {
		c := &Cursor{data: rem}
		opCount := c.ReadUvarint()
		var acc []byte
		for i := uint64(0); i < opCount; i++ {
			kind := c.ReadUvarint()
			if kind != OpNested {
				panic(newError(ErrInvalidCanonicalState,
					"operation must be NESTED, got kind "+itoaU(kind)))
			}
			n := c.ReadUvarint()
			ops := make([]operand, 0, n)
			for j := uint64(0); j < n; j++ {
				ops = append(ops, readOperand(c))
			}
			part, aerr := applyOperation(ops, resolve, visited)
			if aerr != nil {
				return aerr
			}
			acc = append(acc, part...)
		}
		if c.Remaining() != 0 {
			panic(newError(ErrInvalidCanonicalState,
				"trailing bytes after EXTENTS-1 operations"))
		}
		out = acc
		return nil
	})
	return out, err
}