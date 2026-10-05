# BinaryRevisionWithProtocol (BRP-1)

Static specification site and documentation generator for the **Binary Revision Protocol (BRP-1)**.

## Repository contents

- `generate_docs.py` — specification generator. Running `python generate_docs.py` writes `docs.html`.
- `docs.html` — generated specification output (do not edit by hand; regenerate from the generator).
- `index.html`, `style.css`, `script.js` — static site shell. `index.html` and the top of `docs.html` present VSN Mode (MODERN / Vertical and ENTERPRISE / Horizontal) as a first-class architectural concept; both link to the normative Section 11.
- `Libraries/` — VSN Library implementations across 31 language targets. All 31 have genuine capability tests (Tier 2) and thread-safe stores (Tier 3). **12/31 fully verified** via conformance runner with all 19 capabilities passing; **19 NOT_VERIFIED** due to Docker/infrastructure blockers — all test code fixes (syntax, API mismatches, assertion depth, exit codes) have been applied. COBOL is the exception: no native threading, so Tier 2 is sequential and Tier 3 is documented as a limitation.
- `docs_part1.html` — historical/candidate material only. **Non-authoritative; MUST NOT be promoted automatically.**

## Specification state

- 53 sections, numbered 01–53, generated sequentially with no duplicates.
- Verified normative core: Sections 12–21 (Revision Model, RevisionSet, FileHead, Logical Commit vs Physical Projection, ApplyTransaction, Crash Recovery, VSN Atomicity, Integrity, Paths, Rename/Move/Delete).
- Section 10 (Canonical / Derived Boundary and Object Model) carries the canonical-versus-derived architecture, hash working modes and hash-independence rules, the object store and dedup model, the mandatory physical framing and canonical recovery chain, the index, materialized snapshot, and checkpoint contracts, integrity coverage, the storage-over-compute principle, and the canonical encoding and collection ordering contracts.
- Section 11 (VSN Mode: Modern and Enterprise) defines the two VSN Modes, the feature-parity invariant, mode-is-not-semantic-identity, the Computation Unit, Pre-Materialized Content, the Vertical computation contract, mode-independent framing, and cross-mode recovery equivalence.
- Section 19 defines the four hash domains (ContentHash, MembersDigest, ApplyTransactionHash, ContainerIntegrityHash) as **algorithm-selected metadata**, not canonical semantic identity.
- Section 38 defines eight distinct recovery/verification states so that unavailable algorithms are never reported as corruption.
- Section 48 (Implementation Guidance, *Informative*) points to the dedicated Library reference and adds no capability content of its own.

## VSN Library capability reference

- `libraries.html` is the **VSN Library Implementation and API Capability Reference**, a top-level page in the main navigation alongside `Docs`.
- Section 2 of that page is **Supported Languages**: **31 language targets** for the VSN Library API, in this order — C, C#, C++, Java, Python, Rust, Go, JavaScript / TypeScript, Julia, R, Ada, Kotlin, Swift, D, Zig, Fortran, COBOL, Objective-C, PHP, Ruby, Dart, Scala, Lua, Elixir, Erlang, Haskell, OCaml, F#, Nim, Crystal, Perl. C, C#, and C++ are separate entries; JavaScript / TypeScript is one combined target. The list lives in `generate_docs.py` as the single source constant `LIBRARY_LANGUAGES`, where each entry records language, binding type, core API surface, data/streaming, and validation/recovery.
- Every target has an active implementation. **31/31 have capability tests (Tier 2) and thread-safe library stores (Tier 3)** using each language's native concurrency primitive. **12/31 fully verified** (Ada, C#, Crystal, F#, Go, JavaScript-TypeScript, Kotlin, PHP, Python, Rust, Swift, Zig); **19 NOT_VERIFIED** due to Docker/infrastructure blockers — all test code fixes applied. COBOL is the single exception: no native threading, so Tier 2 runs sequentially and Tier 3 is documented as a known limitation.
- **Supported languages and supported representations are different concepts.** A programming language is not a VSN representation, and a binding is not a different VSN format; all 31 targets read and write one format governed by one specification. The representations are `DIRECT-1` and `EXTENTS-1`. The Languages section states this explicitly and is kept structurally separate from the capability and representation sections.
- Language bindings expose the Library API surface documented in the later sections (open/create, read/write, file, revision, object, representation, validation, recovery, diff, import/export, storage, diagnostics). Capabilities are documented once and not repeated per language.
- CLI tools, workbenches, editor integrations, and diagnostic applications are separate from language bindings and are not part of the language list.
- It documents what an implementation may do with a `.vsn` file: container, file, revision, content and object, representation, transaction, recovery, validation, diff, merge, checkout, import/export, streaming, mode, storage, GC, integrity, forward-compatibility, concurrency, limits, rewrite, multi-container, capability query, diagnostics, observability, and error-model capabilities, plus the capability matrix and the protocol/Library boundary table. The page now has 34 sections.
- It is generated by `generate_docs.py` (function `build_libraries_page()`), which writes both `docs.html` and `libraries.html`. There is one generator and one source of truth. Library page section numbers are assigned in declaration order, so inserting a section does not renumber the ones after it.
- The page is documentation of the implementation/API layer **on top of** VSN-1. It adds no record type, field, identifier, requirement, or protocol error ID, and it does not modify the frozen specification.
- Every capability is labelled an **intended capability** or a **Library facility**. No implementation is claimed, because the repository contains the specification and its generated documentation only.

