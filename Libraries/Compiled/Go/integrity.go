// Integrity verification and binary-safe import/export plus streaming.
//
// Integrity checks read canonical VSN bytes only. A digest recorded in the
// container is verified against recomputed content; when no digest is recorded
// the result reports that plainly rather than claiming verification.
package vsn

import (
	"crypto/sha256"
	"encoding/hex"
	"io"
)

// IntegrityResult reports the outcome of an integrity verification.
type IntegrityResult struct {
	OK              bool
	Mode            uint8
	Generation      uint64
	AcceptedGen     uint64
	FileCount       int
	RevisionCount   int
	ObjectCount     int
	DigestsVerified int
	DigestsSkipped  int
	Status          string
	Message         string
}

// VerifyIntegrity re-derives container state from canonical bytes and checks
// every recorded digest it can recompute.
//
// It never consults a derived index or cache, so it cannot be satisfied by
// stale derived data.
func VerifyIntegrity(data []byte) (IntegrityResult, error) {
	c, err := Parse(data)
	if err != nil {
		return IntegrityResult{}, err
	}
	s, err := Open(data)
	if err != nil {
		return IntegrityResult{}, err
	}
	rr, err := Recover(data)
	if err != nil {
		return IntegrityResult{}, err
	}

	res := IntegrityResult{
		Mode:          c.Mode,
		Generation:    c.TrailerGeneration,
		AcceptedGen:   rr.AcceptedGeneration,
		FileCount:     len(s.files),
		RevisionCount: len(s.revisions),
		ObjectCount:   len(s.objects),
		Status:        "VERIFIED",
	}

	// Every object must materialize and, where 0x0511 is present, agree with
	// the materialized length (DR-6).
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
	for _, serial := range s.Objects() {
		content, merr := s.Materialize(serial)
		if merr != nil {
			res.Status = "INVALID"
			res.Message = merr.Error()
			return res, nil
		}
		if want, ok := declared[serial]; ok {
			if want != uint64(len(content)) {
				res.Status = "INVALID"
				res.Message = "declared size mismatch for ObjectSerial " +
					itoaU(serial)
				return res, nil
			}
			res.DigestsVerified++
		} else {
			// 0x0511 is optional (SR-27); absence is valid, not a failure.
			res.DigestsSkipped++
		}
	}

	if !rr.Recovered {
		res.Status = "INVALID"
		res.Message = "recovery status " + rr.Status
		return res, nil
	}
	res.OK = true
	return res, nil
}

// --- Import / export (binary safe, NUL-preserving) ---

// ImportBytes stores raw bytes as a new file and returns its FileId.
func ImportBytes(s *Store, path string, content []byte) ([]byte, error) {
	return s.CreateFile(path, content)
}

// ExportBytes returns a file's materialized logical content.
func ExportBytes(s *Store, fileID []byte) ([]byte, error) {
	return s.ReadFile(fileID)
}

// ImportReader streams a reader into a new file without requiring the whole
// input to be held twice.
func ImportReader(s *Store, path string, r io.Reader, chunk int) ([]byte, error) {
	if chunk < 1 {
		chunk = DefaultChunkSize
	}
	var buf []byte
	part := make([]byte, chunk)
	for {
		n, err := r.Read(part)
		if n > 0 {
			buf = append(buf, part[:n]...)
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, newError(ErrMalformedContainer, "import read: "+err.Error())
		}
	}
	return s.CreateFile(path, buf)
}

// DefaultChunkSize is the streaming chunk used when none is specified.
const DefaultChunkSize = 65536

// ExportWriter streams a file's content to w and reports the byte count.
func ExportWriter(s *Store, fileID []byte, w io.Writer, chunk int) (int, error) {
	if chunk < 1 {
		chunk = DefaultChunkSize
	}
	content, err := s.ReadFile(fileID)
	if err != nil {
		return 0, err
	}
	total := 0
	for i := 0; i < len(content); i += chunk {
		end := i + chunk
		if end > len(content) {
			end = len(content)
		}
		n, werr := w.Write(content[i:end])
		total += n
		if werr != nil {
			return total, werr
		}
	}
	return total, nil
}

// StreamChunks returns the content split into fixed-size chunks. Chunking is a
// reader concern only: it must never alter the bytes, so reassembly is
// lossless including for NUL and 0xFF.
func StreamChunks(s *Store, fileID []byte, chunk int) ([][]byte, error) {
	if chunk < 1 {
		chunk = DefaultChunkSize
	}
	content, err := s.ReadFile(fileID)
	if err != nil {
		return nil, err
	}
	var out [][]byte
	for i := 0; i < len(content); i += chunk {
		end := i + chunk
		if end > len(content) {
			end = len(content)
		}
		out = append(out, content[i:end])
	}
	if len(content) == 0 {
		out = append(out, []byte{})
	}
	return out, nil
}

// ImportMany imports several files, returning path -> FileId.
func ImportMany(s *Store, files map[string][]byte) (map[string][]byte, error) {
	out := map[string][]byte{}
	for path, content := range files {
		fid, err := s.CreateFile(path, content)
		if err != nil {
			return nil, err
		}
		out[path] = fid
	}
	return out, nil
}

// ExportMany exports several files, returning FileId -> content.
func ExportMany(s *Store, ids [][]byte) (map[string][]byte, error) {
	out := map[string][]byte{}
	for _, id := range ids {
		content, err := s.ReadFile(id)
		if err != nil {
			return nil, err
		}
		out[keyOf(id)] = content
	}
	return out, nil
}

// ContentDigest returns the SHA-256 of a file's logical content. It is a
// Library convenience for callers; identity is never derived from it.
func ContentDigest(s *Store, fileID []byte) (string, error) {
	content, err := s.ReadFile(fileID)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(content)
	return hex.EncodeToString(sum[:]), nil
}