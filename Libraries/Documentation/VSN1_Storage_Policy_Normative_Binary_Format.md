# VSN Normative Binary Format — REC_STORAGE_POLICY (0x0009)

**Status:** Draft — Phase 2 Protocol Contract  
**Date:** 2026-10-08  
**Authority:** BRP Step 3 (frozen protocol semantics) + GR-28 (record type allocation)

---

## 1. Record Type: REC_STORAGE_POLICY = 0x0009

### Definition

```
RecordType = 0x0009  (decimal 9)
Name       = "StoragePolicy"
FieldID    = FID_STORAGE_POLICY = 0x0901
Value      = u8, range [1..4]
Status     = ACTIVE / NORMATIVE
Replaces   = REC_MODE_DECLARATION (0x0007) [OBSOLETE]
```

### Purpose

The `REC_STORAGE_POLICY` record carries the **authoritative** storage policy value directly in the VSN wire format. It is the normative classification of a container's storage optimization profile. This is not metadata, not a hint, and not inferred -- it is explicitly encoded and validated on every read.
### Wire Encoding

```
+--------+----------+--------+-------+---------+
| Offset | Size     | Field  | Value | Notes   |
+--------+----------+--------+-------+---------+
| +0     | u16be    | type   | 0x0009| Fixed   |
| +2     | varint   | length | N     | Payload length (=3) |
| +2+N   | u16be    | field  | 0x0901| FID_STORAGE_POLICY  |
|        | varint   | len    | 1     | value length        |
|        | u8       | value  | [1..4]| Storage policy      |
+--------+----------+--------+-------+---------+
Total payload: exactly 3 bytes (field=0x0901, len=1, value=u8)
```

### Field Details

| Item           | Value         | Encoding     | Constraint                    |
|----------------|---------------|--------------|-------------------------------|
| Record type    | `0x0009`      | u16be        | Fixed                         |
| FID            | `0x0901`      | u16be        | Fixed (per GR-17 allocation)  |
| Value length   | `1`           | varint       | Always 1                      |
| Value          | `1..4`        | u8           | Must be in {1,2,3,4}          |

### Valid Values

| Numeric Value | Name              | Description                             |
|--------------|-------------------|-----------------------------------------|
| 1            | HIGHLY_VERTICAL   | Maximum storage-effort optimization     |
| 2            | VERTICAL          | Bounded storage-effort optimization     |
| 3            | HORIZONTAL        | Low storage-effort optimization         |
| 4            | HIGHLY_HORIZONTAL | Minimal optimization effort             |

### Invalid Values

| Value   | Error Category      | Description                                   |
|---------|--------------------|-----------------------------------------------|
| 0       | INVALID_STORAGE_POLICY | Zero is not a valid policy                |
| 5..255  | INVALID_STORAGE_POLICY | Outside known range; future extension-safe check required |
| missing FID | MALFORMED_RECORD | No FID_STORAGE_POLICY field in record         |

---

## 2. Record Placement and Ordering

`REC_STORAGE_POLICY` is a header-level metadata record in the canonical records section:

1. **After** the RecordsEnd header marker (FID 0x0000)
2. **Before** ContentObject records (describes how content was stored)
3. **Before or alongside** FileIdentity/Revision records (structural context)
4. **Before** CommitMarker (policy declared before commitment)

### Uniqueness Rules

- **Exactly one** `REC_STORAGE_POLICY` record is valid per container.
- **Duplicate** records are **invalid**. The writer MUST emit exactly one.
- Zero occurrences: container is structurally incomplete for canonical writers.

### Unknown Record Handling (GR-29..GR-33)

A reader that does not understand `0x0009` MUST skip it by declared length and preserve it byte-for-byte. However, Storage Policy is the authoritative classification — new canonical containers must include this record.

---

## 3. Obsolete: REC_MODE_DECLARATION = 0x0007

```
RecordType = 0x0007
Name       = "ModeDeclaration"
Status     = OBSOLETE / NO LONGER EMITTED BY CANONICAL WRITERS
ReplacedBy = REC_STORAGE_POLICY (0x0009)
```
---

## 6. Validation Rules

### Writer Must Ensure