## VSN Mode (Modern / Vertical, Enterprise / Horizontal)

A **VSN Mode** is the representation mode selected for a VSN container. Exactly two modes exist. They are operating modes of one VSN library, not separate products, tiers, or libraries.

| Mode | Representation | Resource architecture |
|---|---|---|
| **MODERN** | Vertical Representation | uses the **Computation Unit** for content representation and reconstruction |
| **ENTERPRISE** | Horizontal Representation | uses **Pre-Materialized Content**; consumes no Computation Unit for content reconstruction |

Modern Mode *is* the Vertical Representation; Enterprise Mode *is* the Horizontal Representation.

- **Same library, same features.** VSN Mode MUST NOT remove, disable, or redefine any VSN library feature. Both modes expose the complete feature set: create/open, read, write, edit, revisions, revision history and relationships, file reconstruction, delete/recovery semantics, canonical recovery, metadata, and verification when available. Mode never determines which APIs or features exist — only the representation strategy for persisted file content and edit history.
- **Computation Unit.** The logical component performing permitted content representation, materialization, and reconstruction work (analysis, transform, deduplicate, chunk, apply delta/patch, algorithmic reconstruction). Modern Mode uses it for content representation and reconstruction. Enterprise Mode MUST NOT consume it for content reconstruction. This is not a claim of literally zero CPU: ordinary reading, copying, container-metadata parsing, record enumeration, reference resolution, length validation, and I/O are not Computation Unit reconstruction work.
- **ENTERPRISE / HORIZONTAL — full copy only.** For file editing through the VSN library, a Horizontal Representation MUST persist the resulting logical file content as a **FULL COPY**; the edit MUST NOT introduce a content reconstruction instruction chain. A Horizontal edit MUST NOT depend on diff, delta, patch, edit script, reconstruction instructions, previous-revision content, deduplication reconstruction, or algorithmic content synthesis. Recovery = materialize stored content. This applies to *file content edit representation* only: an Enterprise container still carries ordinary metadata, references, framing, versions, indexes, and integrity data.
- **Pre-Materialized Content.** Content whose complete logical content, required for the corresponding revision and file state, is already stored in the VSN representation. It is **canonical persisted content** — never a cache, checkpoint, derived artifact, or optional optimization. Deleting it is deleting canonical recovery data.
- **MODERN / VERTICAL — flexible representation.** Modern MAY use deduplication, content sharing, delta/diff, patch, compressed or shared representations, chunking, revision-to-revision reuse, indexing, caching, algorithmic reconstruction, and future algorithms. **No single optimization algorithm is mandated** — the specification defines the required semantics and recovery properties, not one implementation algorithm. A Vertical Representation MUST contain sufficient normative information, instructions, operands, references, and/or source data for deterministic reconstruction by an implementation that supports the declared representation identity and version. Components required by that representation are canonical recovery data, not deletable caches. Modern **may** reduce storage consumption; this specification never claims it always does.
- **Storage/computation trade-off.** Modern consumes computation to reduce storage; Enterprise consumes storage to avoid computation. Neither is better or worse; no numerical claim is made anywhere, because no measured benchmark data exists.
- **Compatibility positioning.** Enterprise is compatibility-oriented: it minimizes the number of content reconstruction mechanisms required for recovery. This specification does **not** claim Enterprise will be readable by every future implementation — long-term compatibility still depends on versioning, mandatory framing, mandatory record semantics, mandatory baseline representations, supported codecs, and defined recovery rules. Modern is modern, storage-efficient, and representation-flexible; it is **not** less compatible by definition — compatibility depends on whether the representation used falls within the mandatory supported specification.
- **Same canonical semantics and recovery.** VSN Mode MUST NOT become part of canonical object identity and MUST NOT change the semantic identity of files, revisions, revision relationships, accepted state, or recovered logical content. Both modes follow the identical canonical recovery chain, use identical record framing, and produce identical logical content bytes for the same canonical content state. Physical representations need not be byte-identical; only the recovered semantics are compared.
- **Hash independence.** Hash working mode (`None`, `BLAKE3-256`, `SHA-256`) remains independent of VSN Mode; all six combinations are valid. ContentHash stays optional metadata and MUST NOT become the canonical object identifier merely because Modern can benefit from hashing.
- **Unfrozen.** Identity, binary grammar, semantic rules, error identifiers, registries, recovery semantics, and verified byte vectors are **now frozen** by ID-01…ID-62, GR-01…GR-53, SR-01…SR-45, VR-01…VR-37, RC-01…RC-45, and BP-01…BP-10. Still unfrozen: the internal payload grammar of representations other than the two designed here (**UNPROVEN** — no delta/chunked Modern representation is designed, so no such byte vector exists); MembersDigest ordering; index/derived encodings; checkpoint cadence; compression values beyond IDENTITY; and all expected hash fixtures for constructs beyond the frozen fixtures. Steps 1–6 resolve no other byte-level blocker and change no 8-Gate freeze-review verdict.

## Canonical identity model (Step 1 — frozen)

Section 10 freezes canonical identity as numbered rules **ID-01 … ID-62**. Semantics are frozen; binary encoding is deferred to the binary grammar freeze step.

