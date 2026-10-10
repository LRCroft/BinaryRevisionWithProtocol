# VSN Consumer Test Evidence (raw, unmodified)

- **Date:** 2026-10-10 · **Environment:** Windows, Docker (canonical per-language images)
- All commands below were executed and the outputs captured verbatim (truncated to the result summary).
- Repo-relative consumer paths: `Libraries/Consumer/<Lang>/`.

## 1. JavaScript-TypeScript (node:20-slim)

```
cmd : npm install   (consumer dependency: file:../../JavaScript-TypeScript, built dist)
cmd : node consumer.cjs
ok  - file exists after createFile
ok  - readFile round-trips content
ok  - three revisions tracked
ok  - limitCleanup removed >= 1 revision
ok  - revisions now <= 2
ok  - commit produced canonical bytes
ok  - Full validation is clean
ok  - recoverContainer returns a result
ok  - reopened store exposes file by path
ok  - diff detects modified + added files
ok  - conflicting merge reports a conflict
ok  - ancestor-on-ours merges cleanly
ok  - import/export round-trips
ok  - verifyIntegrity returns a report
ok  - canonicalHash is a sha256 hex digest
ok  - inspectContainer reports fileCount
ok  - StoragePolicy values 1..4
ok  - wire modes 1/2
ok  - frozen DIRECT-02 validates
ok  - frozen DIRECT-02 recovers
CONSUMER JS/TS PASS
cmd : node consumer.mjs
ok  - ESM: file exists
ok  - ESM: read round-trips
ok  - ESM: Full validation clean
ok  - ESM: StoragePolicy.VERTICAL === 2
ok  - ESM: VsnStore class is exported
CONSUMER JS/TS (ESM) PASS
```
(CJS 20 + ESM 5 checks; loads the C-produced frozen DIRECT-02.vsn — cross-language interop.)

## 2. Go (golang:1.23-alpine)

```
cmd : go run .
ok  - createFile
ok  - fileExists
ok  - readFile round-trips
ok  - writeFile new revision
ok  - revisions tracked
ok  - limitCleanUp removed >= 1
ok  - commit produced canonical bytes
ok  - Full validation clean (ValidateWithDiagnostics)
ok  - CreateWithPolicy constructs a store
CONSUMER GO PASS
```

## 3. C (vsn-deb:latest, gcc)

```
cmd : gcc -o /tmp/consumer main.c ../../C/vsn.c -I../../C -lpthread && /tmp/consumer
ok  - vsn_create
ok  - create_file
ok  - read_file round-trips
ok  - write_file new revision
ok  - revisions tracked
ok  - commit produced canonical bytes
ok  - Full validation clean
ok  - integrity ok
ok  - storage stats file_count >= 1
ok  - create_with_policy constructs a store
CONSUMER C PASS
```

## 4. Java (vsn-deb:latest, javac+java)

```
cmd : javac -d /tmp/classes Main.java ../../Java/VsnLib.java && java -cp /tmp/classes Main
ok  - Store.create
ok  - createFile + fileExists
ok  - readFile round-trips
ok  - revision tracked
ok  - commit produced canonical bytes
ok  - validate returns true
ok  - magicCheck true
ok  - recover ok
ok  - parseStoragePolicy returns a value
ok  - createWithPolicy constructs a store
CONSUMER JAVA PASS
```

## 5. C# (mcr.microsoft.com/dotnet/sdk:10.0)

```
cmd : dotnet run
ok  - VsnStore.Create
ok  - createFile + fileExists
ok  - readFile round-trips
ok  - revision tracked
ok  - commit produced canonical bytes
ok  - Full validation is clean
ok  - recover returns a result
ok  - Create(StoragePolicy) constructs a store
CONSUMER C# PASS
```

## 6. Python (python:3.11-slim)

```
cmd : python consumer.py
ok  - VsnStore.create
ok  - create_file + file_exists
ok  - read_file round-trips
ok  - revision tracked
ok  - to_bytes produced canonical bytes
ok  - validate_container (Full) clean
ok  - recover_container returns a result
ok  - StoragePolicy values (1..4)
ok  - create(ENTERPRISE)
CONSUMER PYTHON PASS
```
(Run via `sys.path` → `../../Python`; NOT pip-installed — see `PACKAGING_REPORT.md` §3.3 for the pip-install GAP.)

## 7. Rust (rust:1-slim)

