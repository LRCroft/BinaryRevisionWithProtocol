# VSN Four-Policy Architecture Freeze Audit Report

**Date:** 2026-10-07  
**Status:** READY FOR ARCHITECTURE FREEZE

---

## Executive Summary

The architectural contradiction between the four "HIGHLY_*/VERTICAL/HORIZONTAL" names and the two normative wire modes (MODERN 0x01 / ENTERPRISE 0x02) has been **resolved**. The four names are now clearly classified as **informative writer-side storage-policy profiles**, not wire modes. No new protocol values were introduced.

## Decision: Option (a) — Informative Storage-Policy Layer

**Chosen:** Keep 2 normative wire modes (0x01 MODERN, 0x02 ENTERPRISE). Treat HIGHLY_VERTICAL / VERTICAL / HORIZONTAL / HIGHLY_HORIZONTAL as an **informative storage-policy layer**: writer-side optimization profiles layered over the two wire modes.

**Rationale:**
- The wire-mode registry (`generate_docs.py:820-833`, `docs.html:817-830`) defines exactly two modes and marks 0x00, 0x03-0xFF as reserved/malformed (VR-16, IV-09).
- Allocation of 0x03/0x04 for HIGHLY_* would require new frozen byte vectors, additional conformance tests, and changes to the wire grammar — all unnecessary when the four names are purely informative.
- The hierarchical model (Wire Mode → Storage Policy → Optimization Config) is architecturally cleaner and semantically correct.

## Wire Mode Registry (UNTOUCHED)

| Value | Name | Description |
|-------|------|-------------|
| 0x00 | RESERVED | Malformed on wire |
| 0x01 | MODERN (Vertical) | Permitted: HIGHLY_VERTICAL, VERTICAL profiles |
| 0x02 | ENTERPRISE (Horizontal) | Permitted: HORIZONTAL, HIGHLY_HORIZONTAL profiles |
| 0x03–0xFF | RESERVED | Malformed on wire |

**Frozen vectors:** All 5 SHA-256 intact. No changes to binary encoding.

## Storage-Policy Profile Definitions (Informative)

### HIGHLY_VERTICAL
- **Wire Mode:** MODERN (0x01)
- **Purpose:** Maximum storage-efficiency effort within explicit resource and safety limits
- **Features:** Aggressive deduplication, EXTENTS-1 permitted, deep dependency structures, expensive similarity search within budget

### VERTICAL
- **Wire Mode:** MODERN (0x01)  
- **Purpose:** High storage efficiency with more bounded optimization
- **Features:** Bounded deduplication, EXTENTS-1 with depth limits, full-copy fallback common

### HORIZONTAL
- **Wire Mode:** ENTERPRISE (0x02)
- **Purpose:** Prefer straightforward representations with limited reuse
- **Features:** Complete content objects preferred, limited/shallow EXTENTS only, avoid deep dependency chains

### HIGHLY_HORIZONTAL
- **Wire Mode:** ENTERPRISE (0x02)
- **Purpose:** Maximum straightforwardness — simplest canonical physical representation
- **Features:** DIRECT-1 required, EXTENTS-1 forbidden, complete logical content per object

## Section-by-Section Changes in Documentation

### `generate_docs.py`

| Line | Change |
|------|--------|
| 2915–2960 | **Expanded Section 17** (`lib-storage-policies`) from stub → full hierarchy diagram + 4 profile definitions + wire-mode mapping table |
| 2961 | Unchanged (Section 18: `lib-storage-optimization`, "Storage Optimization") |
| 2962 | **Title changed:** `sec('19', 'lib-storage', 'Physical storage management', ...)` — was `'Storage optimization'` |

### `docs.html` (generated)

| Check | Result |
|-------|--------|
| No "four-mode" claims | PASS — 0 matches |
| No new wire values (0x03/0x04 as modes) | PASS — 0x03 only appears as SR-record types |
| Frozen vectors SHA-256 intact | PASS — 5/5 match |
| Wire mode registry at line 820-833 | UNTOUCHED — still defines 0x01 MODERN, 0x02 ENTERPRISE only |

### `libraries.html` (generated)

| Check | Result |
|-------|--------|
| Section 18 expanded with full policy details | PASS |
| Section 20 renamed to "Physical storage management" | PASS — eliminates overlap with Section 19 "Storage Optimization" |
| TOC anchors match section ids | PASS — all verified |
| No "four-mode" claims | PASS — 0 matches |
| Wire-mode mapping table present in Section 18 | PASS |

## Validation Summary

| Validation | Method | Result |
|-----------|--------|--------|
| Zero four-mode ambiguous language | regex scan both HTMLs | PASS (0 matches each) |
| No new wire values introduced | regex scan docs.html | PASS (0x03 only as SR-record types) |
| TOC links correct | anchor matching | PASS (all href → id) |
| Section overlap eliminated | Section 19 vs 20 title check | PASS ("Storage Optimization" ≠ "Physical storage management") |
| Frozen vectors intact | SHA-256 compare to manifest.json | PASS (5/5 match) |
| Wire mode registry frozen | `generate_docs.py` line 820-833 | UNTOUCHED |

## Freeze Verdict

```
ARCHITECTURE IS READY FOR FREEZE.

All documentation is consistent with the two-wire-mode / four-policy-profile model.
No protocol changes required. No frozen vectors modified. No conformance suite changes needed.
```