- **`ObjectSerial`** (ID-01…ID-16) — persistent canonical identifier of one canonical content object, unique **within one VSN container**; assigned by the writer when the object record is committed by an accepted RevisionSet; never an offset, block/record number, ordinal, index, hash, or checksum; never renumbered by compaction, re-layout, compression change, or index rebuild; never reused within the container lifetime; a new container from export MAY assign new values.
- **`RevisionId`** (ID-17…ID-24) — persistent identifier of one Revision, unique per container, identified with FileId; never physical/ordinal/hash/derived; permanent across head movement, branching, rename, deletion, re-layout, and mode change; never reused; `Generation` is never revision identity.
- **Parent relationships** (ID-25…ID-32) — explicit repeatable parent `RevisionId` list; 0 parents = initial Revision; 1 = linear; 2+ = branch/merge; order carries no meaning; repeated parent, self-parent, and cycles are deterministic canonical validation failures; missing parent = deterministic reference failure; parents are never inferred from order, timestamps, Generation, diffs, or hashes.
- **`RevisionSetId`** (ID-33…ID-36) — container-local persistent identifier of a RevisionSet; needed because the accepted boundary and member set are canonical group facts, not derivable from members.
- **`FileId`** (ID-37, ID-38) — file identity; path/name at a revision is `PathSnapshot` data, never identity.
- **`FileHead`** (ID-39…ID-45) — canonical reference `(FileId, head RevisionId)`; at most one per FileId; may be absent before first acceptance; `ExpectedRevisionId` is an operation precondition, never canonical state and never a second head reference; head movement changes no identity; historical Revisions stay addressable; head recovered from canonical FileHead records with no index.
- **`ContentRef`** (ID-46…ID-50) — **required `ObjectSerial`** + optional `ContentHash` (verification/acceleration only) + optional `size` (validation only); resolvable under `HashMode = None` with no hash, index, manifest, offset, or record order.
- **Invalid identity** (ID-51…ID-57) — duplicate ObjectSerial/RevisionId/RevisionSetId, dangling references, cross-container references, and parent cycles are all distinct deterministic failures, never implementation-defined and never heuristically repaired.
- **Classification** (ID-58…ID-62) — ObjectSerial, RevisionId, RevisionSetId, FileId, FileHead, parent RevisionId, ContentRef are canonical. ContentHash, size, index/cache mappings, offsets, record ordinals, snapshots are **not** identity. The full identity graph is reconstructable from canonical records alone, and survives physical relocation.

## Canonical binary grammar (Step 2 — frozen)

Section 10 freezes the canonical binary grammar as rules **GR-01 … GR-53** with test vectors **BV1 … BV24**. It is one grammar, common to both modes.

```text
Container ::= Magic ContainerFormatVersion EncodingVersion HeaderFields RecordsEnd
Magic                ::= 0x56 0x53 0x4E 0x2D        ; "VSN-", 4 bytes
ContainerFormatVersion ::= u16be                       ; 1 = VSN-1
EncodingVersion      ::= u16be                       ; 1 = RCMP-1
HeaderFields         ::= Field*                       ; until RecordsEnd marker
Field                ::= FieldId FieldLength FieldValue
FieldId              ::= u16be
FieldLength          ::= uvarint
FieldValue           ::= byte[FieldLength]
uvarint              ::= 1..10 bytes, LEB128, little-endian significance,
                        high bit = continuation, minimal encoding required
RecordsEnd           ::= FieldId 0x0000 with FieldLength 0
Records              ::= Record*
Record               ::= RecordType RecordLength RecordPayload
RecordType           ::= u16be
RecordLength         ::= uvarint                       ; payload bytes only
RecordPayload        ::= byte[RecordLength]
Object               ::= ObjectSerial ObjectLength ObjectDescriptor
ObjectSerial         ::= uvarint
ObjectLength         ::= uvarint                       ; descriptor bytes only
```

Key frozen points:
- **Byte order** — every fixed-width multi-byte integer is big-endian. "native endian", "host order", and "implementation-defined" are prohibited for canonical data (GR-08).
- **Lengths** — every length counts payload/value bytes only, never its own encoding bytes (GR-03).
- **Field order** — fields appear in strictly ascending `FieldId`, no repeats except declared repeatable collections (GR-16).
- **Collections** — uvarint count followed by count elements; empty = count 0; parent and RevisionSet member lists use the canonical member ordering (GR-19).
- **Primitives** — uvarint (minimal LEB128), u16be/u32be/u64be, boolean = exactly `0x00`/`0x01`, strings = well-formed NUL-free UTF-8 with no normalization (GR-21…GR-26).
- **Uniqueness** — one canonical value has exactly one canonical byte encoding; non-minimal integer encodings are rejected (GR-24).
- **Record types** — global u16be space: `0x0000` end-of-records, `0x0001` FileIdentity, `0x0002` Revision, `0x0003` RevisionSet, `0x0004` FileHead, `0x0005` ContentObject, `0x0006` CommitMarker, `0x0007` ModeDeclaration, `0x0008` RepresentationDescriptor, `0x8000–0xFFFE` extension, `0xFFFF` reserved (GR-28).
- **Field IDs** — `0x0001–0x7FFF` protocol-assigned, `0x8000–0xFFFE` extension, `0xFFFF` reserved; `0x0000` is the `RecordsEnd` marker (GR-17).
- **Unknown records/fields** — skipped by their own declared extent, preserved byte-for-byte on rewrite, container stays valid, distinguishable from malformed framing (GR-29…GR-33).
- **References** — `ObjectSerial`, `RevisionId`, `RevisionSetId`, parent `RevisionId` = uvarint (0 reserved); `FileId` = 16-byte UUID (all-zero reserved); `FileHead` = FileIdentity record pair, not a standalone ref; `ExpectedRevisionId` is never persisted; `ContentHash` is never required and never a fallback identity (GR-35…GR-37).
- **Mode encoding** — one mandatory `ModeDeclaration` record, field `0x0701`: `0x01` MODERN, `0x02` ENTERPRISE; no mixed modes; Mode never enters any identity encoding (GR-38…GR-40).
- **Object framing** — locate the complete payload without executing the reconstruction algorithm; unsupported representation ⇒ *unsupported representation*, never malformed framing (GR-06, GR-07, GR-41, GR-42).
- **ENTERPRISE payload** — complete logical content directly as a length-delimited byte run; never a delta, patch, or reconstruction instructions (GR-43).
- **EOF/truncation** — valid EOF requires the end-of-records marker, consumed object section, and complete trailer; physical EOF mid-unit is always truncation, never valid (GR-46, GR-47).
- **Trailing bytes** — bytes after the trailer are malformed; readers MUST NOT silently ignore them (GR-48).
- **Padding** — never inside any declared extent; physical block padding is not canonical (GR-20, GR-27).

