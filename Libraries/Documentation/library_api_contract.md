# VSN Language-Neutral API and Conformance Contract

**Status:** Draft  
**Applies to:** All VSN library implementations  
**Scope:** Library-level API semantics (not normative protocol rules)

---

## Purpose

This document defines the **language-neutral API contract** for VSN library implementations. It describes the expected behavior, capabilities, and conformance levels for libraries that implement the frozen VSN canonical binary container format.

This document does **not** define normative VSN protocol rules. Protocol rules are frozen in `Specification/VSN_Specification.md` and related documents. This contract defines **library-level semantics** that implementations must provide to be considered "Library-Complete."

---

## Conformance Levels

Implementations progress through the following conformance levels:

### 1. Planned
- Implementation has not started.
- No code exists.

### 2. In Development
- Implementation is in progress.
- May not pass frozen-vector tests.

### 3. Protocol-Conformant
- Passes all frozen-vector protocol conformance tests.
- Correctly parses, validates, and materializes VSN containers.
- Implements core protocol semantics (DIRECT-1, EXTENTS-1, CommitMarker, etc.).
- Does **not** provide full library API surface.

### 4. Conformance Partial
- Passes frozen-vector tests.
- Implements **some** library capabilities but not all.
- May be missing transactions, diff, merge, diagnostics, or storage management.

### 5. Library-Complete
- Passes all frozen-vector protocol conformance tests.
- Implements **full** library API surface as defined in this contract.
- All library workflow tests pass.
- Provides production-ready library capabilities.

---

## Core Protocol Capabilities (Protocol-Conformant)

All implementations must provide these capabilities to be Protocol-Conformant:

### Parser
- **Function:** `parse(data: bytes) -> Container`
- **Behavior:** Parse a VSN binary container into structured representation.
- **Requirements:**
  - Validate magic, versions, framing.
  - Extract records, fields, objects.
  - Reject malformed containers with appropriate errors.
  - Handle truncated data gracefully.

### Writer
- **Function:** `encode(container: Container) -> bytes`
- **Behavior:** Serialize a Container into canonical VSN binary format.
- **Requirements:**
  - Emit canonical field ordering.
  - Exclude ModeDeclaration from trailer record count (GR-13).
  - Support DIRECT-1 and EXTENTS-1 representations.
  - Produce deterministic output for identical input.

### Validation
- **Function:** `validate(data: bytes, level: string) -> void`
- **Levels:** `"Structural"`, `"Semantic"`, `"Recovery"`, `"Content"`, `"Full"`
- **Behavior:** Validate container at requested depth.
- **Requirements:**
  - Structural: magic, versions, framing, lengths, ordering.
  - Semantic: identity, references, graph, presence, mode.
  - Recovery: marker-based recovery (RC-01..RC-45).
  - Content: representation materialization.
  - Full: all levels.

### Recovery
- **Function:** `recover(data: bytes) -> RecoveryResult`
- **Behavior:** Recover accepted state from potentially corrupted data.
- **Requirements:**
  - Marker-based recovery only (no indexes, caches, or heuristics).
  - Accepted state = data preceding highest-Generation valid CommitMarker.
  - Return status: `"RECOVERED"`, `"PARTIAL"`, `"FAILED"`.


### Representations
- **Function:** `materialize(object_descriptor: bytes) -> bytes`
- **Behavior:** Materialize logical content from object descriptor.
- **Requirements:**
  - Support DIRECT-1 (literal content).
  - Support EXTENTS-1 (copy-plus-literal reconstruction).
  - Detect and reject dependency cycles.
  - ENTERPRISE mode must reject EXTENTS-1 (GR-43).

### Modes
- **MODERN (0x01):** Supports DIRECT-1 and EXTENTS-1.
- **ENTERPRISE (0x02):** Supports DIRECT-1 only; EXTENTS-1 forbidden.

### Objects
- **ContentObject:** Stores object descriptor and serial.
- **ObjectSerial:** Unique identifier for content objects.
- **Materialization:** Reconstruct logical content from descriptor.

---

## Library Capabilities (Library-Complete)


