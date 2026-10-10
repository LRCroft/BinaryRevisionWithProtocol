# VSN-1 Consumer Test Report (31 Independent Consumers + 31-Language Public API)

- **Generated:** 2026-10-10 (Act mode)
- **Scope:** Independent consumer tests (31 languages) + 31-language public-API conformance.
- **Method:** Each of the 31 consumers is a **separate project** that uses the library through its **public API only** (no access to internal fields, private modules, or implementation detail). All tests are executed inside their language's canonical Docker image; raw output is captured in `CONSUMER_EVIDENCE.md`.

## Headline results

| Metric | Result | Source |
|--------|--------|--------|
| 31-language public-API conformance | **31/31 VERIFIED** (0 PARTIAL, 0 NOT_VERIFIED), exit 0 | `Libraries/Conformance/run_conformance.py` |
| Storage-policy conformance | **31/31 PASS** (P01-P12) | `run_conformance.py` |
| Frozen vectors | **5/5 SHA-256 MATCH** | `Libraries/TestVectors/manifest.json` |
| Independent consumer tests | **31/31 PASS** (all languages, exit 0) | `Libraries/Consumer/` |

> **Scope:** All 31 languages have an executed *independent consumer project* (exit 0). See `CONSUMER_STATUS.json`.

## Independent consumer results (31)

| # | Language | Consumer project | Result | Exit |
|---|----------|------------------|--------|------|
| 1 | JavaScript-TypeScript | `Consumer/JavaScript-TypeScript` (Node) | **CJS 20/20 + ESM 5/5 PASS** | 0 |
| 2 | Go | `Consumer/Go` | **9/9 PASS** | 0 |
| 3 | C | `Consumer/C` | **10/10 PASS** | 0 |
| 4 | Java | `Consumer/Java` | **10/10 PASS** | 0 |
| 5 | C# | `Consumer/CSharp` | **8/8 PASS** | 0 |
| 6 | Python | `Consumer/Python` | **9/9 PASS** | 0 |
| 7 | Rust | `Consumer/Rust` | **9/9 PASS** | 0 |
| 8 | C++ | `Consumer/Cpp` | **PASS** (create_with_storage_policy_raw → vsn_open().storage_policy==3) | 0 |
| 9 | F# | `Consumer/FSharp` | **PASS** (SP round-trip) | 0 |
| 10 | Lua | `Consumer/Lua` | **PASS** (SP round-trip) | 0 |
| 11 | Kotlin | `Consumer/Kotlin` | **PASS** (VsnApi.parse/parseStoragePolicy SP 1..4 wire-in) | 0 |
| 12 | Swift | `Consumer/Swift` | **PASS** (VsnApi.encode + parseStoragePolicy SP 1..4) | 0 |
| 13 | Ruby | `Consumer/Ruby` | **PASS** (VSN.encode + VSN.parse().storage_policy SP 1..4) | 0 |
| 14 | PHP | `Consumer/PHP` | **PASS** (VSN namespace encode + parse_sp_from_bytes SP 1..4) | 0 |
| 15 | Zig | `Consumer/Zig` | **PASS** (vsn.encode + parseStoragePolicy SP 1..4) | 0 |
| 16 | Ada | `Consumer/Ada` | **PASS** (Create_With_Policy + Export/Import SP 1..4) | 0 |
| 17 | COBOL | `Consumer/COBOL` | **PASS** (op29/30 + op18/19 SP 1..4) | 0 |
| 18 | D | `Consumer/D` | **PASS** (createWithPolicy + export/import SP 1..4) | 0 |
| 19 | Dart | `Consumer/Dart` | **PASS** (encode + parse SP 1..4) | 0 |
| 20 | Elixir | `Consumer/Elixir` | **PASS** (VSN.encode/3 + parse SP 1..4) | 0 |
| 21 | Erlang | `Consumer/Erlang` | **PASS** (vsn:encode/3 + parse SP 1..4) | 0 |
| 22 | Fortran | `Consumer/Fortran` | **PASS** (vsn_encode + vsn_parse_storage_policy SP 1..4) | 0 |
| 23 | Haskell | `Consumer/Haskell` | **PASS** (createWithPolicy + exportBytes/parse SP 1..4) | 0 |
| 24 | Julia | `Consumer/Julia` | **PASS** (VSN.encode + parse SP 1..4) | 0 |
| 25 | Nim | `Consumer/Nim` | **PASS** (encodeWithSP + importBytes SP 1..4) | 0 |
| 26 | Objective-C | `Consumer/Objective-C` | **PASS** (vsn_sp_encode_c + vsn_sp_parse_c SP 1..4) | 0 |
| 27 | OCaml | `Consumer/OCaml` | **PASS** (encode_with_policy + parse SP 1..4) | 0 |
| 28 | Perl | `Consumer/Perl` | **PASS** (VSN::encode + parse SP 1..4) | 0 |
| 29 | R | `Consumer/R` | **PASS** (create_with_policy + export/import SP 1..4) | 0 |
| 30 | Scala | `Consumer/Scala` | **PASS** (VsnApi.encodeWithSP + parseSP SP 1..4) | 0 |
| 31 | Crystal | `Consumer/Crystal` | **PASS** (StoreWithPolicy + parse_sp SP 1..4) | 0 |

