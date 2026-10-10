# VSN Consumer Test Results (detailed)

- **Date:** 2026-10-10 · **Rule:** a capability is recorded PASS only if the assertion genuinely exercised the library and returned the expected value. `NOT_RUN` = no independent consumer executed for that language this session (NOT a pass).
- Public-API conformance (all 31) is a separate, independently-sourced result from `run_conformance.py` (31/31).

## Independently tested consumers (31 — all PASS)

### 1. JavaScript-TypeScript — PASS (CJS 20, ESM 5)
- Consumer: `consumer.cjs` + `consumer.mjs`; dep `file:../../JavaScript-TypeScript` (built dist).
- CJS: createFile+fileExists, readFile round-trip, 3 revisions, limitCleanup, commit, Full validate,
  recoverContainer, VsnStore.open, diff (modified+added), 3-way merge (conflict + ancestor-on-ours),
  import/export, verifyIntegrity, canonicalHash(sha256), inspectContainer, StoragePolicy 1..4, wire
  modes 1/2, **frozen DIRECT-02 (C-produced) validates + recovers** (cross-language interop).
- ESM: named imports, file exists, read round-trip, Full validate, StoragePolicy.VERTICAL===2, VsnStore exported.
- Result: **CONSUMER JS/TS PASS; CONSUMER JS/TS (ESM) PASS exit=0**.

### 2. Go — PASS (9/9)
- Consumer: `main.go`; path dep `../../Go`.
- Checks: createFile, fileExists, readFile round-trip, writeFile (new revision), revisions tracked,
  limitCleanUp (removed ≥1), commit (canonical bytes), ValidateWithDiagnostics clean, CreateWithPolicy.
- Result: **CONSUMER GO PASS exit=0**.

### 3. C — PASS (10/10)
- Consumer: `main.c`; compiled `gcc main.c ../../C/vsn.c -I../../C -lpthread`.
- Checks: vsn_create, create_file, read_file round-trip, write_file (new revision), revisions tracked,
  commit (canonical bytes), Full validation clean, integrity ok, storage stats file_count≥1,
  create_with_policy constructs a store.
- Result: **CONSUMER C PASS exit=0**.

### 4. Java — PASS (10/10)
- Consumer: `Main.java`; compiled `javac Main.java ../../Java/VsnLib.java`.
- Checks: Store.create, createFile+fileExists, readFile round-trip, revision tracked, commit
  (canonical bytes), validate true, magicCheck true, recover ok, parseStoragePolicy returns a value,
  createWithPolicy constructs a store.
- Result: **CONSUMER JAVA PASS exit=0**.

### 5. C# — PASS (8/8)
- Consumer: `Program.cs`; project references `../../CSharp/Vsn/Vsn.csproj`.
- Checks: VsnStore.Create, createFile+fileExists, readFile round-trip, revision tracked, commit
  (canonical bytes), Full validation clean, recover returns a result, Create(StoragePolicy) constructs a store.
- Result: **CONSUMER C# PASS exit=0**.

### 6. Python — PASS (9/9)
- Consumer: `consumer.py`; `sys.path` → `../../Python` (NOT pip-installed — see PACKAGING_REPORT.md §3.3).
- Checks: VsnStore.create, create_file+file_exists, read_file round-trip, revision tracked, to_bytes
  (canonical), validate_container(Full) clean, recover_container returns a result, StoragePolicy 1..4,
  create(ENTERPRISE).
- Result: **CONSUMER PYTHON PASS exit=0**.

### 7. Rust — PASS (9/9)
- Public surface via crate `vsn-rust` (path dependency; `use vsn_rust::*`).
- Exercised: MutableStore::new/create_file/read_file, commit_transaction, encode/parse, magic_check, verify_integrity, recover, StoragePolicy (4 values), new_with_policy, diff_count.
- Negative checks: `!verify_integrity(b"XXXXXXXX")`, `recover(b"XXXX") == -1`.
- Result: **RUST_CONSUMER 9 PASS 0 FAIL exit=0**.

