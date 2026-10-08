# HARD IMPLEMENTATION AUDIT — Storage Policy Wire Contract (2026-10-08)

**Verdict:** **NOT READY.** Only 4/31 languages have BOTH writer AND reader implementing REC_STORAGE_POLICY on wire. Many "migrated" claims are based solely on constant declarations, not actual binary serialization/parsing behavior.

---

## SECTION 1: WRITER AUDIT — Does the canonical writer emit `REC_STORAGE_POLICY` (0x0009)?

**Criteria:** Canonical write/commit MUST produce record type=0x0009 + field_id=0x0901 + u8 value in {1,2,3,4}. Stub encode() returning only VSN- header = NOT implementation. Emitting REC_MODE_DECLARATION (0x0007) instead = FAIL.

| # | Lang | Emits 0x0009? | Reader Parses? | u8=1..4? | Avoids 0x0007? | Status |
|---|------|--------------|---------------|---------|---------------|--------|
| 01 | Python | YES (store.py:491) | YES (container.py:92-95) | YES | YES | FULL |
| 02 | C | YES (vsn.c:215) | YES (vsn.c:83-84) | YES | YES | FULL |
| 03 | Go | YES (store.go:262) | NO | YES | YES | PARTIAL |
| 04 | TypeScript | YES (store.ts:447) | PARTIAL | YES | YES | PARTIAL |
| 05 | C# | YES (Store.cs:506) | NO | YES | YES | PARTIAL |
| 06 | Rust | YES (lib.rs:66) | NO | YES | YES | PARTIAL |
| 07 | F# | NO | PARTIAL | N/A | NO | FAIL |
| 08 | Lua | NO | PARTIAL | N/A | NO | FAIL |
| 09-28 | Java,Kotlin,Ruby,Elixir,Erlang,Dart,PHP,Ada,Fortran,COBOL,Zig,Julia,Haskell,Nim,OCaml,Scala,R,ObjC | NO | NO | N/A | N/A | STUB |
| 29 | Swift | NO (bug) | NO | N/A | PARTIAL(bug) | FAIL |

### Summary: FULL=2, PARTIAL=4, FAIL=3, STUB=23


---

## SECTION 2: DETAILED EVIDENCE PER LANGUAGE

### FULL IMPLEMENTATION (writer + reader)
**Python**: `VsnStore.to_bytes()` → emits `REC_STORAGE_POLICY` with `FID_STORAGE_POLICY` + u8 value. Parser extracts via `cont.storage_policy = sp.value[0]`.
**C**: `vsn_commit()` line 215: `enc_record(buf, REC_STORAGE_POLICY, pl_with_FID_STORAGE_POLICY, pl_value)`. `vsn_parse()` line 83-84: `c->storage_policy = val[0]`.

### PARTIAL (writer OK, reader broken/incomplete)
**Go**: `Store.toBytesLocked()` emits correct record. But parser (`reopen`) only handles RecFileIdentity/RecRevision/RecFileHead/RecCommitMarker — never extracts storage_policy.
**TypeScript**: `toBytes()` emits REC_STORAGE_POLICY correctly. Parser reads records to fields but Container type has no `storagePolicy` field. Parsed values not exposed.
**C#**: `VsnStore.ToBytes()` emits correct record. `ContainerParser.Parse()` only handles REC_MODE_DECLARATION, ignores REC_STORAGE_POLICY entirely.
**Rust**: `encode()` emits correct bytes. Parser (`parse()`) only reads mode byte at position 6 + generation. No record-level parsing.

### FAIL (wrong architecture — emits 0x0007)
**F# Vsn.fs line 332**: Emits `w.Record(RT.MODE, ...)` = REC_MODE_DECLARATION (0x0007). Container has StoragePolicy field but encoder IGNORES IT.
**Lua vsn.lua lines 816-819**: Emits REC_MODE_DECLARATION + FID_MODE as FIRST record. No storage_policy field in MutableStore constructor.
**Swift Vsn.swift lines 20-26**: Treats `mode` as policy value — writes mode>>8 and mode&0xFF (wrong for UInt8). Uses mode=MODERN(1) not storage_policy field.

### STUB (no actual wire implementation — 23 languages)
encode(mode, gen) returns only `[VSN-,0x00,0x01,0x00,0x01]`. No record-level serialization. MutableStore lacks storage_policy field or commit path calls stub encode().


---

## SECTION 3: REQUIRED FIXES

### CRITICAL (wrong record on wire):
1. **F# Vsn.fs line 332**: Replace RT.MODE emission with RT.STORAGE_POLICY using container's StoragePolicy field.
2. **Lua vsn.lua lines 816-819**: Replace REC_MODE_DECLARATION with REC_STORAGE_POLICY in to_bytes(). Add storage_policy to MutableStore.
3. **Swift Vsn.swift lines 20-26**: Rewrite to use actual storage_policy value, not mode.

### PARTIAL (reader needs extraction):
4. Go store.go reopen(): Extract REC_STORAGE_POLICY from parsed Container.
5. TypeScript container.ts: Add storagePolicy field, extract in parse().
6. C# ContainerParser.cs: Extract REC_STORAGE_POLICY alongside REC_MODE_DECLARATION.
7. Rust lib.rs parse(): Parse record-level data including REC_STORAGE_POLICY.

### STUB → FULL (23 languages):
All need: storage_policy field + full record-level commit path emitting REC_STORAGE_POLICY.