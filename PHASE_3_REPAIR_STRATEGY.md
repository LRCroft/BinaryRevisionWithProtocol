# PHASE 3: REPAIR & VERIFICATION — Implementation Strategy
**VSN-1 Binary Revision With Protocol Audit**  
**Date:** 2026-01-15  
**Status:** READY FOR EXECUTION

---

## Phase 3 Objectives (from AUDIT_PLAN.md)

1. **Fix all production code** (Storage Policy writers, readers, recovery semantics)
2. **Verify frozen vectors unchanged** (hash check)
3. **Fix test issues** (regression tests, genuine cross-language tests)
4. **Build verification** (clean builds for all 31 languages)
5. **Final conformance run** (run_conformance.py, cross-language tests, storage policy tests)

---

## Phase 3.1 Prioritized Repair Plan

### Tier 1: FSharp Source Code Recovery (CRITICAL BLOCKER)

**Issue:** 44 test files, 0 source files

**Action:**
- [ ] Check git history for FSharp source deletions
- [ ] Check FSharp/.fsproj for clues about build structure
- [ ] Determine: Was source deleted? Or never committed?
- [ ] If deleted: Restore from git or rebuild from test specs
- [ ] If missing: Create minimal reader/writer implementation from test expectations

**Expected Outcome:** FSharp source code committed and tested

---

### Tier 2: Reference Implementation Verification (6 Languages)

**Language List:** Python, CSharp, Go, JavaScript-TypeScript, Kotlin, Scala

**For each language:**

#### 2.1: Verify Reader Implementation
- [ ] Locate reader code (parse_vsn, read_header, etc.)
- [ ] Verify it can consume frozen test vectors
- [ ] Test with DIRECT-01.vsn → DIRECT-02.vsn → EXT-01.vsn
- [ ] Document reader error handling and edge cases

#### 2.2: Verify Writer Implementation
- [ ] Locate writer code (emit_vsn, write_header, etc.)
- [ ] Generate VSN bytes matching Storage Policy (1-4)
- [ ] Verify output matches manifest expectations
- [ ] Cross-check with other language writers for byte compatibility

#### 2.3: Cross-Language Interop Test
- [ ] Python writes → CSharp reads (DIRECT-01)
- [ ] CSharp writes → Go reads (DIRECT-02)
- [ ] Go writes → JavaScript reads (DIRECT-03)
- [ ] JavaScript writes → Kotlin reads (EXT-01)
- [ ] Kotlin writes → Scala reads (EXT-02-and-EXT-03)
- [ ] Scala writes → Python reads (round-trip)
- **Expected:** All vectors consumed successfully, byte-for-byte identical

---

### Tier 3: Writer-Only Languages (6 Languages)

**Language List:** C, Cpp, Java, Rust, Swift, Zig

**Scope:** These have writers but no readers

**Decision Point:** For each language:
- Option A: Implement reader to achieve full support
- Option B: Document as "write-only" and exclude from cross-language tests
- Option C: Remove from reference implementation set

**Recommendation:** Implement readers for C, C++, Java, Rust (high-impact languages). Mark Swift, Zig as "write-only reference" if time is limited.

**For each language attempting reader:**
- [ ] Create reader module matching writer interface
- [ ] Test on frozen vectors (all 5)
- [ ] Verify error handling for malformed records (CAP09)
- [ ] Add to cross-language interop matrix

---

### Tier 4: Stub Languages (18 Languages)

**Language List:** Ada, COBOL, Crystal, D, Dart, Elixir, Erlang, Fortran, Haskell, Julia, Lua, Nim, OCaml, Objective-C, PHP, Perl, R, Ruby

**Decision Point:** These have neither reader nor writer

**Recommendation:** 
- Decide: Keep as "language samples" or remove from "31 languages supported" claim?
- If keeping: Document clearly as "demonstration code, not production"
- If removing: Reduce scope to 13 core languages (6 ref + 6 writers + 1 reader-only)

**If keeping as samples:**
- [ ] Mark each language's README as "Sample Implementation" not "Production"
- [ ] Add disclaimer in main README
- [ ] Move to separate "Language Samples" section in documentation

