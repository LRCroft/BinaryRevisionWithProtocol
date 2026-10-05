// Marker-based recovery (RC-01..RC-45).
//
// The accepted state is the canonical data preceding the highest-Generation
// structurally complete and semantically valid CommitMarker. No index, cache,
// checkpoint, or heuristic substitutes for the marker.
package vsn

// RecoveryResult reports the outcome of a recovery scan.
type RecoveryResult struct {
	AcceptedGeneration uint64
	Recovered          bool
	TailPresent        bool
	Status             string
	Message            string
}

// Recover locates the effective CommitMarker and reports the accepted
// generation. A truncated or incomplete tail after the marker is tolerated;
// malformed trailing data inside the framing is not.
func Recover(data []byte) (*RecoveryResult, error) {
	c, err := Parse(data)
	if err != nil {
		if e, ok := err.(*Error); ok && e.Code == ErrTruncated {
			return &RecoveryResult{
				Status:  "TRUNCATED",
				Message: "physical end reached mid-unit",
			}, nil
		}
		return &RecoveryResult{
			Status:  "MALFORMED",
			Message: err.Error(),
		}, nil
	}

	var highest uint64
	found := false
	for i := range c.Records {
		rec := &c.Records[i]
		if rec.RType != RecCommitMarker {
			continue
		}
		g := rec.Field(FidCommitGen)
		if g == nil {
			continue
		}
		v := g.UvarintValue()
		if !found || v > highest {
			highest = v
			found = true
		}
	}
	if !found {
		return &RecoveryResult{
			Status:  "NO_MARKER",
			Message: "no CommitMarker present",
		}, nil
	}
	return &RecoveryResult{
		AcceptedGeneration: highest,
		Recovered:          true,
		TailPresent:        c.TrailerGeneration != 0 && c.TrailerGeneration != highest,
		Status:             "RECOVERED",
		Message:            "accepted generation " + itoaU(highest),
	}, nil
}