## Canonical semantic rules (Step 3 — frozen)

Section 10 freezes the semantic layer as rules **SR-01 … SR-45**, with vectors **SV-A…SV-L** (valid) and **SI-1…SI-22** (invalid). It does not alter Step 1 identity or Step 2 grammar.

- **Canonical state** (SR-01, SR-02) — the exact set of canonical records/objects/relationships recovering files, FileIds, PathSnapshots, Revisions, parents, ContentRefs, RevisionSets, FileHeads, objects, representation data, and accepted state. An artifact is **canonical iff removing it makes that state unrecoverable**; everything rebuildable is derived. Classification is per artifact, not per record type.
- **Layers** — `Physical Bytes → Binary Structure → Canonical Records → Canonical Semantic State → Logical File State → Logical File Bytes`, with Derived Data as an independent branch that is never an input.
- **Cardinality** (SR-05, SR-06) — ModeDeclaration exactly 1; FileIdentity/Revision/RevisionSet/ContentObject one record per identity; FileHead at most one per FileId (no last-wins); CommitMarker multiple markers each declare a Generation, highest accepted is authoritative. **Record order never carries meaning** and nothing supersedes by position or Generation.
- **Conditional fields** (SR-09) — `Presence` is always required; `PRESENT` → ContentRef required, PathSnapshot required; `DELETED` → both forbidden; `DIRECTORY` → ContentRef forbidden, PathSnapshot required.
- **Files & paths** (SR-07…SR-13) — a FileId names a file only with a FileIdentity record; deletion is a `DELETED` Revision that never erases history; rename/move preserve FileId and all RevisionIds and create a new Revision with a new PathSnapshot; path is never identity; two FileIds may collide on a path (reported, never merged); path semantics are platform-neutral byte comparison, case- and separator-sensitive, never normalized.
- **Revisions** (SR-14, SR-15) — a committed Revision is **immutable** in identity, file, presence, parents, ContentRef, PathSnapshot, metadata, and Generation; any change is a new Revision; no accepted flag lives on a Revision.
- **Parents & Generation** (SR-16, SR-17) — parents are explicit and unordered (0 = initial, 1 = sequential, 2+ = merge, no extra metadata); Generation is a canonical *ordering* value, never identity or parentage, never `parent+1`, and optional on FileHead.
- **Accepted state** (SR-21…SR-24) — marker-based (CommitMarker + FileHeads), never heuristic; head may point anywhere valid, move backward, or point at a branch; five distinct states: **accepted / unaccepted / incomplete / abandoned / invalid**.
- **Content** (SR-26…SR-31) — `size` means expected **logical content** bytes (not representation bytes); ContentHash and size never affect semantics; sharing is optimization; Modern must be deterministic and self-contained; unsupported representation ≠ invalid; Enterprise persists the complete content with no previous-Revision or Computation Unit dependency.
- **Validity, equality, order** (SR-32…SR-35) — six reference classes (valid/missing/foreign/duplicate/cyclic/invalid); duplicates are never resolved by last-wins; **every collection has set semantics**; four equality levels: byte < structural < canonical-state < logical-content, where canonical-state equality is the interoperability relation.
- **Equivalence** (SR-37…SR-40) — cross-mode and recovery equivalence; only the ModeDeclaration value may differ between equivalent containers; full feature parity; all three hash modes yield identical identity, graph, head, accepted state, and content.
- **Validation order** (SR-41) — framing → field presence → identity uniqueness → references → relationships → accepted state → representation support → materialization → optional verification. Steps 1–7 complete **before** any content reconstruction.
- **Derived deletion** (SR-42…SR-45) — removing every index, cache, checkpoint, manifest, diff artifact, offset hint, and hash accelerator leaves full recovery intact; anything whose removal breaks the chain is misclassified and must be reclassified as canonical.

## Version & registry model (Step 4 — frozen)

Section 10 freezes the version and registry model as rules **VR-01 … VR-35**, with vectors **V1–V6, H1–H6, R1–R7, C1–C6, E1–E3, A1–A3**. Sections 39 (Error Wire Format), 40 (Registry), and 46 (Registries) now resolve against it.

