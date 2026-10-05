// Corpus probe for the Go VSN Library.
//
// Executed by Conformance/run_corpus.sh, which supplies identical subcommands to
// every language so conformance is decided by identical inputs and identical
// pass/fail criteria.
//
//	go run ./cmd/vsncorpus <subcommand> <args...>
//
// Subcommands match run_corpus.sh:
//	vectors   <file> <expected_bytes> <expected_sha256>
//	scenario  <file> <interpretation.json>
//	limit     <contract.json>
//	malformed <frozen_vector>
//	interop   <corpus_dir>
package main

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
"strings"
	"strconv"

	"github.com/campmember/vsn/go"
)

func failf(format string, args ...interface{}) int {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	return 1
}

// codeOf runs fn expecting a VSN failure and returns its 4-hex identifier, or
// "" when fn unexpectedly succeeded.
func codeOf(fn func() error) string {
	err := fn()
	if err == nil {
		return ""
	}
	if e, ok := err.(*vsn.Error); ok {
		return fmt.Sprintf("%04X", e.Code)
	}
	return "UNEXPECTED:" + err.Error()
}

// fileEntry is one file's canonical description. Field names and pointer-ness
// mirror corpus/scenarios/*.json so a nil path/head serializes to JSON null.
type fileEntry struct {
	FileID        string  `json:"fileId"`
	Path          *string `json:"path"`
	HeadRevision  *uint64 `json:"headRevision"`
	ObjectSerial  *uint64 `json:"objectSerial"`
	RepIdentity   *uint16 `json:"repIdentity"`
	RepVersion    *uint64 `json:"repVersion"`
	ContentBase64 string  `json:"contentBase64"`
}

// interpretation is the language-neutral canonical description of a container.
type interpretation struct {
	Mode               uint8       `json:"mode"`
	Generation         uint64      `json:"generation"`
	RecoveryStatus     string      `json:"recoveryStatus"`
	AcceptedGeneration uint64      `json:"acceptedGeneration"`
	Files              []fileEntry `json:"files"`
}

// descriptorOf returns the raw descriptor bytes for an ObjectSerial.
func descriptorOf(c *vsn.Container, serial uint64) []byte {
	for _, o := range c.Objects {
		if o.Serial == serial {
			return o.Descriptor
		}
	}
	return nil
}

// describe derives the canonical interpretation directly from the bytes, so
// comparing it against the recorded JSON is genuine cross-language evidence
// rather than self-consistency.
func describe(data []byte) (*interpretation, error) {
	parsed, err := vsn.Parse(data)
	if err != nil {
		return nil, err
	}
	store, err := vsn.Open(data)
	if err != nil {
		return nil, err
	}

	pathByFile := map[string]string{}
	revByFile := map[string]uint64{}
	serialByRev := map[uint64]uint64{}
	for i := range parsed.Records {
		rec := &parsed.Records[i]
		switch rec.RType {
		case vsn.RecRevision:
			ridF := rec.Field(vsn.FidRevID)
			fidF := rec.Field(vsn.FidRevFileID)
			if ridF == nil || fidF == nil {
				continue
			}
			key := hex.EncodeToString(fidF.Value)
			rid := ridF.UvarintValue()
			if p := rec.Field(vsn.FidRevPath); p != nil {
				pathByFile[key] = string(p.Value)
			}
			if o := rec.Field(vsn.FidRevObjectSerial); o != nil {
				serialByRev[rid] = o.UvarintValue()
			}
		case vsn.RecFileHead:
			fidF := rec.Field(vsn.FidHeadFileID)
			ridF := rec.Field(vsn.FidHeadRevID)
			if fidF != nil && ridF != nil {
				revByFile[hex.EncodeToString(fidF.Value)] = ridF.UvarintValue()
			}
		}
	}

	rr, err := vsn.Recover(data)
	if err != nil {
		return nil, err
	}
	out := &interpretation{
		Mode:               parsed.Mode,
		Generation:         parsed.TrailerGeneration,
		RecoveryStatus:     rr.Status,
		AcceptedGeneration: rr.AcceptedGeneration,
		Files:              []fileEntry{},
	}

	for i := range parsed.Records {
		rec := &parsed.Records[i]
		if rec.RType != vsn.RecFileIdentity {
			continue
		}
		f := rec.Field(vsn.FidFileID)
		if f == nil {
			continue
		}
		key := hex.EncodeToString(f.Value)
		entry := fileEntry{FileID: key}
		if p, ok := pathByFile[key]; ok {
			pv := p
			entry.Path = &pv
		}
		if head, ok := revByFile[key]; ok {
			hv := head
			entry.HeadRevision = &hv
			if serial, ok := serialByRev[head]; ok {
				sv := serial
				entry.ObjectSerial = &sv
				content, merr := store.Materialize(serial)
				if merr != nil {
					return nil, merr
				}
				ident, ver, _, herr := vsn.ParseObjectHeader(descriptorOf(parsed, serial))
				if herr != nil {
					return nil, herr
				}
				i16 := uint16(ident)
				vv := ver
				entry.RepIdentity = &i16
				entry.RepVersion = &vv
				entry.ContentBase64 = base64.StdEncoding.EncodeToString(content)
			}
		}
		out.Files = append(out.Files, entry)
	}
	sort.Slice(out.Files, func(i, j int) bool {
		return out.Files[i].FileID < out.Files[j].FileID
	})
	return out, nil
}

