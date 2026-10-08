# VSN-1 normative rule → Library → Conformance mapping

Single source of truth for which frozen rule each implementation behavior
satisfies, and which conformance test exercises it. The authoritative
specification is `generate_docs.py` at the repository root; nothing here
duplicates the normative text.

## Binary grammar (GR-01..GR-53)

| Normative rule | Library behavior | Test |
|---|---|---|
| GR-01 signature "VSN-" | `primitives.MAGIC`, `container.parse` | negative `test_bad_magic` |
| GR-08 big-endian | `primitives.put_u16/32/64` | frozen vectors |
| GR-21 uvarint minimal LEB128 | `reader.read_uvarint` | `PrimitiveTests` |
| GR-24 non-minimal rejection | `reader._check_minimal` | `test_uvarint_rejects_nonminimal` |
| GR-25 overflow | `reader.read_uvarint` 10th-byte | golden uvarint |
| GR-47 truncation | `reader.Truncated` | `test_truncated_recovery` |

## Records (GR-28) and fields (GR-17)

### Record Type Registry (GR-28)

| ID | Name | Status | Description |
|----|------|--------|-------------|
| 0x0000 | END_OF_RECORDS | FROZEN | End-of-records marker (GR-11) |
| 0x0001 | FILE_IDENTITY | FROZEN | File identity record |
| 0x0002 | REVISION | FROZEN | Revision record |
| 0x0003 | REVISION_SET | FROZEN | Revision set record |
| 0x0004 | FILE_HEAD | FROZEN | File head record |
| 0x0005 | CONTENT_OBJECT | FROZEN | Content object record |
| 0x0006 | COMMIT_MARKER | FROZEN | Commit marker / acceptance record |
| 0x0007 | MODE_DECLARATION | **OBSOLETE** | Deprecated, no longer emitted by canonical writers |
| 0x0008 | REPRESENTATION_DESCRIPTOR | FROZEN | Representation descriptor (DIRECT/EXTENTS) |
| **0x0009** | **STORAGE_POLICY** | **ACTIVE** | **New: authoritative storage policy (direct on wire)** |
| 0x8000..0xFFFE | EXTENSION | PLANNED | Extension range |
| 0xFFFF | RESERVED | FROZEN | Reserved |

### Field ID Registry (GR-17)

| ID | Name | Record | Status | Description |
|----|------|--------|--------|-------------|
| 0x0000 | RECORDS_END | - | FROZEN | End-of-header marker |
| **0x0901** | **FID_STORAGE_POLICY** | **0x0009** | **ACTIVE** | **StoragePolicy field (u8 value 1..4)** |
| 0x0701 | FID_MODE | 0x0007 | OBSOLETE | ModeDeclaration field ID (deprecated) |
| 0x0101 | FID_FILE_ID | 0x0001 | FROZEN | FileIdentity.FileId (normative field allocation) |
| 0x0201..0x0211 | REV_FID_* | 0x0002 | FROZEN | Revision record fields |
| 0x0301..0x0310 | RSET_FID_* | 0x0003 | FROZEN | Revision set fields |
| 0x0401..0x0410 | HEAD_FID_* | 0x0004 | FROZEN | File head fields |
| 0x0501..0x0511 | OBJ_FID_* | 0x0005 | FROZEN | Content object fields |
| 0x0601..0x0610 | COMMIT_FID_* | 0x0006 | FROZEN | Commit marker fields |
| 0x0801..0x0810 | REP_FID_* | 0x0008 | FROZEN | Representation descriptor fields |

Unknown records/fields are skipped by declared length (GR-29..GR-33). FieldId `0x0001` in a FileIdentity record is NOT treated as the canonical FileId field.

## Representations (DR-0..DR-12)

| Rule | Behavior | Test |
|---|---|---|
| DR-0 object header (u16be identity + uvarint version) | `representations.parse_object_header` | all vectors |
| DIRECT-1 baseline | `representations.materialize_direct` | DIRECT-01..03 |
| EXTENTS-1 operation collection | `representations.materialize_extents` | EXT-01, EXT-02/03 |
| COPY/LITERAL, cycle rejection | `_apply_operation` | EXT-02/03 |

## Recovery (RC-01..RC-45)

`recovery.recover` selects the highest-Generation CommitMarker; indexes and
caches are never consulted.

## Error registry (VR-28, VR-29)

`errors.ERRORS` maps the frozen identifiers; no new protocol IDs added.
`ResourceRefusal` is reader-local and distinct from canonical invalidity.