**Core principle (VR-01).** A registry is a *naming mechanism*: `Identifier → Registry meaning → Capability`. All three are spec-defined and local. Reading a historical `.vsn` **must never** require a live registry service, URL, or DNS lookup. Registry *documentation* ≠ registry *execution*; a local registry table is an implementation mechanism, not an external dependency.

**Version domains (VR-08)** — eleven distinct namespaces, never overloaded: Protocol Version, ContainerFormatVersion, EncodingVersion, Mode Identifier, Representation Identity, Representation Version, Hash Algorithm Identifier, Compression Identifier, Transform Identifier, Error Identifier, Extension Identifier.

**Compatibility matrix (VR-12)** — every cell deterministic; no "best effort" or "generally compatible" cells.

| Reader | Container | Encoding | Result |
|---|---|---|---|
| V1 | 1 | 1 | supported |
| V1 | unknown | any | unsupported container version; no decode |
| V1 | 1 | unknown | unsupported encoding version; no decode |
| V1 | newer | known | unsupported unless that version explicitly declares the V1 grammar valid |
| Future | 1 | 1 | supported; must preserve unknown records/fields byte-for-byte |
| Any | 1 | 1 | identical canonical state and logical content regardless of Mode/hash mode |

- **Monotonicity ≠ compatibility** (VR-13): a larger number never implies support for a smaller one. No silent coercion, downgrade, or upgrade (VR-14).
- **Mode** — `0x01` MODERN, `0x02` ENTERPRISE, everything else reserved; unknown is malformed and never defaulted (VR-16, VR-31). Mode never changes identity or semantics.
- **Hash** — `0x00` NONE, `0x01` SHA-256, `0x02` BLAKE3-256 (32-byte digests), `0x03–0x7F` reserved, `0x80–0xFE` vendor, `0xFF` reserved. Hash identifiers are **verification-only** and never identity or a resolution fallback (VR-17).
- **Digest domain** (VR-18): a ContentHash covers **raw logical content bytes, before any compression/representation/framing, excluding ObjectSerial, descriptor, and container framing**. RecordHash, MembersDigest, and ContainerIntegrityHash are separate digest kinds.
- **Representation** — `0x0000` reserved, `0x0001–0x7FFF` core, `0x8000–0xFFFE` vendor; version 0 reserved. **Allocated: `0x0001` = DIRECT-1 and `0x0002` = EXTENTS-1, each Version 1.** The descriptor is self-describing: identity, version, operands, sources, parameters, transforms all carried canonically (VR-20). Operand categories: `OBJECT_SOURCE`, `REVISION_SOURCE`, `LITERAL_BYTES`, `NUMERIC`, `STRING`, `TRANSFORM`, `NESTED` (VR-23). Forbidden dependency edges: cache, index, external database, undeclared previous revision (VR-24).
- **Compression/transform** — `0x00` IDENTITY, `0x01–0x7F` core, `0x80–0xFE` vendor, `0xFF` reserved. Compression is representational and **never changes logical content** (VR-25). Separate from Representation and Transform namespaces (VR-26).
- **Errors** — 21 stable identifiers `0x0000`–`0x0014` (OK, MALFORMED_CONTAINER, TRUNCATED, UNSUPPORTED_CONTAINER_VERSION, UNSUPPORTED_ENCODING_VERSION, UNSUPPORTED_PROTOCOL_VERSION, UNSUPPORTED_REPRESENTATION, UNSUPPORTED_TRANSFORM, MISSING_OBJECT, MISSING_CANONICAL_REFERENCE, DUPLICATE_IDENTITY, INVALID_RELATIONSHIP, INVALID_CANONICAL_STATE, VERIFICATION_UNAVAILABLE, VERIFICATION_MISMATCH, INVALID_UTF8, RESERVED_VALUE, INVALID_FIELD_ORDERING, INVALID_LENGTH, UNKNOWN_MANDATORY_RECORD, ACCESS_OR_DECRYPTION_FAILURE), `0x0015–0x7FFF` reserved, `0x8000–0xFFFE` vendor. Immutable meanings, never reused, never canonical (VR-28, VR-29).
- **Unknown values** (VR-30) are classified per namespace — record/field extensions skippable, versions fatal-unsupported, mode never guessed, representation/transform scoped-unsupported, hash ignored, errors diagnostic.
- **Lifecycle** (VR-32): `active` / `deprecated` (still valid) / `reserved` / `retired` (historically readable, never reusable) / `unknown` are five distinct states.
- **Ownership** (VR-33): core `0x0001–0x7FFF`, vendor `0x8000–0xFFFE`, top value reserved — collision impossible by construction.
- **No registry versioning layer** (VR-35): registries are versioned by this specification itself.

**Archival:** a container written in 2026 is fully interpretable in 2076 from its bytes + this published specification + declared implementation capabilities. The original writer, registry service, indexes, caches, and storage engine are unnecessary (VR-27).

**Range correction:** the legacy §46 wording `0x01–0xEF core / 0xF0–0xFF ext` conflicted with frozen **GR-28** (`0x0001–0x7FFF` / `0x8000–0xFFFE`). GR-28 governs; the conflict is recorded explicitly in §46.

## Recovery & failure semantics (Step 5 — frozen)

