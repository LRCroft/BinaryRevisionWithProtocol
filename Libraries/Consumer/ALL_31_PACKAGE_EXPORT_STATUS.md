# VSN-1 ALL-31 Package / Export Status — 2026-10-10

Per-language packaging manifest, installability, and known gaps. All 31 have a usable build recipe
in `run_conformance.py`; the gaps below are installability-only (do NOT affect conformance).

| # | Language | Manifest | Installable | Public entry | Gap |
|---|----------|----------|-------------|-------------|-----|
| 01 | Ada | gnatmake | source build | `Vsn` pkg | none |
| 02 | C | header lib | source build | `vsn.h` | none |
| 03 | COBOL | none | source build | VSN-LIBRARY | none |
| 04 | CSharp | Vsn.csproj | dotnet | `VsnStore` | none |
| 05 | Cpp | none | source build | `vsn.hpp` | none |
| 06 | Crystal | shard.yml | shards | `Vsn` module | none |
| 07 | D | dub.json | dub | `Vsn` module | none |
| 08 | Dart | pubspec.yaml | pub | `Vsn` class | none |
| 09 | Elixir | mix (not committed) | mix | `Vsn` module | mix file not committed |
| 10 | Erlang | rebar.config | rebar3 | `Vsn` module | none |
| 11 | FSharp | Vsn.fsproj | dotnet | `Vsn` module | none |
| 12 | Fortran | Makefile | make | `Vsn` module | none |
| 13 | Go | go.mod | go get | `vsn` pkg | none |
| 14 | Haskell | ghc | cabal/ghc | `Vsn` module | no .cabal/.packaged |
| 15 | Java | none | javac/jar | `VsnLib` | no pom/gradle committed |
| 16 | JavaScript-TypeScript | package.json (CJS/Node16) | npm (fixed 2026-10-10) | `vsn-typescript` | none (fixed) |
| 17 | Julia | none | julia | `Vsn` module | no Project.toml |
| 18 | Kotlin | build.gradle.kts | gradle | `VsnApi`/`Vsn` | none |
| 19 | Lua | none | source | `Vsn` table | none |
| 20 | Nim | none | source | `Vsn` module | none |
| 21 | Objective-C | Dockerfile | source build | `VSN.h` | none |
| 22 | OCaml | none | dune/ocaml | `Vsn` module | no dune file |
| 23 | Perl | none | source/cpan | `Vsn` pkg | no .cpanfile |
| 24 | PHP | none | source/composer | `Vsn` class | no composer.json |
| 25 | Python | NONE | **not pip-installable** | `vsn` pkg | no pyproject/setup (GAP) |
| 26 | R | none | R source | `vsn` fns | no DESCRIPTION |
| 27 | Ruby | none | gem source | `Vsn` module | no .gemspec |
| 28 | Rust | Cargo.toml (vsn-rust) | cargo (fixed 2026-10-10) | `vsn_rust` | none (fixed) |
| 29 | Scala | none | scala-cli | `Vsn` object | no build.sbt |
| 30 | Swift | Package.swift | swiftpm | `Vsn` pkg | none |
| 31 | Zig | build.zig | zig build | `Vsn` pkg | none |

## Key packaging gaps (installability only — no conformance impact)
- **Python:** no `pyproject.toml`/`setup.py`/`setup.cfg` → not pip-installable (import via `sys.path`).
- **Elixir / Haskell / Java / Julia / OCaml / Perl / PHP / R / Ruby / Scala:** no committed package manifest
  (mix/.cabal/pom or gradle/Project.toml/dune/.cpanfile/composer.json/DESCRIPTION/.gemspec/build.sbt); all build & test via their runner toolchain.
- **Rust** and **JavaScript-TypeScript** packaging were fixed this audit cycle (valid crate name + `[lib]` target; CJS/Node16 `exports` + multi-platform esbuild).
