# VSN-1 Build Report — Distributable Libraries (31/31)

**Generated:** 2026-10-10 · **Output:** `Libraries/Compiled/<Lang>/` · **Manifest:** `Libraries/Compiled/BUILD_MANIFEST.json`

**Result: 31/31 languages built (PASS), 31/31 external-consumer tested (PASS, exit 0), 0 FAIL, 0 BLOCKED, 0 NOT_RUN.**

Builds were staged under `Libraries/Compiled_staging/<Lang>/`, each artifact's independent consumer
(`Libraries/Consumer/<Lang>/`) was re-run against the **staged** copy, and only on success was staging
promoted to `Compiled/`. Frozen protocol vectors are unchanged (5/5 SHA-256 MATCH). Storage Policy
values 1-4 encode/decode through each public API.

## Distributables

| # | Language | Artifact(s) | Build command (toolchain) | Consumer result |
|---|----------|-------------|---------------------------|-----------------|
| 01 | C | `libvsn.a`, `libvsn.so`, `vsn.h` | `gcc -O2 -c/-shared vsn.c` (vsn-deb) | PASS |
| 02 | Cpp | `libvsncpp.a/.so`, `vsn.hpp` | `g++ -O2 -std=c++17 vsn.cpp` (gcc:13) | PASS |
| 03 | Objective-C | `libvsnobjc.a/.so`, `VSN.h`, `vsn_sp_c.c` | `gcc -O2 vsn_sp_c.c` (vsn-objc) | PASS |
| 04 | Ada | `vsn.adb/.ads` (+`.ali/.o`) | `gnatmake -c vsn.adb` (vsn-deb) | PASS |
| 05 | Fortran | `libvsnfortran.a`, `vsn.f90`, `.mod` | `gfortran -O2 -c vsn.f90` (vsn-deb) | PASS |
| 06 | COBOL | `vsn_lib.cbl` (+`.o`) | `cobc -free -O2 -c vsn_lib.cbl` (vsn-deb) | PASS |
| 07 | D | `libvsnd.a`, `vsn.d` | `dmd -c vsn.d` (vsn-d) | PASS |
| 08 | Zig | `libvsnzig.a`, `vsn.zig` | `zig build-lib vsn.zig` (vsn-zig) | PASS |
| 09 | Nim | `libvsnnim.a`, `vsn.nim` | `nim c --app:staticlib vsn.nim` (vsn-deb) | PASS |
| 10 | Haskell | `libvsnhaskell.a`, `VSN.hs` (+`.o/.hi`) | `ghc -O2 -c VSN.hs` (haskell:9.6) | PASS |
| 11 | OCaml | `vsn.cma/.cmo/.cmi`, `vsn.ml` | `ocamlc -c vsn.ml` (vsn-deb) | PASS |
| 12 | Erlang | `vsn.beam`, `vsn.erl` | `erlc vsn.erl` (erlang:27) | PASS |
| 13 | Elixir | `Elixir.VSN*.beam`, `vsn.ex` | `elixirc vsn.ex` (elixir:1.17) | PASS |
| 14 | Java | `vsn-java.jar` | `javac + jar` (vsn-deb) | PASS |
| 15 | Kotlin | `vsn-kotlin.jar` | `kotlinc Vsn.kt -d jar` (vsn-jvm) | PASS |
| 16 | Scala | `vsn-scala.jar` | `scala-cli --power package` (vsn-jvm:with-scalacli) | PASS |
| 17 | Swift | `VSN.swiftmodule`, `Vsn.swift` | `swift build -c release` (swift:5.9) | PASS |
| 18 | CSharp | `Vsn.dll` (+`.cs`/`.csproj`) | `dotnet build -c Release` (.NET 10) | PASS |
| 19 | FSharp | `Vsn.dll` (+`.fs`/`.fsproj`) | `dotnet build -c Release` (.NET 10) | PASS |
| 20 | Rust | `libvsn_rust.rlib`, `src/`, `Cargo.toml` | `cargo build --release` (rust:1-slim) | PASS |
| 21 | Go | `*.go` module, `go.mod` | `go build ./...` (golang:1.23) | PASS |
| 22 | JavaScript-TypeScript | `dist/` (JS + `.d.ts`), `package.json` | `tsc -p tsconfig.json` (node 20) | PASS |
| 23 | Python | `vsn/` package | copy source package (py 3.11+) | PASS |
| 24 | Julia | `vsn.jl` | source module (julia) | PASS |
| 25 | R | `vsn.R` | source script (Rscript) | PASS |
| 26 | Lua | `vsn.lua` | source module (lua) | PASS |
| 27 | PHP | `vsn.php` | source module (php 8.3) | PASS |
| 28 | Ruby | `vsn.rb` | source module (ruby 3.3) | PASS |
| 29 | Perl | `vsn.pl` | source module (perl 5.40) | PASS |
| 30 | Crystal | `vsn.cr`, `shard.yml` | source shard (crystal) | PASS |
| 31 | Dart | `vsn.dart`, `pubspec.yaml` | source module (dart 3) | PASS |

Each `Compiled/<Lang>/README.md` documents files-to-copy, how to consume, dependencies, a minimal
public-API example, and the exact verify command.

## Notes
- Native-compiled languages ship static (`.a`/`.o`/`.rlib`/`.beam`/`.cma`) and, where conventional, shared
  (`.so`) artifacts plus public headers/declarations. Languages that distribute as modules ship their
  validated source package + manifest (Go/Rust/Python/JS-TS/Julia/R/Lua/PHP/Ruby/Perl/Crystal/Dart/Dart).
- Storage Policy wire-out (`REC_STORAGE_POLICY 0x0009` + `FID 0x0901`, 1-byte value 1-4) and wire-in
  round-trip verified through each language's public API in its consumer.
- Frozen vectors DIRECT-01/02/03, EXT-01, EXT-02-and-EXT-03: 5/5 SHA-256 MATCH (unchanged).
- Rebuild workflow: see `AGENTS.md` → "Compiled Artifact Freshness and Rebuild Policy".