Section 10 freezes recovery as rules **RC-01 … RC-45** with vectors **T1–T32**. Sections 17 (Crash Recovery) and 28 (Atomicity) now resolve against it.

**Accepted state (RC-01).** `CommitMarker` is the **sole** acceptance authority. The accepted canonical state is exactly the canonical data physically preceding the effective marker: the highest-Generation structurally complete, semantically valid `CommitMarker`. No heuristic — never latest record, highest Generation without a valid marker, record position, file length, offset, timestamp, largest RevisionId/ObjectSerial, index, cache, or checkpoint (RC-41).

- **Commit scope** (RC-02): everything before the effective marker is accepted; everything after is uncommitted regardless of completeness.
- **Multiple markers** (RC-03): permitted, append-only, each a historical accepted state; exactly one is effective; ties are invalid. **Not "last wins"** — highest *valid* Generation wins.
- **Broken later marker** (RC-04): truncated/malformed markers are discarded; the earlier valid commit survives.
- **Invalid covered data** (RC-05): the marker is not effective; fall back to the previous valid marker.
- **Generation** (RC-06): container-global commit sequence, required on every marker, monotonic, gaps allowed, duplicates invalid, lower-after-higher is *stale* (never a rollback).
- **Transaction states** (RC-07): `UNCOMMITTED` / `COMMITTABLE` / `ACCEPTED` / `ABANDONED` / `INVALID`. "Not committed" ≠ "invalid".
- **Visibility** (RC-08): only marker-covered data is file content; uncommitted records are retrievable only on explicit request.
- **Durability ≠ acceptance** (RC-09): acceptance is a semantic fact; durability is the writer's obligation under its declared storage contract.
- **Atomicity** (RC-10): guaranteed at the VSN commit boundary, not by the filesystem — correct under atomic append, reordered writes, partial writes, delayed flush, and torn sectors.

**Torn writes & prefix recovery** — truncation is *never* corruption (RC-11). Interruption at *any* byte boundary yields either a valid complete container or a discarded incomplete tail (RC-12). A permitted incomplete tail after the marker is silently discarded; this is the **only** tolerance the grammar grants, and it stays bounded by GR-48 — complete-but-malformed bytes after the marker are `MALFORMED_CONTAINER`, not a tail (RC-13, RC-15). Complete well-formed uncommitted records after the marker (including a complete higher-Generation marker whose covered set is incomplete) are permitted but never accepted (RC-14, RC-16). Phantom acceptance is impossible (RC-18).

**Crash points** — a 10-row table fixes the observable state at every crash point: before any bytes, during the header, during a record, after objects, after the Revision, after the FileHead but before the marker, during the marker, immediately after a complete marker, after commit during a derived-data update, and during a physical re-layout. Rollback is automatic and read-only (RC-19).

**Checkpoints are derived** (RC-21): deleting every checkpoint, index, cache, and manifest leaves accepted state unchanged, because acceptance is found by scanning canonical records for the effective marker. Scanning is the normative recovery mechanism (RC-22).

**Identity lifecycle** (RC-24): identifiers allocated in a transaction that never commits are **permanently consumed** — required by ID-08/20/34/37, so identity lifecycle cannot depend on commit success. Uncommitted complete records are canonical-but-not-accepted and preserved on rewrite (RC-25). Orphan objects are canonical-but-unreachable, reclaimable, with their serial still consumed (RC-26). No abort record is required (RC-27).

**Failure taxonomy** (RC-29) — six classes that never collapse: truncated, malformed, invalid canonical state, missing canonical data, unsupported, verification.

**Recovery order** (RC-30) — 11 numbered steps, stopping at the first failure; earlier blocking failures mask later ones (RC-31). An 18-row **failure priority matrix** fixes, per condition, the detection stage, error identifier, whether the previous accepted state is recoverable, and whether content reconstruction is allowed.

**Recovery state machine** — `UNREAD → STRUCTURALLY VALIDATING → COMMIT BOUNDARY DISCOVERY → CANDIDATE ACCEPTED STATE → SEMANTIC VALIDATION → CANONICAL REFERENCE RESOLUTION → TAIL CLASSIFICATION → REPRESENTATION VALIDATION → RECOVERABLE → verification`, with each failure branch naming its distinct error identifier (no ambiguous generic ERROR).

**Determinism** (RC-34): identical bytes + identical capabilities = identical accepted state, failure class, error identifier, logical content, and verification status. Recovery needs a sequential scan; an index may accelerate but is never required (RC-35). Mode/version are immutable per container (RC-39).

**Proof obligations** (RC-42…RC-45): exactly one effective marker is selected (maximum over a totally ordered valid set); no path lets the tail become accepted; no artifact outside canonical data can redefine acceptance; missing data is reported, never substituted.

## Byte vectors and byte-level evidence (Step 6 — frozen)

Every vector in Section 10 was produced by an executable encoder and re-parsed by an independent decoder written directly from GR-01…GR-53. The stated results are observed, not asserted. Families: **BV-01…BV-11** primitives · **CV-01…CV-08** containers · **HV-01…HV-09** hash · **MC-01…MC-09** multi-commit · **TV-03…TV-TAIL** truncation prefixes · **IV-01…IV-14** invalid · **XV-01…XV-04** extensions. Proofs **BP-01…BP-10**.

**CV-01 — minimal ENTERPRISE container (148 bytes)**, annotated byte-range by byte-range:

