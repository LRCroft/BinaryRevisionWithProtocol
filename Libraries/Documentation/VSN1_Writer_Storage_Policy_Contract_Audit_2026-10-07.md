
---

# Writer Storage Policy Contract Audit Report -- 2026-10-07

**Status:** READY FOR WRITER STORAGE POLICY CONTRACT FREEZE

## Executive Summary

This audit verifies that the four writer-side storage-policy profiles (HIGHLY_VERTICAL, VERTICAL, HORIZONTAL, HIGHLY_HORIZONTAL) are correctly classified as informative implementation-local profiles layered over exactly two normative wire modes (MODERN 0x01, ENTERPRISE 0x02), without introducing any new binary protocol values.

## Wire Mode Registry -- Verified Untouched

| Field | Frozen Value | Status |
|-------|-------------|--------|
| MODERN ModeDeclaration value | 0x01 | Unchanged |
| ENTERPRISE ModeDeclaration value | 0x02 | Unchanged |
| Reserved range (non-MODERN/ENTERPRISE) | 0x00, 0x03-0xFF | Unchanged |
| GR-38 Mode registry rule | Exactly one of two values on wire | Unchanged |

**Verification:** `generate_docs.py` lines 820-833 (ModeDeclaration registry) verified intact. No new values added.

## Policy Profile Definitions -- Complete

| Policy | Wire Mode | Intent | EXTENTS-1 Role | DIRECT-1 Role |
|--------|-----------|--------|----------------|---------------|
| HIGHLY_Vertical | MODERN (0x01) | Maximum storage efficiency | Primary optimization target | Fallback when not beneficial |
| VERTICAL | MODERN (0x01) | Bounded effort | Available but bounded by config | Common fallback |
| HORIZONTAL | ENTERPRISE (0x02) | Simplicity/robustness | Limited/shallow only | Preferred baseline |
| HIGHLY_Horizontal | ENTERPRISE (0x02) | Maximum simplicity | Prohibited | Required for all content |

## No Protocol Changes -- Verification Checklist

| Check | Result | Evidence |
|-------|--------|----------|
| New ModeDeclaration value introduced? | NO | Frozen registry intact at 2 values only |
| New wire-level field added? | NO | Container format unchanged (GR-08) |
| ObjectSerial semantics modified? | NO | ID-03, ID-09, ID-61, SR-37 unchanged |
| Compression rules changed? | NO | 0x00=IDENTITY baseline preserved; GR-45 intact |
| CommitMarker semantics changed? | NO | RC-01 through RC-45 unchanged |
| Test vectors modified? | NO | All 5 SHA-256 match manifest exactly |
| Parser grammar altered? | NO | Reader path: ModeDecl -> RepDesc -> Content unchanged |

## Frozen Vector Verification -- 5/5 SHA-256 MATCH

| File | Manifest SHA-256 | Current SHA-256 | Match |
|------|------------------|-----------------|-------|
| DIRECT-01.vsn | d4c31c91...8bbae5f4426 | D4C31C9109735773...DEBA5F4426 | YES |
| DIRECT-02.vsn | 1af182c3...a2d08324 | 1AF182C3271B9B40...A2D08324 | YES |
| DIRECT-03.vsn | 25f98747...a7b66a4 | 25F9874796DC0407...CEA7B66A4 | YES |
| EXT-01.vsn | 486fdff3...41cab9c6 | 486FDFF3DC19872F...41CAB9C6 | YES |
| EXT-02-and-EXT-03.vsn | d1baabce...857be90 | D1BAABCE8123F398...857BE90 | YES |

**NO PROTOCOL ARTIFACTS MODIFIED.**

## Architecture Hierarchy -- Verified

```
Layer 1: Wire Mode (NORMATIVE, on wire)
  ├── 0x01 MODERN -> Policies: HIGHLY_VERTICAL, VERTICAL
  └── 0x02 ENTERPRISE -> Policies: HORIZONTAL, HIGHLY_HORIZONTAL

Layer 2: Storage Policy (INFORMATIVE, implementation-local config)
  ├── HIGHLY_Vertical | VERTICAL
  └── HORIZONTAL | HIGHLY_Horizontal

Layer 3: Optimization Config (implementation-resource params)
  ├── search_budget | memory_limit
  └── depth | scope
```

## Conformance Test Requirements -- 10 Verifiable Tests

| # | Requirement | Verification Method |
|---|------------|---------------------|
| 1 | Correct wire mode mapping | ModeDeclaration matches expected policy mapping |
| 2 | No illegal values | Exactly one ModeDecl with 0x01 or 0x02 (GR-39) |
| 3 | Valid under declared mode | Full semantic validation passes |
| 4 | Logical semantics preserved | Identical state -> identical FileHeads/RevisionIds/ObjectSerials |
| 5 | ObjectSerial during repack | Re-commit preserves all ObjectSerials |
| 6 | CommitMarker/recovery unchanged | Recovery identical regardless of writer policy |
| 7 | Reader independence | Parser decodes without policy metadata |
| 8 | No wire dependency | Removing policy info does not affect reader correctness |
| 9 | Policy/config separation | Config changes produce valid output; different configs measurable |
| 10 | Cross-language equivalence | Independent impl under same policy -> semantically equivalent containers |

## Verdict

**READY FOR WRITER STORAGE POLICY CONTRACT FREEZE**

- Four policy profiles formally defined with wire-mode mapping
- Zero protocol modifications (frozen vectors intact, registry untouched)
- Documentation complete and synchronized across all files
- Conformance test requirements specified

---
*Audit completed: 2026-10-07*