```
cmd : cargo run --quiet
PASS 2-digit 1 lifecycle create/read round-trip
PASS 2-digit 2 commit_transaction returns container bytes
PASS 2-digit 3 encode output has VSN magic
PASS 2-digit 4 parse round-trips encoded container
PASS 2-digit 5 StoragePolicy 4 values defined
PASS 2-digit 6 store created with HORIZONTAL policy is valid
PASS 2-digit 7 integrity+recover accept valid container
PASS 2-digit 8 integrity+recover reject invalid input
PASS 2-digit 9 diff_count reflects differing file sets
RUST_CONSUMER 9 PASS 0 FAIL exit=0
```
(Dependency: `vsn-rust = { path = "../../Rust" }` — uses the renamed crate; `use vsn_rust::*`.)

## 8. New independent consumers (16 — all exit 0, this session)

```
cmd : gnatmake main.adb (Ada/vsn.adb) && ./main
CONSUMER ADA PASS
cmd : cobc -x -free consumer.cbl vsn_lib.cbl -o consumer && ./consumer
CONSUMER COBOL PASS
cmd : gdc consumer.d vsn.d -o consumer && ./consumer
CONSUMER D PASS
cmd : dart consumer.dart
CONSUMER DART PASS
cmd : elixir consumer.exs
CONSUMER ELIXIR PASS
cmd : erlc consumer.erl vsn.erl && erl -noshell -s consumer main -s init stop
CONSUMER ERLANG PASS
cmd : gfortran -c vsn.f90 && gfortran main.f90 vsn.o -o consumer && ./consumer
CONSUMER FORTRAN PASS
cmd : ghc Main.hs && ./Main
CONSUMER HASKELL PASS
cmd : julia consumer.jl
CONSUMER JULIA PASS
cmd : nim c -r consumer.nim
CONSUMER NIM PASS
cmd : gcc consumer.c vsn_sp_c.c -o consumer && ./consumer
CONSUMER OBJC PASS
cmd : ocamlc vsn.ml consumer.ml -o consumer && ./consumer
CONSUMER OCAML PASS
cmd : perl consumer.pl
CONSUMER PERL PASS
cmd : Rscript consumer.R
CONSUMER R PASS
cmd : scala-cli run vsn.scala consumer.scala
CONSUMER SCALA PASS
cmd : crystal run consumer.cr
CONSUMER CRYSTAL PASS
```
(Each asserts SP wire-out signature + wire-in round-trip for policies 1..4.)

## 9. 31-language public-API conformance (run_conformance.py)

```
cmd : python Libraries/Conformance/run_conformance.py
FINAL VERDICT: 31/31 VERIFIED, 0/31 PARTIAL, 0/31 NOT_VERIFIED
STORAGE POLICY CONFORMANCE: 31/31 PASS
FROZEN VECTORS: 5/5 SHA-256 MATCH
RUNNER_EXIT_CODE: 0
```

## 10. Frozen vectors (Libraries/TestVectors/manifest.json)

```
DIRECT-01.vsn              d4c31c910973577359bbba7f06c71e086bbcae310bef0709667a22deba5f4426  MATCH
DIRECT-02.vsn              1af182c3271b9b40c318c5f9928f23c21684df88e627813460ba98c2a2d08324  MATCH
DIRECT-03.vsn              25f9874796dc04079374f561abf1951d692b0779ecd261a22107f73cea7b66a4  MATCH
EXT-01.vsn                 486fdff3dc19872ff2a0c708f51466ac470d053cbceabb9e36d5f00241cab9c6  MATCH
EXT-02-and-EXT-03.vsn      d1baabce8123f3984c3e7fded6cbc3a386ad9df77ca85e9dd642362a7857be90  MATCH
```

## Cross-references (repository-relative)

- `Libraries/Consumer/CONSUMER_REPORT.md` — summary report
- `Libraries/Consumer/CONSUMER_TEST_RESULTS.md` — detailed per-language results
- `Libraries/Consumer/CONSUMER_STATUS.json` — machine-readable (31 entries)
- `Libraries/Consumer/PACKAGING_EVIDENCE.md` — packaging inspection evidence
- `Libraries/Consumer/PACKAGING_REPORT.md` — packaging analysis
- `Libraries/Consumer/PACKAGING_STATUS.json` — machine-readable packaging status (31 entries)