```
56 53 4E 2D 00 01 00 01 00 00 00 00 07 04 07 01 01 02 00 01 13 01 01 10 01
23 45 67 89 AB CD EF 01 23 45 67 89 AB CD EF 00 02 2B 02 01 01 64 02 02 10 01
23 45 67 89 AB CD EF 01 23 45 67 89 AB CD EF 02 03 01 2A 02 10 09 6E 6F 74 65
73 2E 74 78 74 02 11 01 01 00 05 08 05 01 01 2A 05 11 01 0A 00 04 17 04 01
10 01 23 45 67 89 AB CD EF 01 23 45 67 89 AB CD EF 04 02 01 64 00 06 04 06
01 01 01 00 00 00 2A 0A 68 65 6C 6C 6F 20 76 73 6E 0A 00 06 00
```

Verified round trip `Encode(Decode(B)) == B`, logical content exactly `68 65 6C 6C 6F 20 76 73 6E 0A`, accepted state = the Generation-1 commit, recovered with no hash, index, or checkpoint.

**Canonicality proofs** — one primitive per field (BP-01) · one minimal uvarint (BP-02) · deterministic field order (BP-03) · deterministic collection order (BP-04) · one string form (BP-05) · deterministic references (BP-06) · deterministic digest encoding (BP-07) · no offset in identity (BP-08) · no hash in identity (BP-09) · byte-exact round trip (BP-10).

**Open-item closure** — FROZEN: primitives, framing, references, mode declaration, CommitMarker, hash fixtures, torn-write prefixes, extension preservation, Enterprise full-copy, and the Modern representation architectures **DIRECT-1** and **EXTENTS-1**. **DEFERRED (deliberately, because no frozen canonical byte depends on them):** MembersDigest ordering, compression values beyond IDENTITY, index/derived encodings, checkpoint cadence, §34/§35 registry detail, and additional Vertical representations (delta, chunked, compressed, sparse) — none of which any recovery result depends on.

**Representation architecture freeze (DR-0…DR-12)** — **Payload-location ownership is resolved.** Per-object representation payload placement is fixed by DR-0 together with the amended VR-20 and GR-41: `RepresentationDescriptor` (`0x0008`) remains the *shared contract* (one per Representation Identity/Version, no ObjectSerial, no per-object data, and `0x0810` is representation-level metadata only), while each object's `ObjectDescriptor` carries its own Representation Identity, Version, and complete representation-specific payload. `DIRECT-1` (`0x0001`) is the baseline representation of **both** modes; `EXTENTS-1` (`0x0002`) is the second. **Two layers, never conflated.** A `RepresentationDescriptor` record (`0x0008`) is the *shared declaration* of a representation contract — **exactly one per (Representation Identity, Representation Version)**, carrying only `0x0801` and `0x0802`, and **never an ObjectSerial** (`0x0501` remains owned solely by `ContentObject`, GR-17). The *per-object* representation data lives in that object's own `ObjectDescriptor` payload, which already begins with a three-byte header of Representation Identity (u16be) plus Version (uvarint) as SR-29 requires; the remainder is DIRECT-1 logical content bytes or, for EXTENTS-1, an ordered collection of `LITERAL(bytes)` or `COPY(sourceObjectSerial, sourceOffset, length)` operations. N objects using EXTENTS-1 v1 therefore need **1** declaration, not N; a differing duplicate declaration is invalid. Source resolution uses `OBJECT_SOURCE` and nothing else — no RevisionId, FileId, PathSnapshot, or parent dependency, and **no numeric ObjectSerial ordering rule** (ID-06). Range and accumulated-output arithmetic is checked; overflow is `INVALID_CANONICAL_STATE`. Declared size `0x0511` stays optional for both. No rule merges operations, sorts sources, or makes one representation byte sequence unique — **representation encoding is not necessarily unique, but materialization is deterministic.** Reader-local resource refusal is never a canonical verdict. An unsupported representation leaves the CommitMarker effective with no rollback (SR-30, SR-41, RC-05), verified by vectors UREP-01…UREP-03. No MRP1 envelope, no generic VM, and no fixed dependency-depth limit were introduced.

## Hash working modes

The library supports exactly three working modes: `None`, `BLAKE3-256`, `SHA-256`. None of them is required for canonical decoding or recovery. Canonical semantic identity and canonical recoverability MUST NOT depend on ContentHash or on any hash algorithm being available. Modes are isolated: switching mode MUST NOT change canonical revision history, canonical content, member sets, ordering, logical commit outcomes, or semantic identity.

## Core design principle

VSN implementations SHOULD prefer precomputed, directly consumable representations when doing so materially reduces repeated runtime computation. The computation-versus-storage choice is expressed through VSN Mode (Section 11): MODERN uses the Computation Unit for representation and reconstruction, while ENTERPRISE persists edited content by full copy and consumes storage instead. Repeated logical data MAY be deduplicated and referenced rather than physically duplicated, within the mode rules of Section 11 (an Enterprise Horizontal Representation MAY share complete pre-materialized objects only). Additional storage MAY be used to reduce reconstruction, hashing, canonicalization, indexing, validation, and diff work.

Canonical data is always the source of truth. Derived data is acceleration only: it MUST NOT alter canonical semantics, MUST NOT become a second source of truth, MUST be rebuildable from canonical data, and MUST be ignored and recomputed when missing, invalid, or of an unknown version. Canonical interoperability never depends on derived data.