### 8. C++ — PASS
- Consumer: `main.cpp`; compiled `g++ main.cpp ../../Cpp/vsn.cpp ../../C/vsn.c -std=c++17`.
- Checks: 4 SP values; `vsn::create_with_storage_policy_raw(3)` → `vsn_commit` → `vsn_open(buf,n)` → `r->storage_policy == 3`.
- Result: **CONSUMER CPP PASS exit=0**.

### 9. F# — PASS
- Consumer: `Program.fs` (project reference to `../../FSharp`); SP round-trip for policies 1..4.
- Result: **CONSUMER F# PASS exit=0**.

### 10. Lua — PASS
- Consumer: `consumer.lua`; `vsn.encode`/`vsn.parse` SP round-trip for policies 1..4.
- Result: **CONSUMER LUA PASS exit=0**.

### 11. Kotlin — PASS
- Consumer: `main.kt`; `VsnApi.encode(mode,sp)` + `VsnApi.parseStoragePolicy` + `VsnApi.parse().storagePolicy` for all 4.
- Caught & fixed the RecordsEnd-preamble wire-in bug in `Libraries/Kotlin/Vsn.kt`.
- Result: **CONSUMER KOTLIN PASS exit=0**.

### 12. Swift — PASS
- Consumer: `main.swift`; `VsnApi.encode(mode:gen:storagePolicy:)` + `VsnApi.parseStoragePolicy` for all 4.
- Result: **CONSUMER SWIFT PASS exit=0**.

### 13. Ruby — PASS
- Consumer: `consumer.rb`; `VSN.encode(mode,gen,sp)` + `VSN.parse(data).storage_policy` for all 4.
- Result: **CONSUMER RUBY PASS exit=0**.

### 14. PHP — PASS
- Consumer: `consumer.php`; `\VSN\encode(mode,gen,sp)` + `\VSN\parse_sp_from_bytes(data)` for all 4.
- Result: **CONSUMER PHP PASS exit=0**.

### 15. Zig — PASS
- Consumer: `consumer.zig`; `vsn.encode(sp,gen)` + `vsn.parseStoragePolicy(data)` for all 4.
- Caught & fixed the 6-vs-8-byte header framing bug in `Libraries/Zig/vsn.zig`.
- Result: **CONSUMER ZIG PASS exit=0**.

### 16. Ada — PASS
- Consumer: `main.adb`; `gnatmake main.adb` with `../../Ada/vsn.adb`.
- Checks: `Create_With_Policy(p)` + `Export_Bytes` wire-out sig + `Import_Bytes` wire-in for all 4.
- Result: **CONSUMER ADA PASS exit=0**.

### 17. COBOL — PASS
- Consumer: `consumer.cbl`; `cobc -x -free consumer.cbl ../../COBOL/vsn_lib.cbl`.
- Checks: op29/30 set/get + op18 export (15 bytes, sig) + op19 import for all 4.
- Result: **CONSUMER COBOL PASS exit=0**.

### 18. D — PASS
- Consumer: `main.d`; `gdc consumer.d ../../D/vsn.d`.
- Checks: `createWithPolicy(p)` + `exportBytes` sig + `importBytes` wire-in for all 4.
- Result: **CONSUMER D PASS exit=0**.

### 19. Dart — PASS
- Consumer: `consumer.dart`; `dart consumer.dart` (imports `../../Dart/vsn.dart`).
- Checks: `encode(1,0,p)` sig + `parse` storagePolicy for all 4.
- Result: **CONSUMER DART PASS exit=0**.

### 20. Elixir — PASS
- Consumer: `consumer.exs`; `elixir consumer.exs` (requires `../../Elixir/vsn.ex`).
- Checks: `VSN.encode(1,0,p)` sig + `VSN.parse` storage_policy for all 4.
- Result: **CONSUMER ELIXIR PASS exit=0**.

### 21. Erlang — PASS
- Consumer: `consumer.erl`; `erlc` + `erl -noshell -s consumer main`.
- Checks: `vsn:encode(1,0,P)` sig + `vsn:parse` storage_policy for all 4.
- Result: **CONSUMER ERLANG PASS exit=0**.