### Revision API
- **Functions:**
  - `list_revisions(file_id: FileId) -> list[RevisionId]`: List revisions.
  - `get_current_revision(file_id: FileId) -> RevisionId`: Get head revision.
  - `checkout_revision(file_id: FileId, revision_id: RevisionId) -> bytes`: Read old revision.
  - `restore_revision(file_id: FileId, revision_id: RevisionId) -> void`: Restore old revision as new head.
- **Requirements:**
  - RevisionId is monotonically increasing integer.
  - Preserve full revision history.
  - Support checkout and restore operations.

### History Retention — `LimitCleanUp`

> **This is a LIBRARY capability. It is NOT a VSN protocol rule.** It manages
> canonical history at the Library level. It introduces no VSN record, field,
> error identifier, or semantic, and it does not alter the container grammar.

- **Operation:** `limit_cleanup(file_id: FileId, limit: int) -> list[RevisionId]`
- **Argument:** `limit` — the maximum number of revisions to retain.
- **Return value:** the `RevisionId`s that were actually removed, in **ascending
  canonical revision order**. The returned ids correspond exactly to the
  revisions removed from canonical state, the result is deterministic, and the
  list is empty when nothing was removed. The shape is `list[int]` (Python),
  `List<ulong>` (C#), `number[]` (TypeScript).
- **Scope: one file's history.** This is chosen because the VSN revision model
  is per-file: every `Revision` names exactly one `FileId`, and each file has its
  own `FileHead`. A container-wide variant would be ambiguous whenever files
  have histories of different lengths, so it is not defined. Callers wanting a
  container-wide bound invoke the operation once per `FileId`.
- **Return:** the removed `RevisionId` values in **ascending order**. An empty
  list means nothing was removed.

#### Retention ordering

- Canonical revision ordering is **ascending `RevisionId`**.
- The **newest `limit`** revisions are retained; **every older revision is
  removed**.
- Example — revisions R1…R10, `LimitCleanUp(5)` → R1–R5 removed, R6–R10 retained.

#### Invalid arguments

- **`limit < 1` MUST be rejected**, including `limit == 0`, using the existing
  frozen error identifier `0x000C` (`INVALID_CANONICAL_STATE`). `limit == 0` is
  deliberately **not** defined as "delete everything": a value that slipped from
  `5` to `0` would otherwise become an immediately destructive operation, and
  "delete all" is not a useful reading of "retain N revisions". Rejecting it also
  matches the operation's name, which describes retention.
- An unknown `FileId` MUST be rejected with the existing `0x0009`
  (`MISSING_CANONICAL_REFERENCE`).
- A rejected call MUST NOT modify any state.

#### Guarantees

- The operation is **deterministic**: the same state and `limit` always yield the
  same removed set.
- **Retained revisions are never modified.** Their `RevisionId`, contents, and
  `ObjectSerial` are untouched and are re-emitted byte-identically on the next
  commit. History is not renumbered and no revision is rewritten.
- **The head revision is never removed.** Because the head is the newest revision
  it always falls inside the retained set while `limit >= 1`, so a `FileHead`
  record can never be left dangling. Implementations MUST refuse rather than emit
  a dangling `FileHead`.
- If the file already has `<= limit` revisions, **nothing is removed** and no
  state is touched (no generation bump, no re-encode).
- **Idempotent:** repeating the same call removes nothing further.
- A **smaller** limit followed by a **larger** one never recreates deleted
  history — deleted revisions are gone from canonical state, not merely hidden.
- **Objects are never removed.** The object section is a shared content store: a
  retained revision in another file, or an `EXTENTS-1` `COPY` operand, may still
  reference those objects. Reclaiming objects is a separate operation and is not
  part of history retention.
- **Real removal, not concealment.** Revisions are removed from the Library's
  stored canonical state, so they are genuinely unavailable after reopening. They
  are never merely hidden from an index.

#### Atomicity and failure

- The operation is **atomic from the Library user's perspective**: it either
  applies in full or leaves history exactly as it was. Implementations MUST
  validate first and MUST roll back on any failure, so a failed cleanup never
  leaves partially pruned history visible as a success.
- Failures are reported through the existing Library diagnostics/error
  mechanism. The operation MUST NOT report success when it did not clean.

#### Interaction with recovery and derived storage

- **Canonical VSN state remains authoritative.** Recovery after cleanup MUST work
  from canonical state alone.
- Cleanup MUST NOT require an index, cache, or checkpoint to determine
  correctness, and recovery MUST NOT depend on derived artifacts that cleanup
  removed.
- **Derived indexes/caches MUST be invalidated or updated consistently** after
  deletion, e.g. by dropping the content cache for affected objects.
- `CommitMarker` remains the sole acceptance authority. Cleanup does not change
  how acceptance is determined, and it MUST NOT be used to accept a generation.

#### Persistence

- The operation mutates Library state in the manner of the other Library
  mutators (for example `write_file`); it is persisted by the normal
  `commit()`. After cleanup the container MUST open, recover, and list revisions
  normally.

#### Revision ordering (normative)

- Canonical revision order is **ascending `RevisionId`**, filtered to the
  revisions belonging to the requested `FileId`.
- The `Revision` record carries no parent or sequence field (0x0201 `RevisionId`,
  0x0202 `FileId`, 0x0203 `ContentRef`, 0x0210 `PathSnapshot`, 0x0211
  `Presence`), so `RevisionId` is the only ordering signal available. RC-24
  makes allocated identifiers permanently non-recyclable, which makes ascending
  `RevisionId` a well-defined creation order.
- Consequently an implementation MUST filter by `FileId` **before** ordering.
  Global revision numbering MUST NOT be used: with interleaved files, File A
  owning ids 1,3,5,7,9 and File B owning 2,4,6,8,10, `LimitCleanUp(A, 3)` must
  retain 5,7,9 and leave all of B untouched.

#### Revision API behaviour after cleanup

- Deleted revisions MUST be genuinely unavailable, not merely hidden from
  `list_revisions`. `get_revision`, `checkout_revision` and `restore_revision`
  MUST report absence with the existing `0x0009`.
- `get_object_serial(file_id, revision_id)` is the one API that reports absence
  by **returning the null/None value** rather than raising, exactly as it does
  for a revision that never existed. It MUST NOT return the stale `ObjectSerial`
  of a deleted revision.
- Retained revisions MUST continue to work through every revision and object
  API: list, get, checkout, restore, diff, `FileHead` lookup, existence checks,
  object lookup, and materialization.

#### FileHead behaviour

- `FileHead` MUST point at the newest retained revision, and MUST NOT reference
  a deleted revision.
- The head is the newest revision, so for any `limit >= 1` it always falls inside
  the retained set. An implementation MUST still verify this and refuse rather
  than emit a dangling `FileHead`.
- When only one revision is retained, `FileHead` MUST reference it and that
  revision MUST remain readable. When nothing is removed, `FileHead` MUST be
  unchanged.

#### Transaction interaction

- `LimitCleanUp` is an **immediate store mutation**, like `create_file` and
  `write_file`; it is **not** staged by a `Transaction`.
- `Transaction.rollback()` therefore discards only staged changes and does **not**
  undo a prior `LimitCleanUp`. This is intentional and preserves the existing
  transaction model rather than inventing a new one.
- Callers requiring an all-or-nothing group should run `LimitCleanUp` after the
  commit that produced the history being pruned.
- `ExpectedRevisionId` remains a precondition only and MUST NOT become persisted
  metadata as a result of this capability. Stale preconditions must continue to
  fail after cleanup.

#### CommitMarker rule

- `CommitMarker` remains the **sole acceptance authority**.
- `LimitCleanUp` MUST NOT invent an acceptance record, change `CommitMarker`
  semantics, bypass generation rules, make derived storage canonical, or make a
  deleted revision appear accepted.
- An in-memory cleanup does not itself advance the accepted `Generation`; the
  subsequent `commit()` does.

#### Concurrency

- The store architecture in all three reference implementations is
  **single-writer**: no locking primitive exists in any of them.
- `LimitCleanUp` follows the existing mutation/transaction rules and does not
  introduce a concurrency model. Concurrent mutation of one store is not
  supported by the surrounding architecture, and no thread-safety is claimed.

#### Distinction from object garbage collection

- `LimitCleanUp` **removes old revision history**. It does **not** reclaim
  objects. Therefore:

  ```
  revision deletion  !=  object garbage collection
  ```

- After cleanup, an object that was referenced only by a deleted revision
  remains present and materializable. This is deliberate: the object section is a
  shared content store that a retained revision in another file, or an
  `EXTENTS-1` `COPY` operand, may still reference.
- Any object reclamation is a **separate** operation. Where a storage manager
  already offers cache/object maintenance, that existing capability is used;
  `LimitCleanUp` does not redesign it.
- Canonical correctness MUST NEVER depend on derived object or cache deletion.

#### Examples

| Revisions | `limit` | Removed | Retained |
|---|---|---|---|
| 1 | 5 | — | R1 |
| 3 | 5 | — | R1, R2, R3 |
| 5 | 5 | — | R1…R5 |
| 6 | 5 | R1 | R2…R6 |
| 10 | 5 | R1–R5 | R6…R10 |
| 4 | 1 | R1–R3 | R4 |
| any | 0 | *rejected, `0x000C`* | unchanged |

#### Required per-language API shape

Every one of the 31 language targets MUST provide this operation, expressed
idiomatically but with identical semantics. Suggested shapes:

| Language | Shape |
|---|---|
| Python | `VsnStore.limit_cleanup(file_id: bytes, limit: int) -> list[int]` |
| C# | `List<ulong> VsnStore.LimitCleanUp(byte[] fileId, ulong limit)` |
| TypeScript | `number[] VsnStore.limitCleanup(fileId: Buffer, limit: number)` |
| Rust | `fn limit_cleanup(&mut self, file_id: &FileId, limit: u64) -> Result<Vec<RevisionId>>` |
| Go | `func (s *Store) LimitCleanUp(fileId []byte, limit uint64) ([]uint64, error)` |
| Java / Kotlin / Scala | `List<Long> limitCleanUp(byte[] fileId, long limit) throws VsnException` |
| Others | the local idiom (error type, option/result/either as appropriate) |

**Signedness asymmetry (intentional, documented).** Python's `int` and
TypeScript's `number` are signed, so a negative `limit` is representable and MUST
be rejected the same way `0` is. The C# parameter is `ulong`, so a negative
value is **not representable**; a caller who casts a negative literal produces a
very large `limit`, which is a no-op (nothing is removed) rather than a silent
deletion. `0` is the reject case in C#. This is a consequence of the specified
C# signature, not an oversight.

A language MUST NOT report this capability as implemented until it has executed
the behavioural checks below. In particular, **merely declaring a function with
this name is not evidence**; conformance is established by running the
operation and checking the resulting revision history. The shared runner
(`Conformance/run_conformance.py`) enforces this with an executable probe per
language that builds a real 10-revision history, runs the operation, and
verifies removed/retained RevisionIds, retained ObjectSerials, real removal
after reopen, recovery, and `limit == 0` rejection. A failing probe caps the
language at `Conformance Partial`.

**Minimum behavioural checks every target must satisfy:**

1. 1 / 3 / 5 revisions with `limit 5` → nothing removed
2. 6 revisions with `limit 5` → R1 removed, R2…R6 retained
3. 10 revisions with `limit 5` → R1–R5 removed, R6…R10 retained
4. `limit 1` → only the head retained
5. `limit 0` and negative → rejected (`0x000C`), history unchanged
6. exact retained RevisionIds match
7. deleted revisions are genuinely unavailable after commit + reopen
8. retained contents are byte-identical
9. retained ObjectSerial values are unchanged
10. reopening after cleanup lists exactly the retained set
11. recovery after cleanup succeeds from canonical state alone
12. derived indexes/caches are consistent afterwards
13. a failed cleanup reports failure and does not report false success
14. repeated `LimitCleanUp(5)` is idempotent
15. `LimitCleanUp(3)` then `LimitCleanUp(5)` does not recreate deleted history
16. `LimitCleanUp(5)`, then a new commit, then `LimitCleanUp(5)`
17. interaction with the existing transaction model is well-defined
18. no frozen VSN vector changes, and no new record/field/identifier appears

For the 25 targets that are not yet verified, this section is the
**requirement**. It is not a claim of implementation: those languages remain
`In Development / Unverified` until executable evidence exists.

### Object API
- **Functions:**
  - `list_objects() -> list[ObjectSerial]`: List all objects.
  - `get_object_info(serial: ObjectSerial) -> ObjectInfo`: Get metadata.
  - `materialize_object(serial: ObjectSerial) -> bytes`: Materialize content.
- **Requirements:**
  - ObjectSerial is unique integer.
  - Support DIRECT-1 and EXTENTS-1 (mode-dependent).

### Transactions
- **Class:** `Transaction`
- **Functions:**
  - `stage_create(path: string, content: bytes) -> void`
  - `stage_update(file_id: FileId, content: bytes) -> void`
  - `stage_delete(file_id: FileId) -> void`
  - `stage_rename(file_id: FileId, new_path: string) -> void`
  - `inspect() -> list[StagedChange]`: Inspect staged changes.
  - `rollback() -> void`: Discard staged changes.
  - `commit(store: VsnStore) -> bytes`: Apply and commit.
- **Requirements:**
  - CommitMarker is sole acceptance authority (RC-01).
  - ExpectedRevisionId is precondition only, NEVER persisted.
  - Enforce ExpectedRevisionId precondition on commit.
  - Fail transaction on mismatch.

### Diagnostics
- **Function:** `validate_with_diagnostics(data: bytes, level: string) -> list[Diagnostic]`
- **Diagnostic fields:**
  - `code: int`: Error code.
  - `message: string`: Human-readable message.
  - `severity: Severity`: ERROR, WARNING, INFO.
  - `category: Category`: PROTOCOL, SEMANTIC, RECOVERY.
  - `byte_offset: int | null`: Location in data.

### Diff
- **Functions:**
  - `diff_files(store1: VsnStore, store2: VsnStore) -> FileDiff`: Compare file sets.
  - `diff_revisions(store: VsnStore, file_id: FileId, rev1: RevisionId, rev2: RevisionId) -> ObjectDiff`: Compare revisions.
  - `diff_objects(store1: VsnStore, store2: VsnStore) -> ObjectDiff`: Compare object sets.
- **FileDiff fields:**
  - `added: list[string]`: Paths added in store2.
  - `removed: list[string]`: Paths removed in store2.
  - `modified: list[string]`: Paths modified in store2.
  - `unchanged: list[string]`: Paths unchanged.
- **Requirements:**
  - Compare by path and content.
  - Support binary content comparison.

### Merge
- **Function:** `three_way_merge(base: VsnStore, ours: VsnStore, theirs: VsnStore) -> MergeResult`
- **MergeResult fields:**
  - `merged_files: dict[string, bytes]`: Merged file contents.
  - `conflicts: list[Conflict]`: Detected conflicts.
  - `has_conflicts: bool`: Whether conflicts exist.
- **Conflict fields:**
  - `path: string`: Conflicting file path.
  - `base_content: bytes`: Base version.
  - `ours_content: bytes`: Our version.
  - `theirs_content: bytes`: Their version.
- **Function:** `resolve_conflict(result: MergeResult, path: string, content: bytes) -> void`
- **Requirements:**
  - Detect conflicts when both sides modify same file differently.
  - Allow manual conflict resolution.
  - Preserve non-conflicting changes.

### Import/Export
- **Functions:**
  - `import_bytes(store: VsnStore, path: string, content: bytes) -> FileId`: Import from bytes.
  - `export_bytes(store: VsnStore, file_id: FileId) -> bytes`: Export to bytes.
  - `import_stream(store: VsnStore, path: string, stream: InputStream) -> FileId`: Import from stream.
  - `export_stream(store: VsnStore, file_id: FileId, stream: OutputStream) -> int`: Export to stream.
  - `import_multiple(store: VsnStore, files: dict[string, bytes]) -> dict[string, FileId]`: Batch import.
  - `export_multiple(store: VsnStore, file_ids: list[FileId]) -> dict[FileId, bytes]`: Batch export.
- **Requirements:**
  - Support arbitrary binary content.
  - Preserve content exactly (including empty, NULs).
  - Stream APIs support large files.

### Streaming

### Integrity Verification
- **Function:** Library-level integrity check API.
- **Requirements:**
  - Verify container structural integrity.
  - Verify semantic integrity (references, identities).
  - Verify content integrity (materialization).
  - Return diagnostics or raise errors.

### Storage Management (Derived Data)
- **Class:** `StorageManager`
- **Functions:**
  - `build_indexes(store: VsnStore) -> void`: Build derived indexes.
  - `invalidate() -> void`: Invalidate derived data.
  - `gc() -> void`: Garbage collect unused data.
  - `stats() -> StorageStats`: Get storage statistics.
  - `is_valid: bool`: Whether derived data is valid.
- **Requirements:**
  - Derived data (indexes, caches) is NEVER canonical authority.
  - Recovery must work without derived storage.
  - Derived data can be rebuilt from canonical state.

---

## Top-Level Convenience API

Implementations should provide top-level convenience functions:

- `create(mode: int) -> VsnStore`: Create new container.
- `open(data: bytes) -> VsnContainer`: Open existing container.
- `validate_container(data: bytes, level: string) -> list[Diagnostic]`: Validate with diagnostics.
- `recover_container(data: bytes) -> RecoveryResult`: Recover container.
- `import_file(store: VsnStore, path: string, content: bytes) -> FileId`: Import file.
- `export_file(store: VsnStore, file_id: FileId) -> bytes`: Export file.
- `transaction(expected_revision_id: int) -> Transaction`: Create transaction.
- `inspect_container(store: VsnStore) -> dict`: Inspect container metadata.

---


---

## Test Matrix

Library-Complete implementations must pass tests covering:

- create/open/close
- create/update/delete/rename file
- revision creation/listing/checkout/restore
- transaction commit/rollback
- ExpectedRevisionId success and failure
- ENTERPRISE DIRECT-1 behavior
- ENTERPRISE EXTENTS-1 rejection
- import/export bytes and streams
- arbitrary binary content, empty content, embedded NULs
- integrity verification
- diagnostics
- diff
- three-way merge and conflict resolution
- storage rebuild/invalidate/GC
- recovery without derived storage
- malformed/truncated containers
- dependency cycles
- deterministic writer output
- writer-to-reader round-trip

---

## Implementation Status

| Language | Status | Notes |
|----------|--------|-------|
| Python | Library-Complete | Full library API, all tests pass (152) |
| C# | Library-Complete | Full library API + byte-level interop (133) |
| JavaScript/TypeScript | Library-Complete | Full library API + byte-level interop (108) |
| Go | Library-Complete | Full 19-capability surface. 21 native tests pass and the shared conformance corpus passes 11/11, including byte-identical regeneration of all four interop scenarios and the executed LimitCleanUp contract. |
| C | Library-Complete | VsnContainer handle API, file/revision/object calls, streaming I/O, executed LimitCleanUp probe (80) |
| C++ | Library-Complete | RAII wrapper over C core: Container class, error types, full library surface (40) |
| Rust | Library-Complete | Full 19-capability surface. 27 native tests pass and the shared conformance corpus passes 11/11, including byte-identical regeneration of all four interop scenarios and the executed LimitCleanUp contract. No runtime dependencies. |
| F# | Library-Complete | .NET F# discriminated-result API + executed LimitCleanUp probe (44) |
| Java | In Development | Full VsnStore with file/revision/object API, transactions, validation, recovery |
| Julia | In Development | Parse, encode, container model, validation, recover |
| R | In Development | parse_vsn, build_container, validate_structural, recover |
| Ada | In Development | Package with Container type, parse/encode/validate/recover functions |
| Kotlin | In Development | VsnStore class, file/revision/object API, validation, recovery |
| Swift | In Development | VsnContainer, MutableStore, validation, recovery via Result types |
| D | In Development | parseVsn, encodeVsn, validateStructural, recover structs and functions |
| Zig | In Development | parse, encode, Container/Record/ObjectEntry structs, validation |
| Fortran | In Development | parse/encode/validate/recover subroutines with derived types |
| COBOL | In Development | PARSE-CONTAINER, VALIDATE-STRUCTURAL, RECOVER-DATA paragraphs |
| Objective-C | In Development | VsnContainer, VsnStore classes, validation/recovery methods |
| PHP | In Development | parse, encode, Container class, MutableStore, validate/restore |
| Ruby | In Development | VSN module, Container, MutableStore, parse/encode/validate |
| Dart | In Development | Container, MutableStore, parse/encode, validation, recovery |
| Scala | In Development | VsnContainer, MutableStore, parse/encode/validate/recover |
| Lua | In Development | VSN library with parse, encode, validate_structural, recover |
| Elixir | In Development | VSN module + MutableStore struct, parse/encode/validate |
| Erlang | In Development | parse/encode/validate/recover functions with records |
| Haskell | In Development | Container/Record types, parse, encode, validate, recover |
| OCaml | In Development | Container type, parse/encode/validate via result types |
| Nim | In Development | parse, encode, validateStructural, recover procs |
| Crystal | In Development | VSN class with parse, encode, validate_structural, recover |
| Perl | In Development | VSN package with parse, encode, validate_structural, recover |

Status is computed by `Conformance/run_conformance.py` from four **independent**
axes (protocol conformance, library capability implementation, library test
coverage, interoperability). A language is only reported `Library-Complete` when
all four hold and every documented capability group has a matching passing test.

**Declared size `0x0511`** means the **logical materialized content length** —
not the representation payload length and not `ObjectLength` (SR-27, DR-6).
Absence is fully valid; a mismatch on a present value is invalid canonical state.

---

## Notes

- This contract defines **library-level semantics**, not protocol rules.
- Protocol rules are frozen in `Specification/VSN_Specification.md`.
- Implementations may add language-specific conveniences beyond this contract.
- Conformance runner (`Libraries/Conformance/run_conformance.py`) tracks implementation status.

## Frozen Invariants

All implementations must preserve these frozen invariants:

1. **FileIdentity.FileId = 0x0101** (not 0x0001).
2. **Trailer canonical record count excludes ModeDeclaration** (GR-13).
3. **CommitMarker is sole acceptance authority** (RC-01).
4. **ExpectedRevisionId is precondition only, NEVER persisted**.
5. **ENTERPRISE uses DIRECT-1 only; EXTENTS-1 forbidden** (GR-43).
6. **No indexes, caches, checkpoints, or derived storage may become canonical authorities**.

- **Requirements:**
  - Support streaming import/export for large files.
  - Do not require full content in memory.
  - Stream APIs return byte count for export.

  - `operation: string | null`: Operation context.
- **Requirements:**
  - Return structured diagnostics instead of raising exceptions.
  - Support all validation levels.

Implementations must provide these capabilities to be Library-Complete:

### Container Store
- **Class:** `VsnStore` (or equivalent)
- **Functions:**
  - `create(mode: int) -> VsnStore`: Create new container.
  - `open(data: bytes) -> VsnStore`: Open existing container.
  - `close() -> void`: Close container.
  - `commit() -> bytes`: Commit changes and return canonical bytes.
  - `to_bytes() -> bytes`: Serialize without incrementing generation.
  - `reopen(data: bytes) -> void`: Reopen from bytes.
- **Requirements:**
  - Maintain file, revision, and object state.
  - Support deterministic serialization.
  - Preserve generation across commit/reopen cycles.

### File API
- **Functions:**
  - `create_file(path: string, content: bytes) -> FileId`: Create new file.
  - `read_file(file_id: FileId) -> bytes`: Read file content.
  - `write_file(file_id: FileId, content: bytes) -> void`: Update file.
  - `delete_file(file_id: FileId) -> void`: Delete file.
  - `rename_file(file_id: FileId, new_path: string) -> void`: Rename file.
  - `list_files() -> list[(FileId, path)]`: List all files.
  - `file_exists(file_id: FileId) -> bool`: Check existence.
  - `get_file_id(path: string) -> FileId | null`: Lookup by path.
- **Requirements:**
  - FileId is 16 bytes (UUID).
  - Reject duplicate paths.
  - Support arbitrary binary content (including empty, NULs).

---

## Writer Storage Policy Contract

VSN defines exactly two normative wire modes and four informative writer-side storage-policy profiles. The complete formal contract is in `library_api_contract_policy.md`.

| Wire Mode | Value | Permitted Storage Policies |
|-----------|-------|--------------------------|
| MODERN | 0x01 | HIGHLY_VERTICAL, VERTICAL |
| ENTERPRISE | 0x02 | HORIZONTAL, HIGHLY_HORIZONTAL |

**Key invariants:**
- Policies do NOT appear in the container binary.
- Policy names are implementation-local configuration values.
- A reader never needs to know the writer's policy to decode a container.
- All four policies preserve identical logical VSN semantics (SR-37).

