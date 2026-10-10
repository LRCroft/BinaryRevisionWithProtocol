# VSN-1 ALL-31 Independent Consumer Test Results — 2026-10-10

Independent consumers exercise ONLY the public API (no internal fields/private modules).
All 31 languages have an executed independent consumer (real Docker execution, exit 0).

| # | Language | Consumer path | Tool | Exit | Checks | Result |
|---|----------|---------------|------|------|--------|--------|
| 01 | Ada | `Consumer/Ada` | gnatmake (Docker) | 0 | 4 | PASS |
| 02 | C | `Consumer/C` | gcc (Docker) | 0 | 10 | PASS |
| 03 | COBOL | `Consumer/COBOL` | cobc (Docker) | 0 | 4 | PASS |
| 04 | CSharp | `Consumer/CSharp` | dotnet | 0 | 8 | PASS (re-verified this session) |
| 05 | Cpp | `Consumer/Cpp` | g++ (Docker) | 0 | 4 | PASS |
| 06 | Crystal | `Consumer/Crystal` | crystal (Docker) | 0 | 4 | PASS |
| 07 | D | `Consumer/D` | gdc (Docker) | 0 | 4 | PASS |
| 08 | Dart | `Consumer/Dart` | dart (Docker) | 0 | 4 | PASS |
| 09 | Elixir | `Consumer/Elixir` | elixir (Docker) | 0 | 4 | PASS |
| 10 | Erlang | `Consumer/Erlang` | erlc+erl (Docker) | 0 | 4 | PASS |
| 11 | FSharp | `Consumer/FSharp` | dotnet (Docker) | 0 | 8 | PASS |
| 12 | Fortran | `Consumer/Fortran` | gfortran (Docker) | 0 | 4 | PASS |
| 13 | Go | `Consumer/Go` | go (Docker) | 0 | 9 | PASS |
| 14 | Haskell | `Consumer/Haskell` | ghc (Docker) | 0 | 4 | PASS |
| 15 | Java | `Consumer/Java` | javac (Docker) | 0 | 10 | PASS |
| 16 | JavaScript-TypeScript | `Consumer/JavaScript-TypeScript` | node | 0 | CJS 18 + ESM 5 | PASS (re-verified this session) |
| 17 | Julia | `Consumer/Julia` | julia (Docker) | 0 | 4 | PASS |
| 18 | Kotlin | `Consumer/Kotlin` | kotlinc (Docker) | 0 | 9 | PASS |
| 19 | Lua | `Consumer/Lua` | lua (Docker) | 0 | 5 | PASS |
| 20 | Nim | `Consumer/Nim` | nim (Docker) | 0 | 4 | PASS |
| 21 | Objective-C | `Consumer/Objective-C` | gcc (Docker) | 0 | 4 | PASS |
| 22 | OCaml | `Consumer/OCaml` | ocamlc (Docker) | 0 | 4 | PASS |
| 23 | Perl | `Consumer/Perl` | perl (Docker) | 0 | 4 | PASS |
| 24 | PHP | `Consumer/PHP` | php (Docker) | 0 | 5 | PASS |
| 25 | Python | `Consumer/Python` | python | 0 | 9 | PASS (re-verified this session) |
| 26 | R | `Consumer/R` | Rscript (Docker) | 0 | 4 | PASS |
| 27 | Ruby | `Consumer/Ruby` | ruby (Docker) | 0 | 5 | PASS |
| 28 | Rust | `Consumer/Rust` | cargo (Docker) | 0 | 9 | PASS |
| 29 | Scala | `Consumer/Scala` | scala-cli (Docker) | 0 | 4 | PASS |
| 30 | Swift | `Consumer/Swift` | swiftc (Docker) | 0 | 5 | PASS |
| 31 | Zig | `Consumer/Zig` | zig (Docker) | 0 | 5 | PASS |

**Totals:** 31/31 independent consumers PASS (exit 0).
