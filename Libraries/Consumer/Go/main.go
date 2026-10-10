// Independent Go consumer: a separate module that depends on the VSN Go
// library via a `replace` directive and exercises ONLY the public API.
package main

import (
	"fmt"
	"os"

	vsn "github.com/campmember/vsn/go"
)

func main() {
	fails := 0
	check := func(cond bool, msg string) {
		if cond {
			fmt.Println("ok  - " + msg)
		} else {
			fmt.Println("FAIL: " + msg)
			fails++
		}
	}

	s := vsn.Create(vsn.ModeModern)
	fid, err := s.CreateFile("go.txt", []byte("GO-CONSUMER"))
	check(err == nil, "createFile")
	check(s.FileExists(fid), "fileExists")
	got, _ := s.ReadFile(fid)
	check(string(got) == "GO-CONSUMER", "readFile round-trips")
	err = s.WriteFile(fid, []byte("GO-CONSUMER-2"))
	check(err == nil, "writeFile creates a new revision")
	_, _ = s.Commit()
	revs := s.ListRevisions(fid)
	check(len(revs) >= 2, "revisions tracked")
	removed, _ := s.LimitCleanUp(fid, 1)
	check(len(removed) >= 1, "limitCleanUp removed >= 1")
	exported, err := s.Commit()
	check(err == nil && len(exported) > 0, "commit produced canonical bytes")
	diags := vsn.ValidateWithDiagnostics(exported, vsn.LevelStructural)
	check(len(diags) == 0, "structural validation is clean")
	// Storage Policy wire-out / wire-in round-trip (public API only).
	sp4 := []vsn.StoragePolicy{vsn.StoragePolicyHighlyVertical, vsn.StoragePolicyVertical,
		vsn.StoragePolicyHorizontal, vsn.StoragePolicyHighlyHorizontal}
	check(len(sp4) == 4, "4 StoragePolicy values defined (1..4)")
	// HORIZONTAL (3) round-trip through public Parse and Open.
	sh := vsn.CreateWithPolicy(vsn.StoragePolicyHorizontal)
	check(sh != nil, "CreateWithPolicy(HORIZONTAL) constructs a store")
	_, _ = sh.CreateFile("sp.txt", []byte("SP"))
	out, err := sh.Commit()
	check(err == nil && len(out) > 0, "policy store committed")
	c, err := vsn.Parse(out)
	check(err == nil && c != nil && c.StoragePolicy == 3, "SP wire-in: Parse reads HORIZONTAL==3")
	o, err := vsn.Open(out)
	check(err == nil && o != nil && o.GetStoragePolicy() == 3, "SP wire-in: Open().GetStoragePolicy()==3")
	// VERTICAL (2) round-trip.
	sv := vsn.CreateWithPolicy(vsn.StoragePolicyVertical)
	_, _ = sv.CreateFile("sp.txt", []byte("SP"))
	outv, _ := sv.Commit()
	cv, err := vsn.Parse(outv)
	check(err == nil && cv != nil && cv.StoragePolicy == 2, "SP wire-in: Parse reads VERTICAL==2")
	// Distinct policies -> distinct SP values on the wire.
	s1 := vsn.CreateWithPolicy(vsn.StoragePolicyHighlyVertical)
	_, _ = s1.CreateFile("x", []byte("x"))
	b1, _ := s1.Commit()
	c1, _ := vsn.Parse(b1)
	check(c1 != nil && c1.StoragePolicy == 1, "SP wire-in: HIGHLY_VERTICAL==1 distinct")

	if fails == 0 {
		fmt.Println("CONSUMER GO PASS")
	} else {
		fmt.Printf("CONSUMER GO FAIL (%d)\n", fails)
		os.Exit(1)
	}
}