1. Exactly one `REC_STORAGE_POLICY` record (0x0009)
2. Exactly one FID_STORAGE_POLICY field (0x0901) within it
3. Value is u8 in range [1..4]
4. Record appears before CommitMarker and ContentObject records

### Reader Must Enforce

1. Reject container with zero `REC_STORAGE_POLICY` records (mandatory for canonical)
2. Reject container with multiple `REC_STORAGE_POLICY` records
3. Reject if FID_STORAGE_POLICY field is missing from the record
4. Reject if value < 1 or value > 4
5. Warn on legacy `REC_MODE_DECLARATION` in new-format containers

---

## 7. Field ID Allocation Justification (GR-17)

FID `0x0901` follows the existing allocation convention:

- High byte `0x09` corresponds to record type `0x0009`
- Low byte `0x01` is the first/only field in this record
- Consistent with other single-field records (e.g., FID_MODE = 0x0701 for REC_MODE_DECLARATION)

---

## 8. Negative Test Cases

### Test Case: Storage Policy value 0

Encoded bytes after magic header:
```
00 09 03 09 01 01 00    (type=0x0009, len=3, fid=0x0901, val_len=1, value=0)
```
Expected outcome: **INVALID_STORAGE_POLICY**

### Test Case: Storage Policy value 5

Encoded bytes after magic header:
```
00 09 03 09 01 01 05    (type=0x0009, len=3, fid=0x0901, val_len=1, value=5)
```
Expected outcome: **INVALID_STORAGE_POLICY**

### Test Case: Malformed FID (wrong field ID)

Encoded bytes after magic header:
```
00 09 03 09 02 01 01    (type=0x0009, len=3, fid=0x0902 [wrong], val_len=1, value=1)
```
Expected outcome: **MALFORMED_RECORD** (missing FID_STORAGE_POLICY field)

### Test Case: Truncated field (length says 2 bytes but only 1 present)

Encoded bytes after magic header:
```
00 09 03 09 01 02        (type=0x0009, len=3, fid=0x0901, val_len=2, but only 01 byte)
```
Expected outcome: **TRUNCATED_CONTAINER**

### Test Case: Truncated record (length says 5 bytes but only 3 payload bytes)

Encoded bytes after magic header:
```
00 09 05 09 01 01        (type=0x0009, len=5, fid=0x0901, val_len=1, value=1, but only 3 payload bytes)
```
Expected outcome: **TRUNCATED_CONTAINER**

### Test Case: Duplicate StoragePolicy record

Two REC_STORAGE_POLICY (0x0009) records in the same container.
Expected outcome: **INVALID_STORAGE_POLICY** (duplicate record)

### Test Case: Missing StoragePolicy (canonical writer output)

Container with no REC_STORAGE_POLICY (0x0009) record.
Expected outcome: **MISSING_STORAGE_POLICY** for canonical containers

### Test Case: Obsolete ModeDeclaration in new-format container

Container contains both REC_MODE_DECLARATION (0x0007) and valid REC_STORAGE_POLICY (0x0009).
Expected outcome: **WARN** on legacy ModeDeclaration; use StoragePolicy as authoritative.

**Reader behavior:**
- Must parse legacy containers with ModeDeclaration for backward compatibility
- MUST NOT emit ModeDeclaration in new canonical containers
- Should warn on obsolete ModeDeclaration in new-format containers

---

## 4. Wire-Mode Separation from Storage Policy

**CRITICAL INVARIANT:** The four storage policies are **NOT mapped to two wire modes**. That architecture is cancelled.

```
Storage Policy values = {1, 2, 3, 4} -- DIRECT classification on wire
No mapping: HIGHLY_VERTICAL -> MODERN/0x01
No mapping: VERTICAL -> MODERN/0x01
No mapping: HORIZONTAL -> ENTERPRISE/0x02
No mapping: HIGHLY_HORIZONTAL -> ENTERPRISE/0x02
```

---

## 5. Example Encoded Record (HIGHLY_VERTICAL = 1)

Using GR-08 big-endian + minimal uvarint:

```
Bytes: 00 09        (record type = 0x0009, big-endian u16)
       03           (payload length = 3, varint)
       09 01        (field ID = 0x0901, big-endian u16)
       01           (value length = 1, varint)
       01           (value = 1, u8 = HIGHLY_VERTICAL)

Full hex: 00 09 03 09 01 01 01
```
