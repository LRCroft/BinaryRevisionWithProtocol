# VSN-1 Packaging Evidence (raw, unmodified)

- **Date:** 2026-10-10 · **Method:** source inspection + executed build/test in canonical Docker images.
- All commands executed; outputs captured (truncated to the material result).

## 1. Python packaging GAP (Libraries/Python)

```
cmd : dir Libraries/Python   (top-level)
  files: conformance_test.py, storage_policy_tests.py, test_*.py, test_vsn.py, tests/
  NO pyproject.toml / setup.py / setup.cfg
cmd : import vsn  (without sys.path insert)
  ModuleNotFoundError: No module named 'vsn'
cmd : python -c "import sys; sys.path.insert(0, 'Libraries/Python'); import vsn; ..."
  vsn OK  (VsnStore, StoragePolicy present)   (consumer.py resolves Libraries/Python via ../../Python)
```
**Conclusion:** `vsn` is not a pip-installable distribution (no packaging metadata). Usable via `sys.path`. The 31/31 conformance (which uses `sys.path.insert`) is unaffected.

## 2. Rust packaging fix (Libraries/Rust)

Before:
```toml
[package]
name = "Rust"          # INVALID for external consumers; all-caps
version = "0.1.0"
edition = "2021"
# no [lib] target; tests/ only
```
After:
```toml
[package]
name = "vsn-rust"
version = "0.1.0"
edition = "2021"

[lib]
name = "vsn_rust"
path = "src/lib.rs"
```
`tests/test_vsn.rs`: `use Rust::*;` → `use vsn_rust::*;`

Regression evidence:
```
cmd (crate) : cargo test -- --nocapture
  all_capabilities ... ok   (19/19)
  storage_policy_conformance ... ok
cmd (consumer) : Libraries/Consumer/Rust  ->  cargo run --quiet
  RUST_CONSUMER 9 PASS 0 FAIL exit=0
```

## 3. JavaScript-TypeScript packaging fix (Libraries/JavaScript-TypeScript)

Before: `"type": "module"` (ESM-only) + `main`/`exports` pointing at a non-existent build + esbuild emitting a Linux `.node`.
After (`package.json`):
```json
{
  "name": "vsn-typescript",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "files": ["dist"],
  "type": "commonjs",
  "exports": { ".": { "types": "./dist/index.d.ts", "require": "./dist/index.js", "import": "./dist/index.js" } },
  "scripts": { "build": "node build.mjs", "build-win": "node build.mjs --win32-x64", "test": "npm run build && node tests/test_vsn.js" }
}
```
esbuild multi-platform (build.mjs): `--platform=node --format=cjs` → **linux-x64** (default) + **win32-x64** (`--win32-x64`).

Regression evidence:
```
cmd (conformance) : node:20-slim  ->  npx tsx tests/test_vsn_caps.ts
  CAP 01..19 PASS   (19/19, exit 0)   [part of the 31/31 run]
cmd (consumer) : cd Libraries/Consumer/JavaScript-TypeScript && npm install && node consumer.cjs
  CONSUMER JS/TS PASS   (20 ok checks; loads C-produced frozen DIRECT-02.vsn)
cmd (consumer) : node consumer.mjs
  CONSUMER JS/TS (ESM) PASS   (5 ok checks)
```

## 4. 31-language packaging/manifest inventory (from `dir Libraries/<Lang>`)

```
Ada                 vsn.adb, vsn.ads                 (gnatmake; no package manifest)
C                   vsn.c, vsn.h                     (header lib; no manifest)
COBOL               vsn_lib.cbl                      (none)
CSharp              Vsn.csproj, Vsn.slnx, Vsn/*.cs   (.NET project)
Cpp                 vsn.cpp, vsn.hpp                 (none)
Crystal             shard.yml, vsn.cr                (shard)
D                   dub.json, vsn.d                  (dub)
Dart                pubspec.yaml, vsn.dart           (pub)
Elixir              vsn.ex                           (mix; none committed)
Erlang              rebar.config, vsn.erl            (rebar)
FSharp              Vsn.fsproj, Vsn/*.fs             (.NET project)
Fortran             Makefile, vsn.f90                (Makefile)
Go                  go.mod, *.go                     (module github.com/vsn/vsn)
Haskell             VSN.hs, Hash.hs                  (ghc; none)
Java                VsnLib.java                      (single class)
JavaScript-TypeScript package.json, src/*.ts, dist/  (vsn-typescript, CJS/Node16) [FIXED]
Julia               vsn.jl                           (none)
Kotlin              build.gradle.kts, Vsn.kt         (Gradle)
Lua                 vsn.lua                          (none)
Nim                 vsn.nim                          (none)
Objective-C         VSN.h, VSN.m, Dockerfile         (none / Dockerfile)
OCaml               vsn.ml                           (none)
Perl                vsn.pl                           (none)
PHP                 vsn.php                          (none)
Python              vsn/*.py                         (NO packaging metadata) [GAP]
R                   vsn.R                            (none)
Ruby                vsn.rb                           (none)
Rust                Cargo.toml (vsn-rust), src/lib.rs [FIXED]
Scala               vsn.scala                        (scala-cli; none)
Swift               Package.swift, Vsn.swift         (SwiftPM)
Zig                 build.zig, vsn.zig               (zig build)
```

## 5. Cross-references (repository-relative)
- `Libraries/Consumer/PACKAGING_REPORT.md` — analysis & verdicts
- `Libraries/Consumer/PACKAGING_STATUS.json` — machine-readable (31 entries)
- `Libraries/Consumer/CONSUMER_EVIDENCE.md` — consumer test evidence (the regression side)
- `Libraries/Rust/Cargo.toml` · `Libraries/JavaScript-TypeScript/package.json` · `Libraries/Conformance/run_conformance.py`