---

## Phase 3.2: Frozen Vector Verification

**Action Items:**

- [ ] Run SHA256 hash check on all 5 frozen vectors
  ```bash
  sha256sum DIRECT-01.vsn DIRECT-02.vsn DIRECT-03.vsn EXT-01.vsn EXT-02-and-EXT-03.vsn
  ```
- [ ] Compare against manifest.json
- [ ] Verify no accidental modifications during audit
- [ ] Document hash verification in test suite

**Expected:** All 5 hashes identical to manifest

---

## Phase 3.3: Test Fixes & Regression Testing

### 3.3.1: Create Cross-Language Interop Test Harness

**Goal:** Systematic validation of all producer→consumer pairs

**Test Matrix:**
```
Writers (12):  C, CSharp, Cpp, Go, Java, JavaScript, Kotlin, Python, Rust, Scala, Swift, Zig
Readers (7):   CSharp, FSharp, Go, JavaScript, Kotlin, Python, Scala

Combinations:  12 × 7 = 84 potential tests
Core subset:   6 × 6 = 36 reference language tests (Priority 1)
Extended:      Remaining 48 if time permits
```

**Test Script Template (pseudocode):**
```python
def test_interop():
	for producer in ['Python', 'CSharp', 'Go', 'JavaScript', 'Kotlin', 'Scala']:
		for vector in ['DIRECT-01', 'DIRECT-02', 'DIRECT-03', 'EXT-01', 'EXT-02-and-EXT-03']:
			# Producer: write or locate vector
			vsn_bytes = producer.write_vsn(vector)

			for consumer in ['Python', 'CSharp', 'Go', 'JavaScript', 'Kotlin', 'Scala']:
				# Consumer: read bytes
				result = consumer.read_vsn(vsn_bytes)

				# Assertion: Parsing succeeds and data is correct
				assert result.is_valid(), f"{producer} → {consumer}: {vector} FAILED"
				assert result.matches_expected(), f"{producer} → {consumer}: {vector} data mismatch"
```

### 3.3.2: Create Regression Tests for Each Defect

**From Defect Catalog:**
- [ ] For each "Reader missing" defect: Create test to verify reader once added
- [ ] For each "Writer missing" defect: Create test to verify writer once added
- [ ] For each "Storage Policy missing" defect: Create test for Storage Policy enum/class

**Example:**
```python
# Test: Ada reader (currently missing)
def test_ada_read_direct01():
	"""Regression: Ada must consume DIRECT-01.vsn"""
	bytes = load_frozen_vector('DIRECT-01.vsn')
	result = ada_reader.parse(bytes)
	assert result.is_valid()
	assert result.metadata.storage_policy in [1, 2, 3, 4]
```

### 3.3.3: Verify CAP19 Cross-Language Tests Use Real Artifacts

**Current Issue:** Some "CAP19" implementations may be stubs

**Action:**
- [ ] Inspect each CAP19 test (Haskell, Zig, Kotlin, etc.)
- [ ] Verify test actually uses frozen vectors, not mock data
- [ ] If mock: Replace with frozen vector tests
- [ ] If stub: Add genuine assertions

---

## Phase 3.4: Build Verification

### 3.4.1: Clean Build for All 31 Languages

**Prerequisites:**
- Docker daemon running
- Build toolchains available (listed in run_conformance.py)
- Sufficient disk space (~50GB for Docker images)

**Build Script Template:**
```bash
for lang in Ada C COBOL CSharp Cpp Crystal D Dart Elixir Erlang FSharp Fortran Go Haskell Java JavaScript-TypeScript Julia Kotlin Lua Nim Objective-C OCaml Perl PHP Python R Ruby Rust Scala Swift Zig; do
  echo "Building $lang..."
  cd Libraries/$lang
  # Run language-specific build per run_conformance.py spec
  # E.g., C: gcc -o /tmp/t test_vsn.c vsn.c
  cd ../..
done
```

**Expected Outcomes:**
- All 31 languages compile/run without errors
- Test exit codes: 0 (pass) or non-zero (fail)
- Document which languages have build blockers
- Record artifact paths and sizes

