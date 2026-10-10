# VSN Packaging Report

- **Generated:** 2026-10-10 (Act mode)
- **Scope:** Packaging/manifest analysis of all 31 language libraries + the two packaging fixes (Rust, JS/TS) + gaps. Raw inspection output in `PACKAGING_EVIDENCE.md`; machine-readable status in `PACKAGING_STATUS.json`.
- **Rule:** statuses are recorded from actual inspection/execution; no untested capability is marked usable.

## 1. The two packaging fixes (both regression-verified)

### A. Rust — crate name invalid for external consumers (FIXED)
- **Problem:** `Cargo.toml` declared `[package] name = "Rust"` (all-caps). A downstream consumer cannot depend on it via `{ path = ".../Rust" }` because the crate identifier `Rust` is not a valid Rust package name, and no `[lib]` target was declared (a package with only `tests/` and no `src/`/`[lib]` cannot be depended upon).
- **Fix:** renamed to `vsn-rust` (lowercase, valid), added explicit `[lib] name = "vsn_rust" path = "src/lib.rs"`, updated `tests/test_vsn.rs` to `use vsn_rust::*`.
- **Regression evidence:** (1) the library crate `cargo test` → **19/19 capabilities + SP PASS**; (2) independent consumer `Libraries/Consumer/Rust` (path dep `vsn-rust`) → **9/9 PASS, exit 0** (see `CONSUMER_EVIDENCE.md` §7).

### B. JavaScript-TypeScript — ESM-only package + Linux-only prebuild (FIXED)
- **Problem:** `package.json` had `"type": "module"` (ESM-only) with a CJS-style `main`/`exports` pointing at a build that didn't exist; consumers using `require()`/CommonJS failed; and esbuild emitted a **Linux** `.node` binary unusable on Windows.
- **Fix:** set `"type": "commonjs"` (Node16 CJS default), removed `"type": "module"`, added `exports` (require/import), `types` (`dist/index.d.ts`), `files` (`dist`); added an esbuild multi-platform build step (`--platform=node --format=cjs`, `--external:esbuild`, `--external:node:*`) producing `linux-x64` **and** `win32-x64`; the conformance runner (`run_conformance.py`) now runs `npm install` before the TS tests.
- **Regression evidence:** (1) conformance `npx tsx tests/test_vsn_caps.ts` → **19/19 PASS, exit 0** (part of the 31/31 run); (2) independent consumer `Libraries/Consumer/JavaScript-TypeScript` → **CJS 20/20 + ESM 5/5, exit 0** (see `CONSUMER_EVIDENCE.md` §1).

## 2. Per-language packaging / public entry (all 31)

