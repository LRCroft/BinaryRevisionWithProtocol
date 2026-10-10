# VSN ALL-31 Storage Policy Audit — 2026-10-10

Canonical: SP values 1-4 are authoritative on the wire via `REC_STORAGE_POLICY` (0x0009) + `FID_STORAGE_POLICY` (0x0901), payload = single u8 in {1,2,3,4}.
Obsolete: `HV→MODERN` / `H→ENTERPRISE` (SP→wire-mode inference) is CANCELLED in all 31 libraries.
Result: 31/31 SP conformance PASS; frozen vectors 5/5 SHA-256 MATCH; conformance 31/31 VERIFIED (exit 0).

| # | Language | SP 1-4 | Writer 0x0009 | Reader 0x0901 | Obsolete SP→mode | P01-P12 |
|---|----------|--------|---------------|---------------|------------------|---------|
| 01 | Ada | PASS | Encode_With_Policy | Get_Storage_Policy | removed (dead code cleaned) | PASS |
| 02 | C | PASS | vsn_create_with_policy | vsn_open/parse_sp | removed (P02 fixed) | PASS |
| 03 | COBOL | PASS | OP-EXPORT-BYTES | CREATE-WITH-POLICY | removed | PASS |
| 04 | CSharp | PASS | VsnStore.Create(policy) | parse | removed | PASS |
| 05 | Cpp | PASS | encode (sp) | parse | removed | PASS |
| 06 | Crystal | PASS | export_bytes | parse_sp | removed | PASS |
| 07 | D | PASS | encodeWithPolicy | importBytes | removed | PASS |
| 08 | Dart | PASS | encode(storagePolicy:) | parse | removed | PASS |
| 09 | Elixir | PASS | VSN.encode/3 | parse+read_sp | removed | PASS |
| 10 | Erlang | PASS | encode/3 | parse/1 | removed | PASS |
| 11 | FSharp | PASS | store.storagePolicy | parse | removed | PASS |
| 12 | Fortran | PASS | encode(sp) | parse | removed | PASS |
| 13 | Go | PASS | toBytesLocked | Open/GetStoragePolicy | removed | PASS |
| 14 | Haskell | PASS | encode sp | parse sp | removed | PASS |
| 15 | Java | PASS | encode(sp) | parseStoragePolicy | removed | PASS |
| 16 | JavaScript-TypeScript | PASS | commit(sp) | parse sp | removed | PASS |
| 17 | Julia | PASS | encode(sp) | parse | removed | PASS |
| 18 | Kotlin | PASS | commit(sp) | parse | removed | PASS |
| 19 | Lua | PASS | encode(sp) | parse | removed | PASS |
| 20 | Nim | PASS | encodeWithSP | importBytes | removed | PASS |
| 21 | Objective-C | PASS | vsn_encode_with_policy | vsn_parse_storage_policy | removed | PASS |
| 22 | OCaml | PASS | encode(sp) | decode | removed | PASS |
| 23 | Perl | PASS | encode(sp) | parse | removed | PASS |
| 24 | PHP | PASS | encode(sp) | parse | removed | PASS |
| 25 | Python | PASS | store._storage_policy | parse SP | removed | PASS |
| 26 | R | PASS | commit() | import_bytes | removed | PASS |
| 27 | Ruby | PASS | VSN.encode(sp) | export_bytes | removed | PASS |
| 28 | Rust | PASS | encode(sp) | parse | removed | PASS |
| 29 | Scala | PASS | encodeWithSP | parseSP | removed | PASS |
| 30 | Swift | PASS | encode(sp) | parseStoragePolicy | removed | PASS |
| 31 | Zig | PASS | encode(sp) | parse | removed | PASS |

## Session fixes (2026-10-10)
- C `test_vsn.c` P02: obsolete HV→MODERN/H→ENTERPRISE assertion → loop SP 1-4 + `parse_sp_value` round-trip.
- Ada `test_vsn.adb`: removed dead `m1-m4` HV→MODERN / H→ENTERPRISE mapping vars; kept SP 1-4 value assertion.
- C `vsn.c`: removed semantic mode labels from comments; `MODE_MODERN`/`MODE_ENTERPRISE` retained only as binary wire constants.
- Verified 5/5 frozen vectors SHA-256 vs `corpus/manifest.json` (see ALL_31_LANGUAGE_CONFORMANCE_MANIFEST.json).

