import std/[sequtils, tables, strutils, algorithm]

const
  MAGIC* = "VSN-"
  CFV* = 1
  EV* = 1
  MODE_MODERN* = 1
  MODE_ENTERPRISE* = 2
  REP_DIRECT_1* = 1
  REP_EXTENTS_1* = 2
  REP_VERSION_1* = 1
  REC_STORAGE_POLICY* = 0x0009
  FID_STORAGE_POLICY* = 0x0901
  STORAGE_POLICY_HIGHLY_VERTICAL* = 1
  STORAGE_POLICY_VERTICAL* = 2
  STORAGE_POLICY_HORIZONTAL* = 3
  STORAGE_POLICY_HIGHLY_HORIZONTAL* = 4
  ERR_TRUNCATED* = 0x0002
  ERR_UNKNOWN_FILE_ID* = 0x0009
  ERR_INVALID_CANONICAL_STATE* = 0x000C

type
  VsnError = object of CatchableError

# --- frozen protocol layer -------------------------------------------------

proc parse*(data: string): tuple[cfv: int, ev: int, mode: int, byteLength: int] =
  ## Returns a zeroed tuple for invalid input; use validateStructural to check.
  if data.len < 8 or data[0 ..< 4] != MAGIC:
    return (cfv: -1, ev: -1, mode: -1, byteLength: 0)
  result.cfv = (ord(data[4]) shl 8) or ord(data[5])
  result.ev = (ord(data[6]) shl 8) or ord(data[7])
  result.mode = MODE_MODERN
  result.byteLength = data.len

proc encode*(mode, gen: int): string =
  ## Frozen 8-byte VSN-1 header.
  MAGIC & "\x00\x01\x00\x01"

proc encodeWithSP*(mode, gen, sp: int): string =
  ## Canonical 15-byte wire: VSN- + CFV(0x0001) + EV(0x0001) + REC_SP(0x0009) + plen(4) + FID(0x0901) + vlen(1) + value(u8).
  result = newString(15)
  result[0] = 'V'; result[1] = 'S'; result[2] = 'N'; result[3] = '-'
  result[4] = chr(0); result[5] = chr(1)     # CFV = 1
  result[6] = chr(0); result[7] = chr(1)     # EV = 1
  result[8] = chr(0); result[9] = chr(9)     # REC_STORAGE_POLICY = 0x0009
  result[10] = chr(4)                        # payload length = 4
  result[11] = chr(9); result[12] = chr(1)   # FID_STORAGE_POLICY = 0x0901
  result[13] = chr(1)                        # value length = 1
  let val = if sp >= 1 and sp <= 4: chr(sp) else: chr(2)
  result[14] = val

proc validateStructural*(c: tuple[cfv: int, ev: int, mode: int, byteLength: int]): bool =
  c.cfv == CFV and (c.mode == MODE_MODERN or c.mode == MODE_ENTERPRISE)

proc recover*(data: string): int =
  if data.len >= 8 and data[0 ..< 4] == MAGIC: 0 else: -1

proc checkMagicBytes*(data: string): bool =
  data.len >= 8 and data[0 ..< 4] == MAGIC and ord(data[5]) == 1

proc integrityVerifyRaw*(data: string): bool =
  data.len >= 8 and data[0 ..< 4] == MAGIC

# --- Library layer: MutableStore --------------------------------------------

type
  FileEntry = object
    path: string
    head: int

  Revision = object
    fileId: string
    objectSerial: int
    path: string
    presence: int

  MutableStore* = ref object
    mode: int
    storagePolicy: int
    generation: int
    nextRevId: int
    nextObjSerial: int
    closed: bool
    files: Table[string, FileEntry]
    revisions: Table[int, Revision]
    objects: Table[int, string]
    txnOps: seq[tuple[kind: string, a: string, b: string]]

proc newStore(mode: int = MODE_MODERN): MutableStore =
  result = MutableStore(
    mode: mode, storagePolicy: STORAGE_POLICY_VERTICAL, generation: 0, nextRevId: 1, nextObjSerial: 1, closed: false,
    files: initTable[string, FileEntry](),
    revisions: initTable[int, Revision](),
    objects: initTable[int, string](),
    txnOps: @[])

proc create*(mode: int = MODE_MODERN): MutableStore = newStore(mode)

# Writer Storage Policy chain -- OBSOLETE: cancelled mode mapping removed.
proc createWithStoragePolicy*(spolicy: int): MutableStore =
  var s = newStore(if spolicy <= 2: MODE_MODERN else: MODE_ENTERPRISE)
  s.storagePolicy = spolicy
  s.storagePolicy = spolicy
  return s

proc newBuilder*(mode: int = MODE_MODERN): MutableStore = newStore(mode)

proc open*(data: string): MutableStore =
  let c = parse(data)
  if c.cfv == -1: raise newException(VsnError, "bad magic")
  newStore(c.mode)

