# VSN-1 ALL-31 Public API Matrix — 2026-10-10

Public entry points per language (from packaging/manifest analysis) and the four Storage Policy API
capabilities verified by conformance: **policy type**, **create-with-policy**, **wire-out (0x0009)**, **wire-in (0x0901)**.

| # | Language | Public entry | Policy type | create(policy) | wire-out | wire-in |
|---|----------|-------------|-------------|----------------|----------|---------|
| 01 | Ada | `Vsn` (GNAT pkg) | enum | Create_With_Policy | Encode_With_Policy | Get_Storage_Policy |
| 02 | C | `vsn.h` C API | STORAGE_* consts | vsn_create_with_policy | commit+REC | vsn_open |
| 03 | COBOL | `VSN-LIBRARY` | PIC consts | CREATE-WITH-POLICY | OP-EXPORT-BYTES | CREATE-WITH-POLICY |
| 04 | CSharp | `VsnStore` | enum | VsnStore.Create | commit | parse |
| 05 | Cpp | `vsn.hpp` | STORAGE_* | create(policy) | commit | parse |
| 06 | Crystal | `Vsn` module | module const | Store.create | export_bytes | parse_sp |
| 07 | D | `Vsn` module | enum | withPolicy | encodeWithPolicy | importBytes |
| 08 | Dart | `Vsn` class | const | create(policy) | encode | parse |
| 09 | Elixir | `Vsn` module | @constant | with_policy | encode/3 | parse |
| 10 | Erlang | `Vsn` module | macro | new/2 | encode/3 | parse/1 |
| 11 | FSharp | `Vsn` module | DU | createWithPolicy | commit | parse |
| 12 | Fortran | `Vsn` module | param const | create_with_policy | encode | parse |
| 13 | Go | `vsn` pkg | type | Create(policy) | toBytes | Open |
| 14 | Haskell | `Vsn` module | ADT | createWithPolicy | encode | parse |
| 15 | Java | `VsnLib` | enum | createWithPolicy | encode | parseStoragePolicy |
| 16 | JavaScript-TypeScript | `vsn-typescript` | enum | create(policy) | commit | parse |
| 17 | Julia | `Vsn` module | module const | create(policy) | encode | parse |
| 18 | Kotlin | `VsnApi`/`Vsn` | enum | create(policy) | commit | parse |
| 19 | Lua | `Vsn` table | const | new(policy) | encode | parse |
| 20 | Nim | `Vsn` module | const | withPolicy | encodeWithSP | importBytes |
| 21 | Objective-C | `VSN.h` C API | NS_ENUM | withPolicy | vsn_encode_with_policy | vsn_parse_storage_policy |
| 22 | OCaml | `Vsn` module | const | create(policy) | encode | decode |
| 23 | Perl | `Vsn` pkg | const | new(policy) | encode | parse |
| 24 | PHP | `Vsn` class | const | create(policy) | encode | parse |
| 25 | Python | `vsn` pkg | StoragePolicy | create(policy) | commit | parse |
| 26 | R | `vsn` functions | const | create_with_policy | commit | import_bytes |
| 27 | Ruby | `Vsn` module | const | new(policy) | encode | export_bytes |
| 28 | Rust | `vsn_rust` crate | enum | with_policy | encode | parse |
| 29 | Scala | `Vsn` object | const | create(policy) | encodeWithSP | parseSP |
| 30 | Swift | `Vsn` package | enum | create(policy) | encode | parseStoragePolicy |
| 31 | Zig | `Vsn` pkg | const | createWithPolicy | encode | parse |

All 31 expose a policy type (values 1-4), a create-with-policy constructor, and writer/reader
round-trip of the `0x0009`/`0x0901` record — confirmed by the 31/31 conformance run.
