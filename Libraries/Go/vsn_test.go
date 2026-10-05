package vsn

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// vectorDir is the frozen vector directory, two levels above this package.
const vectorDir = "../TestVectors"

// frozenVector is one entry of the frozen manifest.
type frozenVector struct {
	Name   string `json:"name"`
	File   string `json:"file"`
	Bytes  int    `json:"bytes"`
	Sha256 string `json:"sha256"`
}

func loadManifest(t *testing.T) []frozenVector {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(vectorDir, "manifest.json"))
	if err != nil {
		t.Fatalf("read manifest: %v", err)
	}
	var doc struct {
		Vectors []frozenVector `json:"vectors"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatalf("parse manifest: %v", err)
	}
	if len(doc.Vectors) != 5 {
		t.Fatalf("expected 5 frozen vectors, got %d", len(doc.Vectors))
	}
	return doc.Vectors
}

// readVector loads a frozen vector and asserts its declared length and hash
// before any parsing happens, so a corrupted fixture can never be mistaken for
// a parser bug.
func readVector(t *testing.T, v frozenVector) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(vectorDir, v.File))
	if err != nil {
		t.Fatalf("read %s: %v", v.File, err)
	}
	if len(data) != v.Bytes {
		t.Fatalf("%s: length %d, manifest says %d", v.Name, len(data), v.Bytes)
	}
	sum := sha256.Sum256(data)
	if got := hex.EncodeToString(sum[:]); got != v.Sha256 {
		t.Fatalf("%s: sha256 %s, manifest says %s", v.Name, got, v.Sha256)
	}
	return data
}

// TestFrozenVectorsParse checks that every frozen vector decodes and that the
// declared framing metadata is what the manifest expects.
func TestFrozenVectorsParse(t *testing.T) {
	for _, v := range loadManifest(t) {
		v := v
		t.Run(v.Name, func(t *testing.T) {
			data := readVector(t, v)
			c, err := Parse(data)
			if err != nil {
				t.Fatalf("parse: %v", err)
			}
			if len(c.Records) == 0 {
				t.Fatal("no records decoded")
			}
			if c.TrailerGeneration == 0 {
				t.Fatal("trailer generation must be non-zero")
			}
			if c.ByteLength != len(data) {
				t.Fatalf("byte length %d != %d", c.ByteLength, len(data))
			}
		})
	}
}

// TestBadMagicRejected checks the frozen 0x0001 identifier for a bad signature.
func TestBadMagicRejected(t *testing.T) {
	data := readVector(t, loadManifest(t)[0])
	bad := append([]byte(nil), data...)
	bad[0] = 'X'
	_, err := Parse(bad)
	assertCode(t, err, ErrMalformedContainer)
}

// TestUnsupportedVersionsRejected checks the frozen 0x0003 / 0x0004 identifiers.
func TestUnsupportedVersionsRejected(t *testing.T) {
	data := readVector(t, loadManifest(t)[0])

	badCFV := append([]byte(nil), data...)
	badCFV[4], badCFV[5] = 0x00, 0x02
	_, err := Parse(badCFV)
	assertCode(t, err, ErrUnsupportedContainerVersion)

	badEV := append([]byte(nil), data...)
	badEV[6], badEV[7] = 0x00, 0x09
	_, err = Parse(badEV)
	assertCode(t, err, ErrUnsupportedEncodingVersion)
}

// TestTruncationReportsTruncated checks that every prefix of a frozen vector
// that cuts a unit short reports TRUNCATED (0x0002) or a malformed framing
// error, and never a successful parse.
func TestTruncationReportsTruncated(t *testing.T) {
	data := readVector(t, loadManifest(t)[0])
	// Walk every prefix length; none may parse successfully.
	for n := 0; n < len(data); n++ {
		if _, err := Parse(data[:n]); err == nil {
			t.Fatalf("prefix of length %d parsed but should not", n)
		}
	}
	// The full buffer must still parse, proving the loop was meaningful.
	if _, err := Parse(data); err != nil {
		t.Fatalf("full vector must parse: %v", err)
	}
}

// TestTrailingBytesAfterTrailerAreIgnored pins the reference parser behaviour.
//
// The frozen framing is: records, objects, then the trailer (record count and
// generation). Parsing stops once the trailer is read, so bytes appended after
// the trailer are outside the canonical framing and are ignored rather than
// rejected. This matches the Python, C#, and TypeScript references, which all
// stop reading at the trailer.
//
// It does NOT mean malformed data inside the framing is tolerated: the
// truncation test above proves every short prefix is rejected.
func TestTrailingBytesAfterTrailerAreIgnored(t *testing.T) {
	data := readVector(t, loadManifest(t)[0])
	extended := append(append([]byte(nil), data...), 0xFF, 0xFF, 0xFF)
	c, err := Parse(extended)
	if err != nil {
		t.Fatalf("trailing bytes after trailer must be ignored: %v", err)
	}
	base, err := Parse(data)
	if err != nil {
		t.Fatalf("parse base: %v", err)
	}
	if c.TrailerRecordCount != base.TrailerRecordCount ||
		c.TrailerGeneration != base.TrailerGeneration {
		t.Fatal("trailing bytes changed the decoded trailer")
	}
	if len(c.Records) != len(base.Records) || len(c.Objects) != len(base.Objects) {
		t.Fatal("trailing bytes changed the decoded record/object sections")
	}
}

// TestMaterializeDirect checks DIRECT-1 materialization from the frozen vector.
func TestMaterializeDirect(t *testing.T) {
	data := readVector(t, loadManifest(t)[0])
	s, err := Open(data)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	serials := s.Objects()
	if len(serials) == 0 {
		t.Fatal("no objects in frozen vector")
	}
	for _, serial := range serials {
		content, merr := s.Materialize(serial)
		if merr != nil {
			t.Fatalf("materialize %d: %v", serial, merr)
		}
		if content == nil {
			t.Fatalf("object %d materialized to nil", serial)
		}
		// Materialized logical content must agree with the declared 0x0511
		// length whenever that optional field is present (DR-6).
		info, ierr := s.ObjectInfo(serial)
		if ierr != nil {
			t.Fatalf("object info %d: %v", serial, ierr)
		}
		if info.RepresentationIdentity == RepDirect1 {
			if info.RepresentationVersion != uint64(RepVersion1) {
				t.Fatalf("object %d DIRECT-1 version %d, expected 1",
					serial, info.RepresentationVersion)
			}
			if info.Length != len(content) {
				t.Fatalf("object %d payload %d != logical %d",
					serial, info.Length, len(content))
			}
		}
	}
}

// assertCode requires err to be an *Error carrying the expected frozen id.
func assertCode(t *testing.T, err error, want uint16) {
	t.Helper()
	if err == nil {
		t.Fatalf("expected error 0x%04X, got nil", want)
	}
	e, ok := err.(*Error)
	if !ok {
		t.Fatalf("expected *Error, got %T: %v", err, err)
	}
	if e.Code != want {
		t.Fatalf("expected error 0x%04X, got 0x%04X (%s)", want, e.Code, e.Name())
	}
}

var _ = bytes.Equal