**Maximum-compatibility principle.** Long-term semantic recovery depends on the frozen canonical rules and the canonical bytes physically preserved in the container, not on the continued existence of historical hashing, diff, compression, indexing, caching, or storage-engine implementations. Self-contained canonical information is preferred over information that must be reproduced by a future algorithm. An implementation with no historical hash algorithm MUST still recover all canonical information that is physically present and unencrypted.

**Canonical recovery chain.** `container signature → mandatory framing → canonical record type → mandatory fields → canonical references → canonical object bytes`. Recovery MUST be possible by enumerating canonical records through mandatory framing alone; derived indexes MUST NOT be required. Unknown *derived* units MUST be safely skippable; unknown *canonical* records are a distinct deterministic error and never a skip. Physical framing for index-free recovery is a normative requirement, and its byte layout remains a freeze blocker. Both VSN Modes follow this same chain with identical record framing; the mode changes only what the resolved content representation contains (Section 11).

**Terminology.** A canonical `Revision` is never a materialized snapshot; materialized snapshots, indexes, manifests, checkpoints, and derived diff caches are derived. Enterprise Pre-Materialized Content is canonical persisted content, and the data a selected Modern Vertical Representation requires is canonical recovery data for that representation — neither is a cache.

## Status labels

`Normative — Frozen` · `Normative — Review` · `Implementation Pending` · `Informative`

Sections currently marked Review: 10, 11, 28, 34, 35, 38.

## Recovery and verification states

Section 38 requires these states to be reported distinctly: `decoded`, `recovered`, `verified`, `verification unavailable`, `integrity mismatch`, `unsupported transform`, `missing object`, `malformed or corrupt canonical data`. Hash-algorithm unavailability is never corruption, never unreadability, and never a canonical failure; `NONE` working mode and encryption without the required key are likewise distinct from corruption. Encryption never changes canonical identity (identity-before-encryption).

## Freeze blockers (Review / TBD)

Concrete canonical primitive encodings (integer width, signedness, byte order, length and string encoding, boolean representation); record framing and record boundary rules; record type encoding and allocation; field encoding; length encoding; reference encoding, including the binary representation of every canonical identity field (<code>ObjectSerial</code>, <code>RevisionId</code>, <code>RevisionSetId</code>, <code>FileId</code>, FileHead, parent <code>RevisionId</code>, <code>ContentRef</code>) whose <em>semantics are frozen</em> by rules ID-01 to ID-62 while their binary encoding is not; object framing; canonical collection ordering keys; version field identity, encoding, position and values; digest encoding and per-domain algorithm identifiers; unknown-field, unknown-record, trailing-byte, and padding behavior; duplicate-member semantics; index key and value encodings, checksums, and index versions; derived unit field encoding and derived payload hash encoding; content representation mode declaration site and encoding; Vertical representation descriptor fields and unallocated representation identity/version registry values; checkpoint cadence guidance; error identifiers and error encoding; compression algorithm values; and all expected hash fixtures.

**Not blocked (normative today):** hash-independence of identity and recovery, the three hash working modes and mode isolation, index-free recovery via mandatory framing, derived-artifact deletion safety, the `NONE` compression baseline, identity-before-encryption, `verification unavailable` distinct from `corrupt`, ContainerIntegrityHash covering canonical records only, the existence of exactly two content representation modes with the feature-parity invariant, the HORIZONTAL full-copy persistence rule, the VERTICAL deterministic-reconstruction rule, cross-mode recovery equivalence, and the rule that neither mode may make a hash a precondition of semantic recoverability.

## Test vectors

Vector identity and expected semantic results are specified in Section 43 (V01–V29). V13–V18 cover availability and error-state separation: V13 hash implementation unavailable (`recovered; verification unavailable`, not corrupt), V14 working-mode change leaves canonical core bytes and semantic identity unchanged, V15 container declared under working mode `None` (`decoded`/`recovered`; verification unavailable), V16 optional transform with unavailable codec (`unsupported transform`, not corrupt), V17 unsupported mandatory version (version error, no decode attempt), V18 encrypted container with key unavailable (`access or decryption failure`, not integrity mismatch). V19–V29 cover VSN Mode per mode (Section 11): ENTERPRISE V19 single-file edit stored as a pre-materialized full copy and recovered without Computation Unit reconstruction, a diff, a patch, or a previous revision; V20 multiple and branching Enterprise revisions each independently represented; V21 Enterprise with every derived artifact deleted; V22 Enterprise with working mode `None` and no hash available (verification unavailable); V23 MODERN deduplicated, shared, delta/diff, and compressed representation reconstructed deterministically by the Computation Unit; V24 MODERN with derived indexes and caches deleted; V25 MODERN unsupported representation algorithm (unsupported transform, not corrupt); V26 cross-mode equivalence — the same logical file history written MODERN and ENTERPRISE recovers to the same semantic state and identical logical contents, with physical-byte equality explicitly not required; V27 physical relocation or re-layout in both modes; V28 deletion of canonical recovery data (Enterprise pre-materialized content or Modern representation data) reported as missing object or integrity failure, never a cache eviction; V29 re-materialization between representations without semantic change. Expected bytes and hashes remain **Implementation Pending** until an executable canonical encoder exists; no hash fixture may be published from an unexecuted encoder.