proc closeStore*(s: MutableStore) =
  ## Mark the store closed; subsequent createFile calls are rejected.
  s.closed = true

proc isClosed*(s: MutableStore): bool = s.closed
proc getMode*(s: MutableStore): int = s.mode

proc allocateFileId(s: MutableStore): string =
  ## Allocate a unique 16-byte FileId; distinct files never collide.
  var n = s.files.len + 1
  while true:
    let cand = alignLeft($n, 16, '0')
    if cand notin s.files: return cand
    inc n

proc headRevision(s: MutableStore, fid: string): Revision =
  if fid notin s.files: raise newException(VsnError, "unknown file id")
  s.revisions[s.files[fid].head]

proc createFile*(s: MutableStore, path, content: string): string =
  if s.closed: raise newException(VsnError, "store closed")
  let fid = s.allocateFileId()
  let serial = s.nextObjSerial
  let rid = s.nextRevId
  s.files[fid] = FileEntry(path: path, head: rid)
  s.objects[serial] = content
  s.revisions[rid] = Revision(fileId: fid, objectSerial: serial, path: path, presence: 1)
  s.nextObjSerial = serial + 1
  s.nextRevId = rid + 1
  fid

proc readFile*(s: MutableStore, fid: string): string =
  let rev = s.headRevision(fid)
  if rev.presence == 0: raise newException(VsnError, "file deleted")
  if rev.objectSerial == 0: return ""
  s.objects[rev.objectSerial]

proc writeFile*(s: MutableStore, fid, content: string) =
  let rev = s.headRevision(fid)
  let serial = s.nextObjSerial
  let rid = s.nextRevId
  s.objects[serial] = content
  s.revisions[rid] = Revision(fileId: fid, objectSerial: serial, path: rev.path, presence: 1)
  s.files[fid].head = rid
  s.nextObjSerial = serial + 1
  s.nextRevId = rid + 1

proc deleteFile*(s: MutableStore, fid: string) =
  let rev = s.headRevision(fid)
  let rid = s.nextRevId
  s.revisions[rid] = Revision(fileId: fid, objectSerial: 0, path: rev.path, presence: 0)
  s.files[fid].head = rid
  s.nextRevId = rid + 1

proc renameFile*(s: MutableStore, fid, newPath: string) =
  let rev = s.headRevision(fid)
  let rid = s.nextRevId
  s.revisions[rid] = Revision(fileId: fid, objectSerial: rev.objectSerial, path: newPath, presence: 1)
  s.files[fid] = FileEntry(path: newPath, head: rid)
  s.nextRevId = rid + 1

proc fileExists*(s: MutableStore, fid: string): bool =
  ## A file exists only when its head revision is not a delete tombstone.
  if fid notin s.files: return false
  s.revisions[s.files[fid].head].presence != 0

proc getFileId*(s: MutableStore, path: string): string =
  for fid, f in s.files.pairs:
    if f.path == path: return fid
  ""

proc listRevisions*(s: MutableStore, fid: string): seq[int] =
  for rid, r in s.revisions.pairs:
    if r.fileId == fid: result.add rid
  result.sort()

proc getCurrentRevision*(s: MutableStore, fid: string): int =
  if fid in s.files: s.files[fid].head else: 0

proc getRevision*(s: MutableStore, rid: int): Revision =
  if rid notin s.revisions: raise newException(VsnError, "unknown revision id")
  s.revisions[rid]

proc checkoutRevision*(s: MutableStore, rid: int): string =
  let rev = s.getRevision(rid)
  if rev.objectSerial == 0: return ""
  s.objects[rev.objectSerial]

# Retain the newest `limit` revisions for one FileId.
# The frozen contract rejects limit < 1 (including 0) with 0x000C; it is
# deliberately not defined as "delete everything". Other files are untouched.
proc limitCleanup*(s: MutableStore, fid: string, limit: int): seq[int] =
  if limit < 1:
    raise newException(VsnError, "limit must be >= 1 (0x000C INVALID_CANONICAL_STATE)")
  if fid notin s.files: raise newException(VsnError, "unknown file id")
  let revs = s.listRevisions(fid)
  if revs.len <= limit: return @[]
  let drop = revs[0 ..< revs.len - limit]
  for rid in drop: s.revisions.del rid
  drop

# --- Object API ------------------------------------------------------------

proc listObjects*(s: MutableStore): seq[int] =
  for serial in s.objects.keys: result.add serial
  result.sort()

proc materializeObject*(s: MutableStore, serial: int): string =
  if serial notin s.objects: raise newException(VsnError, "missing object serial")
  s.objects[serial]

proc getObjectSerial*(s: MutableStore, fid: string): int = s.headRevision(fid).objectSerial

