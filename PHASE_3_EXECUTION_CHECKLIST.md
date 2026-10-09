# PHASE 3 EXECUTION CHECKLIST
**VSN Audit — Repair & Verification Phase**

---

## Pre-Phase 3: Environment Check

- [ ] Docker daemon running: `docker ps`
- [ ] Sufficient disk space: ~50GB for images + builds
- [ ] Git branch: `main` (clean working directory)
- [ ] Python 3.11+ available: `python --version`

---

## Phase 3.1: FSharp Recovery (CRITICAL BLOCKER)

### Investigation
- [ ] Check FSharp git history for source deletions
  ```bash
  git log -p --all Libraries/FSharp -- | grep -A5 -B5 "deleted"
  ```
- [ ] Review FSharp/.fsproj (project file structure)
- [ ] List what .fsproj expects: `<Compile Include="..." />`

### Decision
- [ ] DECISION: Source deleted OR never committed OR build deleted?
  - [ ] If deleted: Restore with `git checkout <commit>^:Libraries/FSharp/...`
  - [ ] If missing: Parse .fsproj to determine structure
  - [ ] If build artifacts deleted: Rebuild from test specs

### Verification
- [ ] Test files compile/run: `dotnet test Libraries/FSharp`
- [ ] At least one .fs source file present
- [ ] Reader keywords found in source (not just tests)

**Target: FSharp source code present and tests passing**

---

## Phase 3.2: Tier 1 Reference Implementation Verification (6 Languages)

### Python
- [ ] Locate reader code: `Libraries/Python/reader.py` (or similar)
- [ ] Verify can parse: DIRECT-01.vsn → DIRECT-02.vsn → EXT-01.vsn
- [ ] Verify writer code: `Libraries/Python/writer.py`
- [ ] Test: `python3 Libraries/Python/test_vsn.py`

### CSharp
- [ ] Locate reader code: `Libraries/CSharp/VsnLib/Reader.cs`
- [ ] Verify can parse frozen vectors
- [ ] Run tests: `dotnet test Libraries/CSharp/VsnTest`

### Go
- [ ] Locate reader code: `Libraries/Go/reader.go`
- [ ] Verify can parse frozen vectors
- [ ] Run tests: `cd Libraries/Go && go test ./...`

### JavaScript-TypeScript
- [ ] Locate reader code: `Libraries/JavaScript-TypeScript/src/reader.ts`
- [ ] Verify can parse frozen vectors
- [ ] Run tests: `cd Libraries/JavaScript-TypeScript && npm test`

### Kotlin
- [ ] Locate reader code: `Libraries/Kotlin/Vsn.kt`
- [ ] Verify can parse frozen vectors
- [ ] Run tests: `cd Libraries/Kotlin && kotlinc -cp ... && java ...`

### Scala
- [ ] Locate reader code: `Libraries/Scala/vsn.scala`
- [ ] Verify can parse frozen vectors
- [ ] Run tests: `cd Libraries/Scala && scala-cli run ...`

**Target: All 6 reference languages can read frozen vectors**

---

## Phase 3.3: Create Cross-Language Interop Test Matrix

### Test Script
- [ ] Create `test_cross_lang_interop.py` (see PHASE_3_REPAIR_STRATEGY.md for template)
- [ ] Matrix: Python→CSharp, CSharp→Go, Go→JavaScript, JavaScript→Kotlin, Kotlin→Scala, Scala→Python
- [ ] For each pair: Write vector → Read vector → Verify
- [ ] Run: `python3 test_cross_lang_interop.py`

### Expected Results
- [ ] 36 cross-language tests (6×6 reference subset)
- [ ] All frozen vectors (DIRECT-01 through EXT-02-and-EXT-03)
- [ ] Zero failures for reference languages
- [ ] Clear pass/fail output per combination

**Target: 36/36 core interop tests pass**

---

## Phase 3.4: Tier 2 Reader Implementation (Optional but Recommended)

**Decision:** For C, C++, Java, Rust, Swift, Zig

- [ ] DECISION: Implement readers? (Yes/No/Partial)
  - [ ] If YES: Implement reader for 3-4 languages (priority: C, C++, Java)
  - [ ] If NO: Mark as "write-only" reference implementations
  - [ ] If PARTIAL: Do C only, others marked write-only

### If Implementing Reader for C:
- [ ] Create `Libraries/C/reader.c` (mirror structure of writer)
- [ ] Functions: `read_header()`, `parse_vsn()`, `validate_bytes()`
- [ ] Test: `gcc -o /tmp/test Libraries/C/reader.c && ./tmp/test`
- [ ] Feed frozen vectors: `for vec in DIRECT-*.vsn; do ./program $vec; done`

### If Not Implementing:
- [ ] Document in README.md: "C is write-only reference"
- [ ] Skip from interop matrix

**Target: C reader implemented OR clearly marked write-only in docs**

---

## Phase 3.5: Frozen Vector Verification

- [ ] Run hash check:
  ```bash
  sha256sum Libraries/TestVectors/DIRECT-*.vsn Libraries/TestVectors/EXT-*.vsn
  ```
