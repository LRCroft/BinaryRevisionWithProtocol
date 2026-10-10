# VSN-1 Canonical Library API Surface (Normative — All 31 Languages)

**Status:** Normative reference. Defines the ONE library API every VSN-1 language
implementation must expose.
**Rule:** Every implementation MUST provide every operation below with identical
semantics. Spelling follows each language's native convention (snake_case /
camelCase / …); the *set of operations* and their *behavior* are identical.
**Reference implementation:** `Libraries/C/vsn.h` (C) / `Libraries/Python/vsn/` (Python).

A language is **API-Complete** only when all operations in sections 1–14 are
present, each backed by a real implementation (no stub that always returns a
constant), and the library is importable/copy-ready as a single entry point.

## 1. Protocol layer (free functions)
| # | Operation | Neutral signature | Returns |
|---|-----------|-------------------|---------|
| P1 | `parse` | `parse(data) -> Container` | parsed container |
| P2 | `encode` | `encode(container) -> bytes` | canonical bytes |
| P3 | `materialize` | `materialize(container, serial) -> bytes` | logical content |
| P4 | `validate` | `validate(data, level) -> status` | ok / error code |
| P5 | `recover` | `recover(data) -> status` | recovered state |

## 2. Store lifecycle
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| S1 | `create` | `create(mode) -> Store` |
| S2 | `createWithPolicy` | `createWithPolicy(policy) -> Store` |
| S3 | `open` | `open(data) -> Store` |
| S4 | `close` | `close(store) -> void` |
| S5 | `commit` | `commit(store) -> bytes` |
| S6 | `reopen` | `reopen(store, data) -> void` |
| S7 | `toBytes` | `toBytes(store) -> bytes` (no generation bump) |

## 3. File API
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| F1 | `createFile` | `createFile(store, path, content) -> FileId` |
| F2 | `readFile` | `readFile(store, fid) -> bytes` |
| F3 | `writeFile` | `writeFile(store, fid, content)` |
| F4 | `deleteFile` | `deleteFile(store, fid)` |
| F5 | `renameFile` | `renameFile(store, fid, newPath)` |
| F6 | `listFiles` | `listFiles(store) -> [FileId]` |
| F7 | `fileExists` | `fileExists(store, fid) -> bool` |
| F8 | `getFileId` | `getFileId(store, path) -> FileId | null` |

## 4. Revision API
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| R1 | `listRevisions` | `listRevisions(store, fid) -> [RevisionId]` |
| R2 | `getCurrentRevision` | `getCurrentRevision(store, fid) -> RevisionId` |
| R3 | `checkoutRevision` | `checkoutRevision(store, fid, rev) -> bytes` |
| R4 | `restoreRevision` | `restoreRevision(store, fid, rev)` |

## 5. History retention
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| L1 | `limitCleanup` | `limitCleanup(store, fid, limit) -> [removed RevisionId]` |

## 6. Object API
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| O1 | `listObjects` | `listObjects(store) -> [ObjectSerial]` |
| O2 | `getObjectInfo` | `getObjectInfo(store, serial) -> info` |
| O3 | `materializeObject` | `materializeObject(store, serial) -> bytes` |

## 7. Transactions
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| T1 | `beginTransaction` | `beginTransaction(store)` |
| T2 | `stageCreate/Update/Delete` | stage one change (create/update/delete) |
| T3 | `rollback` | `rollback(store)` |
| T4 | `commit` | `commit(store)` — applies staged changes, bumps generation |

## 8. Diagnostics
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| D1 | `diagnostics` | `diagnostics(store) -> [Diagnostic]` (empty == healthy) |

## 9. Diff (derived, never canonical)
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| G1 | `diffFiles` | `diffFiles(a, b) -> FileDiff{added,removed,modified,unchanged}` |
| G2 | `diffObjects` | `diffObjects(a, b) -> ObjectDiff` |

## 10. Merge
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| M1 | `threeWayMerge` | `threeWayMerge(base, ours, theirs) -> MergeResult` |
| M2 | `resolveConflict` | `resolveConflict(result, path, content)` |

## 11. Import / Export
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| I1 | `importBytes` | `importBytes(store, path, content) -> FileId` |
| I2 | `exportBytes` | `exportBytes(store, fid) -> bytes` |

## 12. Streaming (large content, no full in-memory buffer)
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| X1 | `writeLargeObject` | `writeLargeObject(store, path, content) -> FileId` |
| X2 | `streamExport` | `streamExport(store, fid, sink) -> bytes` (chunked) |

## 13. Integrity
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| N1 | `integrityVerify` | `integrityVerify(store|data) -> bool` |

## 14. Storage management (derived stats)
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| A1 | `storageStats` | `storageStats(store) -> {files, revisions, objects, generation}` |

## 15. Builder
| # | Operation | Neutral signature |
|---|-----------|-------------------|
| B1 | `newBuilder` | `newBuilder(mode) -> Store` |
| B2 | `build` | `build(store) -> bytes` |

---

## Naming conventions (identical semantics, native spelling)
- snake_case languages (C, Python, Ruby, R, COBOL, Fortran, Erlang, OCaml, Perl,
  Elixir, Rust, Go-internal, Scala-optional, COBOL): `create_file`, `list_revisions`,
  `limit_cleanup`, `three_way_merge`, …
- camelCase languages (C#, C++, Java, Kotlin, JS/TS, Swift, Dart, Julia, PHP,
  Crystal, D, Zig): `createFile`, `listRevisions`, `limitCleanup`, `threeWayMerge`, …

## Conformance tie-in
- Each operation maps to one of the 19 capability groups that the conformance
  runner (`Libraries/Conformance/run_conformance.py`) verifies via `CAP <n> PASS`.
- **API-Complete == 19/19 caps PASS + all operations above present + single entry point.**