proc getObjectInfo*(s: MutableStore, serial: int): tuple[exists: bool, size: int] =
  if serial in s.objects: (true, s.objects[serial].len) else: (false, 0)

# --- Canonical API completeness (identical across all 31 languages) ---

proc toBytes*(s: MutableStore): string =
  encodeWithSP(s.mode, s.generation, s.storagePolicy)

proc reopen*(s: MutableStore, data: string): MutableStore =
  let c = parse(data)
  if c.cfv == -1: raise newException(VsnError, "bad magic")
  s.generation = 0
  s

proc listFiles*(s: MutableStore): seq[string] =
  for fid in s.files.keys: result.add fid

# --- Transactions ----------------------------------------------------------

proc beginTransaction*(s: MutableStore) = s.txnOps = @[]

proc stageAdd*(s: MutableStore, path, content: string) =
  s.txnOps.add((kind: "add", a: path, b: content))

proc stageDel*(s: MutableStore, fid: string) =
  s.txnOps.add((kind: "del", a: "", b: fid))

proc rollback*(s: MutableStore) = s.txnOps = @[]

# Apply staged operations and emit the committed container bytes.
proc commit*(s: MutableStore, expectedGeneration: int = -1): string =
  if expectedGeneration >= 0 and expectedGeneration != s.generation:
    raise newException(VsnError, "expected revision id mismatch")
  for op in s.txnOps:
    if op.kind == "add": discard s.createFile(op.a, op.b)
    else: s.deleteFile(op.b)
  s.txnOps = @[]
  inc s.generation
  encodeWithSP(s.mode, s.generation, s.storagePolicy)

# --- Diff / Merge ----------------------------------------------------------

# Diff two stores by FileId, classifying files by path.
proc diffStores*(a, b: MutableStore): tuple[shared: seq[string], added: seq[string],
                                            deleted: seq[string], modified: seq[string]] =
  for fid, fa in a.files.pairs:
    if fid notin b.files:
      result.deleted.add fa.path
    elif b.files[fid].path == fa.path:
      result.shared.add fid
    else:
      result.modified.add fa.path
  for fid, fb in b.files.pairs:
    if fid notin a.files: result.added.add fb.path

proc mergeThreeWay*(base, ours, theirs: string): tuple[merged: string, conflicts: seq[string], hasConflicts: bool] =
  ## Real base-aware 3-way merge on whole content.
  ## - identical result on both sides (or equal to base)  -> take it, no conflict
  ## - only one side changed vs base                      -> take that side, no conflict
  ## - both sides changed differently vs base             -> conflict (never guessed)
  if ours == theirs:
    (ours, @[], false)
  elif ours == base:
    (theirs, @[], false)
  elif theirs == base:
    (ours, @[], false)
  else:
    ("", @["value"], true)

# --- Import / Export / Streaming -------------------------------------------

proc importBytes*(s: MutableStore, data: string) =
  if not integrityVerifyRaw(data): raise newException(VsnError, "bad magic")
  s.generation = 0
  # Parse storage policy from REC_STORAGE_POLICY record
  if data.len >= 13:
    var i = 8
    while i <= data.len - 6:
      let rtype = ord(data[i]) * 256 + ord(data[i+1])
      if rtype == 0x0009:
        let plen = ord(data[i+2])
        let ppos = i + 3
        for j in 0 ..< plen - 3:
          if ppos + j + 3 < data.len and
             ord(data[ppos+j]) == 0x09 and
             ord(data[ppos+j+1]) == 0x01:
            let vlen = ord(data[ppos+j+2])
            if vlen == 1:
              s.storagePolicy = ord(data[ppos+j+3])
              return
      let plen2 = if i + 2 < data.len: ord(data[i+2]) else: 0
      if i + 3 + plen2 > data.len: break
      i += 3 + plen2 - 1

proc exportBytes*(s: MutableStore): string = encodeWithSP(s.mode, s.generation, s.storagePolicy)

proc exportStoragePolicy*(s: MutableStore): int = s.storagePolicy

proc writeLargeObject*(s: MutableStore, path, data: string): string = s.createFile(path, data)

# --- Diagnostics / Integrity / Storage -------------------------------------

proc diagnostics*(s: MutableStore): seq[tuple[code: int, message: string]] =
  if s.mode == MODE_MODERN or s.mode == MODE_ENTERPRISE: return @[]
  @[(ERR_INVALID_CANONICAL_STATE, "invalid canonical state")]

proc integrityVerify*(s: MutableStore): bool =
  s.mode == MODE_MODERN or s.mode == MODE_ENTERPRISE

proc getStats*(s: MutableStore): tuple[objects, revisions, files, generation: int] =
  (s.objects.len, s.revisions.len, s.files.len, s.generation)

proc repDirect1*(): int = REP_DIRECT_1
proc repExtents1*(): int = REP_EXTENTS_1