## What each consumer exercised (public API only)

- **JavaScript-TypeScript:** built `vsn-typescript` package (CJS `require` + ESM `import`) →
  createFile/readFile/fileExists/writeFile/listRevisions/limitCleanup/commit, validateContainer,
  recoverContainer, VsnStore.open, diff.diffFiles, merge.threeWayMerge/hasConflicts,
  importFile/exportFile, verifyIntegrity, canonicalHash, inspectContainer, StoragePolicy, wire
  modes; plus **cross-language interop** (loads the C-produced frozen DIRECT-02.vsn).
- **Go:** `vsn.Create`, `*VsnStore` (createFile/readFile/fileExists/writeFile/listRevisions/
  limitCleanUp/commit), `vsn.ValidateWithDiagnostics`, `vsn.CreateWithPolicy`.
- **C:** `vsn_create`, file create/read/write, revision list, commit, validate, recover,
  integrity, storage stats, `create_with_policy`.
- **Java:** `Store.create`, createFile/readFile/fileExists, revision, commit, validate, magicCheck,
  recover, `parseStoragePolicy`, `createWithPolicy`.
- **C#:** `VsnStore.Create` + `CreateFile`/`ReadFile`/`FileExists`, revision, commit, `Validate`
  (Full, clean), `Recover`, `VsnStore.Create(StoragePolicy)`.
- **Python:** `vsn.VsnStore.create`, create_file/read_file/file_exists, revision, to_bytes,
  `validate_container` (Full, clean), `recover_container`, StoragePolicy, create(ENTERPRISE).
- **Rust:** `vsn_rust::{MutableStore, encode, parse, verify_integrity, recover, StoragePolicy,
  diff_count}` → create/read, commit_transaction, encode/parse, StoragePolicy 4 values,
  new_with_policy, integrity/recover (valid + invalid), diff_count.
- **C++:** `vsn::create_with_storage_policy_raw(policy)` → `vsn_commit` → `vsn_open(buf,n)` →
  assert `r->storage_policy == 3`; 4-value SP range check (public Cpp wrapper + C core via `vsn.hpp`).
- **F#:** `Vsn.encode`/`parse` + `StoragePolicy` 4 values → SP round-trip for policies 1..4.
- **Lua:** `vsn.encode`/`vsn.parse` (+ `storage_policy` accessor) → SP round-trip for policies 1..4.
- **Kotlin:** `vsn.VsnApi.encode(mode, sp)` + `VsnApi.parseStoragePolicy(data)` + `VsnApi.parse(data).storagePolicy`
  → SP wire-out **and** wire-in for all 4 policies (this consumer caught the RecordsEnd-preamble wire-in bug).
- **Swift:** `VsnApi.encode(mode:gen:storagePolicy:)` + `VsnApi.parseStoragePolicy(_:)` → SP wire-in for all 4.
- **Ruby:** `VSN.encode(mode, gen, sp)` + `VSN.parse(data).storage_policy` → SP wire-in for all 4.
- **PHP:** `\VSN\encode(mode, gen, sp)` + `\VSN\parse_sp_from_bytes(data)` → SP wire-in for all 4.
- **Zig:** `vsn.encode(sp, gen)` + `vsn.parseStoragePolicy(data)` → SP wire-in for all 4
  (this consumer caught the 6-vs-8-byte header framing bug in the Zig parser).

## Packaging fixes reflected here (see PACKAGING_REPORT.md)

- **Rust:** crate `Rust` → `vsn-rust` (lowercase, valid) + explicit `[lib]` + tests updated to `use vsn_rust::*`. Regression: crate `cargo test` 19/19 PASS + SP PASS; this consumer 9/9 PASS.
- **JavaScript-TypeScript:** ESM-only → CommonJS (`"type": "commonjs"`/Node16), removed `"type": "module"`, added `exports`/`types`/`files`, esbuild multi-platform (`linux-x64` + `win32-x64`). Regression: conformance 19/19 PASS; this consumer CJS 20/20 + ESM 5/5 PASS.

## Gaps / blockers (recorded, not fabricated)

- **Python packaging:** no `pyproject.toml`/`setup.py`/`setup.cfg` at `Libraries/Python` → not installable as a distribution (pip-install GAP). The consumer was run via `sys.path` + a local `vsn` package. This does NOT affect the 31/31 conformance (which uses `sys.path.insert`), but it is a real distribution gap (see `PACKAGING_REPORT.md` §3, `PACKAGING_STATUS.json`).

## Cross-references (repository-relative)

- `Libraries/Consumer/CONSUMER_EVIDENCE.md` — raw executed output + commands
- `Libraries/Consumer/CONSUMER_TEST_RESULTS.md` — detailed per-language results
- `Libraries/Consumer/CONSUMER_STATUS.json` — machine-readable, 31 language entries
- `Libraries/Consumer/PACKAGING_REPORT.md` — packaging/manifest analysis
- `Libraries/Consumer/PACKAGING_EVIDENCE.md` — packaging inspection evidence
- `Libraries/Consumer/PACKAGING_STATUS.json` — machine-readable packaging status, 31 language entries
- `Libraries/Conformance/run_conformance.py` — 31-language conformance runner (source of the 31/31 result)