// compare re-marshals both sides and reports a readable diff on mismatch.
func compare(actual, expected *interpretation, label string) int {
	a, err := json.Marshal(actual)
	if err != nil {
		return failf("%s: marshal actual: %v", label, err)
	}
	b, err := json.Marshal(expected)
	if err != nil {
		return failf("%s: parse expectation: %v", label, err)
	}
	if string(a) == string(b) {
		return 0
	}
	var av, bv interface{}
	_ = json.Unmarshal(a, &av)
	_ = json.Unmarshal(b, &bv)
	var diffs []string
	for _, k := range []string{"mode", "generation", "recoveryStatus",
		"acceptedGeneration", "files"} {
		x, _ := json.Marshal(map[string]interface{}{k: av.(map[string]interface{})[k]})
		y, _ := json.Marshal(map[string]interface{}{k: bv.(map[string]interface{})[k]})
		if string(x) != string(y) {
			diffs = append(diffs, fmt.Sprintf("%s:\n    got  %s\n    want %s", k, x, y))
		}
	}
	return failf("%s interpretation mismatch:\n  %s", label, joinLines(diffs))
}

func joinLines(s []string) string {
	out := ""
	for i, l := range s {
		if i > 0 {
			out += "\n  "
		}
		out += l
	}
	return out
}

func cmdVectors(args []string) int {
	path := args[0]
	wantBytes, err := strconv.Atoi(args[1])
	if err != nil {
		return failf("bad expected byte length %q", args[1])
	}
	wantSha := args[2]
	data, err := os.ReadFile(path)
	if err != nil {
		return failf("read %s: %v", path, err)
	}
	if len(data) != wantBytes {
		return failf("length %d, corpus says %d", len(data), wantBytes)
	}
	sum := sha256.Sum256(data)
	if got := hex.EncodeToString(sum[:]); got != wantSha {
		return failf("sha256 %s, corpus says %s", got, wantSha)
	}
	parsed, perr := vsn.Parse(data)
	if perr != nil {
		return failf("parse failed: %v", perr)
	}
	if len(parsed.Records) == 0 {
		return failf("no records decoded")
	}
	store, oerr := vsn.Open(data)
	if oerr != nil {
		return failf("open failed: %v", oerr)
	}
	for _, serial := range store.Objects() {
		content, merr := store.Materialize(serial)
		if merr != nil {
			return failf("object %d does not materialize: %v", serial, merr)
		}
		if content == nil {
			return failf("object %d materialized to nil", serial)
		}
	}
	return 0
}