| # | Language | Manifest / build | Public entry (consumer-facing) | Packaging status |
|---|----------|------------------|--------------------------------|------------------|
| 1 | Ada | gnatmake (no package manifest) | GNAT package `Vsn` | source-tree only |
| 2 | C | header library (no manifest) | `vsn.h` C API | source-tree only (usable, compiled with `vsn.c`) |
| 3 | COBOL | none | `VSN-LIBRARY` | source-tree only |
| 4 | CSharp | `Vsn.csproj`, `Vsn.slnx` | `VsnStore` | .NET project (usable via project reference) |
| 5 | Cpp | none | `vsn.hpp` | source-tree only |
| 6 | Crystal | `shard.yml` | `Vsn` module | source-tree only |
| 7 | D | `dub.json` | `Vsn` module | source-tree only |
| 8 | Dart | `pubspec.yaml` | `Vsn` class | source-tree only |
| 9 | Elixir | (mix, none committed) | `Vsn` module | source-tree only |
| 10 | Erlang | `rebar.config` | `Vsn` module | source-tree only |
| 11 | FSharp | `Vsn.fsproj` | F# module `Vsn` | .NET project (usable via project reference) |
| 12 | Fortran | `Makefile` | `Vsn` module | source-tree only |
| 13 | Go | `go.mod` (module `github.com/vsn/vsn`) | `Create`, `VsnStore`, `StoragePolicy` | Go module (usable via `replace` or path) |
| 14 | Haskell | none (ghc) | `Vsn` module | source-tree only |
| 15 | Java | none (single class) | `VsnLib` class | source-tree only (usable, compiled against `VsnLib.java`) |
| 16 | JavaScript-TypeScript | `package.json` (`vsn-typescript`, CJS/Node16) | `vsn-typescript` (dist) | **FIXED** — CJS+ESM dual, multi-platform; consumer-ready |
| 17 | Julia | none | `Vsn` module | source-tree only |
| 18 | Kotlin | `build.gradle.kts` | `VsnApi` / `Vsn` | source-tree only |
| 19 | Lua | none | `Vsn` table | source-tree only |
| 20 | Nim | none | `Vsn` module | source-tree only |
| 21 | Objective-C | `Dockerfile` | `VSN` C API | source-tree only |
| 22 | OCaml | none | `Vsn` module | source-tree only |
| 23 | Perl | none | `Vsn` package | source-tree only |
| 24 | PHP | none | `Vsn` class | source-tree only |
| 25 | Python | **NONE (no `pyproject.toml`/`setup.py`/`setup.cfg`)** | `vsn` package (`VsnStore`) | **GAP** — not installable as a distribution (pip); usable via `sys.path` |
| 26 | R | none | `vsn` functions | source-tree only |
| 27 | Ruby | none | `Vsn` module | source-tree only |
| 28 | Rust | `Cargo.toml` (crate `vsn-rust`) | crate `vsn_rust` (`Store`, `MutableStore`, `encode`, …) | **FIXED** — valid crate name + `[lib]`; consumer-ready via path/version |
| 29 | Scala | none (scala-cli) | `Vsn` object | source-tree only |
| 30 | Swift | `Package.swift` | `Vsn` package | SwiftPM package (usable via path dependency) |
| 31 | Zig | `build.zig` | `Vsn` package | source-tree / zig build |

## 3. Gaps / blockers (recorded, not fabricated)

| Language | Gap | Impact | Workaround used |
|----------|-----|--------|-----------------|
| **Python** | No `pyproject.toml`/`setup.py`/`setup.cfg` in `Libraries/Python` | `pip install` / distribution packaging is not possible; `import vsn` only works via `sys.path` | Consumer + conformance runner use `sys.path.insert(0, ...)` + a local `vsn` package. **Does not affect the 31/31 conformance result.** |
| 24 of 31 | Source-tree-only (no installable distribution manifest in some) | Consumers must compile against the source tree (path dependency / project reference / module path) | This is normal for most of these languages (Ada, COBOL, Cpp, Erlang, Haskell, …); all have a usable build recipe in the conformance runner. |

**Not a gap (working as designed):** Rust and JS/TS had *broken* consumer packaging and are now fixed + regression-verified. All other languages are "source-tree usable" — a normal, expected state, not a defect.

## 4. Notes on the two fixes vs. "publishing"
- No packages were **published** to any registry (no `npm publish`, no `cargo publish`, no `pip`/PyPI upload, no `dotnet publish` to a feed). Both fixes are local/consumer-side and verified by build + test only.
- No Git commits were made; no frozen vectors were modified.

## 5. Cross-references (repository-relative)
- `Libraries/Consumer/PACKAGING_EVIDENCE.md` — raw packaging inspection output
- `Libraries/Consumer/PACKAGING_STATUS.json` — machine-readable packaging status (31 entries)
- `Libraries/Consumer/CONSUMER_REPORT.md` · `Libraries/Consumer/CONSUMER_EVIDENCE.md` · `Libraries/Consumer/CONSUMER_TEST_RESULTS.md` · `Libraries/Consumer/CONSUMER_STATUS.json`
- `Libraries/Rust/Cargo.toml` (fixed), `Libraries/JavaScript-TypeScript/package.json` (fixed)
- `Libraries/Conformance/run_conformance.py` (JS/TS `npm install` step added)