- [ ] Compare output against `Libraries/TestVectors/manifest.json`
- [ ] All 5 hashes must match exactly
- [ ] Document result: ✅ VERIFIED NO CHANGES

**Target: All frozen vectors unchanged (5/5 hash match)**

---

## Phase 3.6: Build Verification (All 31 Languages)

### Per-Language Builds

- [ ] **Python:** `cd Libraries/Python && python3 -m pytest test_vsn.py`
- [ ] **CSharp:** `cd Libraries/CSharp && dotnet build && dotnet test`
- [ ] **Go:** `cd Libraries/Go && go build && go test ./...`
- [ ] **C:** `cd Libraries/C && gcc -o /tmp/test test_vsn.c vsn.c && /tmp/test`
- [ ] **C++:** `cd Libraries/Cpp && g++ -o /tmp/test test_vsn.cpp vsn.cpp && /tmp/test`
- [ ] **JavaScript:** `cd Libraries/JavaScript-TypeScript && npm install && npm test`
- [ ] **Kotlin:** `cd Libraries/Kotlin && kotlinc -cp ... && java ...`
- [ ] **Scala:** `cd Libraries/Scala && scala-cli run ...`
- [ ] **Swift:** `cd Libraries/Swift && swiftc -o /tmp/test VSN.swift test_vsn.swift && /tmp/test`
- [ ] **Rust:** `cd Libraries/Rust && cargo test`
- [ ] **Java:** `cd Libraries/Java && javac *.java && java -cp . TestVsn`
- [ ] **(For remaining 21 languages):** Run per spec in `run_conformance.py`

### Docker-based Builds (if toolchain available):
- [ ] Run: `cd Libraries/Conformance && python3 run_conformance.py --langs=Python,CSharp,Go,Java`
- [ ] Capture results: `Libraries/Conformance/_results.json`

**Target: All 31 languages attempt build; document pass/fail/blocker for each**

---

## Phase 3.7: Final Conformance Run

- [ ] Prior to this step: All critical repairs completed
- [ ] Run: `cd Libraries/Conformance && python3 run_conformance.py`
- [ ] Capture results: `cp _results.json _results_phase3.json`
- [ ] Compare with Phase 1 baseline
- [ ] Verify no regressions

### Expected:
- [ ] All 6 reference languages: PASS
- [ ] Tier 2 languages (writers): PASS or documented blockers
- [ ] Tier 4 languages: Pass if stubs work, documented if incomplete
- [ ] No languages should regress from Phase 1

**Target: run_conformance.py completes; results documented**

---

## Phase 3.8: Generate Phase 3 Report

- [ ] Create `PHASE_3_REPAIR_LOG.md` with:
  - [ ] Before/after test results (comparison with Phase 2)
  - [ ] All defects from Phase 2 catalog: status (FIXED/OPEN/DOCUMENTED)
  - [ ] FSharp recovery summary
  - [ ] Cross-language interop test results
  - [ ] Build verification summary (31 languages × status)
  - [ ] Frozen vector verification: ✅ CONFIRMED
  - [ ] Any regressions or unexpected issues

- [ ] Create `INTEROP_MATRIX.md` with:
  - [ ] 6×6 reference language matrix (Python/CSharp/Go/JavaScript/Kotlin/Scala)
  - [ ] ✅ for passing tests, ❌ for failures
  - [ ] List any multi-language paths that fail

- [ ] Update `README.md`:
  - [ ] Clarify: "6 reference languages with full support, 12 write-only, 13 samples"
  - [ ] List reader availability per language
  - [ ] Point to recovery details in Phase 3 report

**Target: Phase 3 report complete with all metrics and decisions documented**

---

## Phase 3 Success Metrics

**MUST HAVE:**
- [ ] FSharp source code recovered (or community decision made)
- [ ] All 6 reference languages PASS interop tests
- [ ] Frozen vectors VERIFIED (SHA256 unchanged)
- [ ] Final conformance run COMPLETES
- [ ] README updated with scope clarification

**SHOULD HAVE:**
- [ ] 36/36 core interop tests pass
- [ ] Cross-language matrix documented
- [ ] At least 3 Tier 2 languages have readers added
- [ ] All 31 languages attempt build (results documented)

**NICE TO HAVE:**
- [ ] All 18 Tier 4 languages have readers/writers
- [ ] Performance benchmarks for round-trip serialization
- [ ] 84-combination full interop matrix

---

## Phase 3 → Phase 4 Handoff

Once Phase 3 complete:

1. Compile data from PHASE_3_REPAIR_LOG.md
2. Create 31-language master status table
3. Generate executive summary
4. Determine verdict:
   - [ ] `FINAL VERIFIED — RELEASE READY`
   - [ ] `FINAL VERIFIED WITH DOCUMENTED LIMITATIONS` (Most likely)
   - [ ] `NOT RELEASE READY`

**Estimated Phase 4 duration:** 30-45 minutes

---

**Checklist Version:** 1.0  
**Last Updated:** 2026-01-15  
**Status:** Ready for Phase 3 Execution  

---