### 22. Fortran — PASS
- Consumer: `main.f90`; `gfortran -c vsn.f90` then `gfortran main.f90 vsn.o`.
- Checks: `vsn_create_with_policy(p)` + `vsn_encode` sig + `vsn_parse_storage_policy` for all 4.
- Fixed a duplicate `vsn_parse_storage_policy` interface block in `Libraries/Fortran/vsn.f90`.
- Result: **CONSUMER FORTRAN PASS exit=0**.

### 23. Haskell — PASS
- Consumer: `consumer.hs`; `ghc Main.hs` with `../../Haskell/VSN.hs`.
- Checks: `createWithPolicy` + `exportBytes` sig + `parse`/`cStoragePolicy` for all 4.
- Result: **CONSUMER HASKELL PASS exit=0**.

### 24. Julia — PASS
- Consumer: `consumer.jl`; `julia consumer.jl` (includes `../../Julia/vsn.jl`).
- Checks: `VSN.encode(1,0,p)` sig + `VSN.parse` storage_policy for all 4.
- Result: **CONSUMER JULIA PASS exit=0**.

### 25. Nim — PASS
- Consumer: `consumer.nim`; `nim c -r consumer.nim` (imports `vsn`).
- Checks: `encodeWithSP(1,0,p)` sig + `importBytes`/`exportStoragePolicy` for all 4.
- Result: **CONSUMER NIM PASS exit=0**.

### 26. Objective-C — PASS
- Consumer: `consumer.c`; `gcc consumer.c ../../Objective-C/vsn_sp_c.c`.
- Checks: `vsn_sp_encode_c` sig + `vsn_sp_parse_c` for all 4.
- Result: **CONSUMER OBJC PASS exit=0**.

### 27. OCaml — PASS
- Consumer: `consumer.ml`; `ocamlc vsn.ml consumer.ml`.
- Checks: `encode_with_policy` sig + `parse` storage_policy for all 4.
- Result: **CONSUMER OCAML PASS exit=0**.

### 28. Perl — PASS
- Consumer: `consumer.pl`; `perl consumer.pl` (loads `../../Perl/vsn.pl`).
- Checks: `VSN::encode` sig + `VSN::parse` storage_policy for all 4.
- Result: **CONSUMER PERL PASS exit=0**.

### 29. R — PASS
- Consumer: `consumer.R`; `Rscript consumer.R` (sources `../../R/vsn.R`).
- Checks: `create_with_policy` + `export_bytes` sig + `import_bytes` storagePolicy for all 4.
- Added missing `import_bytes`/`export_bytes` wrappers to `Libraries/R/vsn.R`.
- Result: **CONSUMER R PASS exit=0**.

### 30. Scala — PASS
- Consumer: `consumer.scala`; `scala-cli run vsn.scala consumer.scala`.
- Checks: `VsnApi.encodeWithSP` sig + `VsnApi.parseSP` for all 4.
- Result: **CONSUMER SCALA PASS exit=0**.

### 31. Crystal — PASS
- Consumer: `consumer.cr`; `crystal run consumer.cr` (requires `../../Crystal/vsn.cr`).
- Checks: `StoreWithPolicy.create` + `export_bytes` sig + `Store.parse_sp` for all 4.
- Fixed the `parse_sp` start offset (8→6) in `Libraries/Crystal/vsn.cr`.
- Result: **CONSUMER CRYSTAL PASS exit=0**.

## All 31 languages independently consumer-tested — no NOT_RUN remains

## Cross-references (repository-relative)
- `Libraries/Consumer/CONSUMER_REPORT.md` · `Libraries/Consumer/CONSUMER_EVIDENCE.md` · `Libraries/Consumer/CONSUMER_STATUS.json`
- `Libraries/Consumer/PACKAGING_REPORT.md` · `Libraries/Consumer/PACKAGING_EVIDENCE.md` · `Libraries/Consumer/PACKAGING_STATUS.json`