### 3.4.2: Artifact Generation

**For compiled languages (C, Cpp, Java, etc.):**
- [ ] Generate .a (archives), .so (shared libs), .jar (Java archives), etc.
- [ ] Verify artifacts can be loaded in fresh runtime
- [ ] Record paths and SHA256 hashes
- [ ] Test artifact reusability

**Expected:** All 31 languages produce consumable artifacts (binaries, .jar, .whl, .npm, etc.)

---

## Phase 3.5: Final Conformance Run

### 3.5.1: Run `run_conformance.py` After All Fixes

```bash
cd Libraries/Conformance
python3 run_conformance.py
```

**Expected:**
- All 31 languages report SUCCESS or clear FAIL reason
- No false positives (languages claiming VERIFIED but actually failing)
- Results saved to `_results.json`

### 3.5.2: Run Cross-Language Interoperability Test Harness

```bash
# Run systematic reader tests for all producers
for producer in ['Python', 'CSharp', 'Go', ...]:
	for consumer in ['Python', 'CSharp', 'Go', ...]:
		if consumer has reader:
			run_interop_test(producer, consumer)
```

**Expected:**
- 36+ reference language tests pass (6×6 matrix)
- All frozen vectors consumed successfully
- Byte-for-byte verification passes

### 3.5.3: Run Storage Policy Conformance Tests (CAP07, CAP08, P01–P12)

```bash
cd Libraries/Conformance/corpus/storage_policy
python3 run_corpus.py  # or equivalent
```

**Expected:**
- Storage Policy wire bytes validated for P01–P12
- CAP07/CAP08 tests pass for all 6 reference languages
- No regressions from Phase 1

---

## Phase 3 Deliverables

### Primary Artifacts:
1. **Repaired source code** — All fixes committed to git
2. **PHASE_3_REPAIR_LOG.md** — Before/after test results, defects fixed

### Secondary Artifacts:
1. **Cross-language interop test results** — 36+ test matrix
2. **Build reports** — 31 language build logs
3. **Conformance run results** — `_results.json` with all 31 languages (post-repair)
4. **Artifact inventory** — Paths and hashes for all consumable outputs

### Documentation:
1. **Updated README.md** — Clarify which languages are reference vs. sample
2. **Migration guide** — How to consume VSN bytes in each language
3. **Known limitations document** — Transparent about what's not supported

---

## Phase 3 Timeline Estimate

| Phase | Task | Estimated Time |
|-------|------|-----------------|
| 3.1 | FSharp recovery + Tier 1-2 repairs | 40 min |
| 3.2 | Frozen vector verification | 5 min |
| 3.3 | Test fixes + regression tests | 30 min |
| 3.4 | Build verification (parallel) | 20 min |
| 3.5 | Final conformance + interop run | 15 min |
| **Total** | | **110 minutes** |

---

## Success Criteria for Phase 3

✓ **MUST HAVE:**
- FSharp source code recovered/verified
- All 6 reference languages pass cross-language interop tests
- Frozen vectors verified unchanged
- All 31 languages attempt build (with clear pass/fail results)
- `run_conformance.py` executes without crashes

✓ **SHOULD HAVE:**
- 36+ cross-language interop tests pass (6×6 matrix)
- Storage Policy tests pass (CAP07, CAP08)
- Clear documentation of which 31 languages are reference vs. sample
- No false positives in final conformance results

✓ **NICE TO HAVE:**
- 18 stub languages have reader/writer implementations
- 84 full interop matrix tests (all combinations)
- Performance benchmarks for each language

---

## Phase 3 Hands-Off to Phase 4

Once Phase 3 completes:

1. Generate final master status table (31 languages × 9 columns)
2. Create executive summary
3. Determine release readiness verdict:
   - `FINAL VERIFIED — RELEASE READY`
   - `FINAL VERIFIED WITH DOCUMENTED LIMITATIONS`
   - `NOT RELEASE READY`

**Typical Outcome:** Likely `FINAL VERIFIED WITH DOCUMENTED LIMITATIONS` depending on repair success in Tier 2-3.

---
