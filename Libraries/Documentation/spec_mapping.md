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

Implemented for record types `0x0001..0x0008` and their frozen fields in
`constants.py` / `container.py`. FileIdentity.FileId = `0x0101` (normative
field allocation). Unknown records/fields are skipped by declared length
(GR-29..GR-33). FieldId `0x0001` in a FileIdentity record is NOT treated as
the canonical FileId field.

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