func cmdScenario(args []string) int {
	data, err := os.ReadFile(args[0])
	if err != nil {
		return failf("read %s: %v", args[0], err)
	}
	raw, err := os.ReadFile(args[1])
	if err != nil {
		return failf("read %s: %v", args[1], err)
	}
	var expected interpretation
	if err := json.Unmarshal(raw, &expected); err != nil {
		return failf("parse expectation: %v", err)
	}
	actual, derr := describe(data)
	if derr != nil {
		return failf("scenario failed to interpret: %v", derr)
	}
	return compare(actual, &expected, filepath.Base(args[0]))
}

func cmdMalformed(args []string) int {
	base, err := os.ReadFile(args[0])
	if err != nil {
		return failf("read %s: %v", args[0], err)
	}
	var problems []string

	expectCode := func(data []byte, want, label string) {
		got := codeOf(func() error { _, e := vsn.Parse(data); return e })
		if got != want {
			problems = append(problems, fmt.Sprintf("%s: got %s want %s",
				label, orNone(got), want))
		}
	}

	bad := append([]byte(nil), base...)
	bad[0] = 'X'
	expectCode(bad, "0001", "bad magic")

	d := append([]byte(nil), base...)
	d[4], d[5] = 0x00, 0x7F
	expectCode(d, "0003", "bad container format version")

	d = append([]byte(nil), base...)
	d[6], d[7] = 0x00, 0x7F
	expectCode(d, "0004", "bad encoding version")

	// Every strict prefix must be rejected: truncation must never be mistaken
	// for a short-but-valid container.
	for n := 0; n < len(base); n++ {
		if codeOf(func() error { _, e := vsn.Parse(base[:n]); return e }) == "" {
			problems = append(problems,
				fmt.Sprintf("prefix of length %d parsed but must not", n))
			break
		}
	}
	if codeOf(func() error { _, e := vsn.Parse(base); return e }) != "" {
		problems = append(problems, "intact vector failed to parse")
	}
	if len(problems) > 0 {
		return failf("malformed handling wrong:\n  %s", joinLines(problems))
	}
	return 0
}

func orNone(s string) string {
	if s == "" {
		return "no-error"
	}
	return s
}

// limitCase mirrors one entry of corpus/limitcleanup.json.
type limitCase struct {
	Name          string   `json:"name"`
	History       int      `json:"history"`
	Limit         int64    `json:"limit"`
	Removed       []uint64 `json:"removed"`
	Retained      []uint64 `json:"retained"`
	Error         string   `json:"error"`
	RemovedFirst  []uint64 `json:"removed_first"`
	RemovedSecond []uint64 `json:"removed_second"`
	RemovedThird  []uint64 `json:"removed_third"`
}

// history builds a store with n revisions of one file.
func history(n int) (*vsn.Store, []byte) {
	s := vsn.Create(vsn.ModeModern)
	fid, err := s.CreateFile("a.txt", []byte("v1"))
	if err != nil {
		return nil, nil
	}
	for i := 2; i <= n; i++ {
		if werr := s.WriteFile(fid, []byte(fmt.Sprintf("v%d", i))); werr != nil {
			return nil, nil
		}
	}
	return s, fid
}

func equalRevs(a, b []uint64) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func fmtRevs(a []uint64) string {
	parts := make([]string, len(a))
	for i, v := range a {
		parts[i] = strconv.FormatUint(v, 10)
	}
	return "[" + strings.Join(parts, " ") + "]"
}

func cmdLimit(args []string) int {
	raw, err := os.ReadFile(args[0])
	if err != nil {
		return failf("read %s: %v", args[0], err)
	}
	var doc struct {
		Cases []limitCase `json:"cases"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		return failf("parse contract: %v", err)
	}
	var problems []string
	expect := func(cond bool, msg string) {
		if !cond {
			problems = append(problems, msg)
		}
	}

	for _, c := range doc.Cases {
		switch c.Name {
		case "retains_newest_n":
			s, fid := history(c.History)
			if s == nil {
				problems = append(problems, "retains_newest_n: build failed")
				continue
			}
			removed, cerr := s.LimitCleanUp(fid, c.Limit)
			if cerr != nil {
				problems = append(problems,
					fmt.Sprintf("cleanup failed: %v", cerr))
				continue
			}
			expect(equalRevs(removed, c.Removed),
				fmt.Sprintf("removed %s want %s", fmtRevs(removed), fmtRevs(c.Removed)))
			got := s.ListRevisions(fid)
			expect(equalRevs(got, c.Retained),
				fmt.Sprintf("retained %s want %s", fmtRevs(got), fmtRevs(c.Retained)))

			// FileHead stays valid and is the newest retained revision.
			head, herr := s.CurrentRevision(fid)
			expect(herr == nil && head == c.Retained[len(c.Retained)-1],
				"FileHead is not the newest retained revision")

			// Removed revisions vanish (0x0009); objects are NOT collected.
			objsBefore := len(s.Objects())
			gone := c.Removed[0]
			expect(codeOf(func() error { _, e := s.GetRevision(gone); return e }) == "0009",
				"removed revision did not raise 0009")
			expect(len(s.Objects()) == objsBefore,
				"LimitCleanUp garbage collected objects")

			// Cleanup persists through commit and survives reopen.
			data, derr := s.Commit()
			if derr != nil {
				problems = append(problems, fmt.Sprintf("commit failed: %v", derr))
				continue
			}
			reopened, oerr := vsn.Open(data)
			if oerr != nil {
				problems = append(problems, fmt.Sprintf("reopen failed: %v", oerr))
				continue
			}
			expect(equalRevs(reopened.ListRevisions(fid), c.Retained),
				"cleanup did not persist through commit")
			expect(codeOf(func() error { _, e := reopened.GetRevision(gone); return e }) == "0009",
				"removed revision resurrected after reopen")
			rr, _ := vsn.Recover(data)
			expect(rr.Recovered, "recovery failed after cleanup")

			// Idempotent: repeating removes nothing and resurrects nothing.
			again, _ := reopened.LimitCleanUp(fid, c.Limit)
			expect(len(again) == 0, "repeat cleanup removed revisions")
			third, _ := reopened.LimitCleanUp(fid, c.Limit)
			expect(len(third) == 0, "third cleanup removed revisions")

		case "limit_zero_rejected":
			s, fid := history(c.History)
			got := codeOf(func() error { _, e := s.LimitCleanUp(fid, c.Limit); return e })
			expect(got == "000C", fmt.Sprintf("limit 0 raised %s want 000C", orNone(got)))
			// History must be untouched by the rejected call.
			full := make([]uint64, 0, c.History)
			for i := 1; i <= c.History; i++ {
				full = append(full, uint64(i))
			}
			expect(equalRevs(s.ListRevisions(fid), full),
				"history changed after a rejected limit 0")

		case "limit_greater_than_history":
			s, fid := history(c.History)
			removed, _ := s.LimitCleanUp(fid, c.Limit)
			expect(equalRevs(removed, c.Removed),
				fmt.Sprintf("limit>history removed %s", fmtRevs(removed)))
			expect(equalRevs(s.ListRevisions(fid), c.Retained),
				fmt.Sprintf("limit>history retained %s", fmtRevs(s.ListRevisions(fid))))

		case "idempotent_repeat":
			s, fid := history(c.History)
			first, _ := s.LimitCleanUp(fid, c.Limit)
			expect(equalRevs(first, c.RemovedFirst),
				fmt.Sprintf("first cleanup %s want %s",
					fmtRevs(first), fmtRevs(c.RemovedFirst)))
			second, _ := s.LimitCleanUp(fid, c.Limit)
			expect(equalRevs(second, c.RemovedSecond),
				fmt.Sprintf("second cleanup %s want empty", fmtRevs(second)))
			third, _ := s.LimitCleanUp(fid, c.Limit)
			expect(equalRevs(third, c.RemovedThird),
				fmt.Sprintf("third cleanup %s want empty", fmtRevs(third)))

		case "per_file_isolation":
			s, fid := history(c.History)
			other, oerr2 := s.CreateFile("other.txt", []byte("o1"))
			if oerr2 != nil {
				problems = append(problems, "per_file_isolation: build failed")
				continue
			}
			for i := 2; i <= c.History; i++ {
				s.WriteFile(other, []byte(fmt.Sprintf("o%d", i)))
			}
			before := s.ListRevisions(other)
			beforeContent, _ := s.ReadFile(other)
			removed, _ := s.LimitCleanUp(fid, c.Limit)
			expect(equalRevs(removed, c.Removed),
				fmt.Sprintf("isolated cleanup removed %s", fmtRevs(removed)))
			expect(equalRevs(s.ListRevisions(other), before),
				"unrelated file history changed")
			afterContent, _ := s.ReadFile(other)
			expect(string(afterContent) == string(beforeContent),
				"unrelated file content changed")
		}
	}

	// An unknown FileId must be rejected, never treated as empty history.
	s, _ := history(3)
	expect(codeOf(func() error {
		_, e := s.LimitCleanUp(make([]byte, 16), 5)
		return e
	}) == "0009", "unknown FileId did not raise 0009")

	if len(problems) > 0 {
		return failf("LimitCleanUp contract violations:\n  %s", joinLines(problems))
	}
	return 0
}

// cmdInterop proves byte-level interoperability rather than self-consistency.
//
// Each recorded scenario is re-derived from this library's own builder and
// compared byte-for-byte against the reference-written corpus file, then read
// back and compared against the recorded interpretation.
func cmdInterop(args []string) int {
	root := args[0]
	var problems []string
	for _, name := range []string{"basic", "extents", "enterprise", "multifile"} {
		path := filepath.Join(root, "scenarios", name+".vsn")
		recorded, err := os.ReadFile(path)
		if err != nil {
			problems = append(problems, fmt.Sprintf("%s: read: %v", name, err))
			continue
		}
		produced, berr := vsn.BuildScenario(name)
		if berr != nil {
			problems = append(problems, fmt.Sprintf("%s: builder: %v", name, berr))
			continue
		}
		if string(produced) != string(recorded) {
			problems = append(problems, fmt.Sprintf(
				"%s: regenerated %d bytes, corpus has %d",
				name, len(produced), len(recorded)))
			continue
		}
		if rc := cmdScenario([]string{
			path, filepath.Join(root, "scenarios", name+".json"),
		}); rc != 0 {
			problems = append(problems, name+": read-back mismatch")
		}
	}
	if len(problems) > 0 {
		return failf("interop failures:\n  %s", joinLines(problems))
	}
	return 0
}

func main() {
	args := os.Args[1:]
	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "usage: vsncorpus <vectors|scenario|limit|malformed|interop> ...")
		os.Exit(2)
	}
	var rc int
	switch args[0] {
	case "vectors":
		if len(args) < 4 {
			rc = failf("vectors needs <file> <bytes> <sha256>")
		} else {
			rc = cmdVectors(args[1:])
		}
	case "scenario":
		if len(args) < 3 {
			rc = failf("scenario needs <file> <interpretation.json>")
		} else {
			rc = cmdScenario(args[1:])
		}
	case "limit":
		if len(args) < 2 {
			rc = failf("limit needs <contract.json>")
		} else {
			rc = cmdLimit(args[1:])
		}
	case "malformed":
		if len(args) < 2 {
			rc = failf("malformed needs <frozen_vector>")
		} else {
			rc = cmdMalformed(args[1:])
		}
	case "interop":
		if len(args) < 2 {
			rc = failf("interop needs <corpus_dir>")
		} else {
			rc = cmdInterop(args[1:])
		}
	default:
		rc = failf("unknown subcommand %q", args[0])
	}
	os.Exit(rc)
}