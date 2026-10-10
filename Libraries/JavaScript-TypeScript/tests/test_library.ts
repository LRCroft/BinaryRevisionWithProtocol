// VSN library workflow tests: container lifecycle, file/revision/object API,
// transactions, representations, diff, merge, import/export, streaming,
// diagnostics, integrity, derived-data rebuild, and recovery after derived loss.
import * as fs from "fs";
import * as path from "path";
import { Readable, Writable } from "stream";
import { test, run, expectThrow, eq, eqBytes } from "./harness.js";
import {
  create, VsnStore, VsnContainer, VsnError, Transaction, StorageManager,
  validate, validateContainer, recoverContainer, recover, inspectContainer, open,
  importFile, exportFile, io_ops, diff, merge, verifyIntegrity, canonicalHash,
  ContainerBuilder, extents1Descriptor, literalOperation, copyOperation,
  parseObjectHeader, encode, parse, putUvarint,
  MODE_MODERN, MODE_ENTERPRISE, DELETED, REP_DIRECT_1, REP_EXTENTS_1,
  FID_FILE_ID, FID_OBJECT_SERIAL, FID_OBJECT_SIZE,
  REC_CONTENT_OBJECT, REC_FILE_HEAD, FID_HEAD_REV_ID, REC_REVISION, FID_REV_ID,
} from "../src/index.js";

const TV_DIR = path.resolve("..", "TestVectors");
function loadVector(name: string): Buffer { return fs.readFileSync(path.join(TV_DIR, name + ".vsn")); }

// --- Container lifecycle ---

test("container create/open/close/reopen", () => {
  const store = create();
  eq(store.mode, MODE_MODERN, "mode");
  const fid = store.createFile("a.txt", Buffer.from("hello"));
  const data = store.commit();
  store.close();
  eq(store.isClosed, true, "closed");
  eq(expectThrow(() => store.listFiles()) instanceof VsnError, true, "closed throws");

  const reopened = VsnStore.open(data);
  eqBytes(reopened.readFile(fid), Buffer.from("hello"), "content");
  reopened.reopen();
  eqBytes(reopened.readFile(fid), Buffer.from("hello"), "content after reopen");
});

test("inspect reports container metadata", () => {
  const store = create();
  store.createFile("a.txt", Buffer.from("x"));
  store.createFile("b.txt", Buffer.from("y"));
  const info = inspectContainer(store);
  eq(info.fileCount, 2, "files");
  eq(info.objectCount, 2, "objects");
  eq(info.revisionCount, 2, "revisions");
});

test("validate exposes Structural/Semantic/Recovery/Content/Full", () => {
  const store = create();
  const fid = store.createFile("a.txt", Buffer.from("data"));
  const data = store.commit();
  for (const level of ["Structural", "Semantic", "Recovery", "Content", "Full"] as const)
    validate(data, level);
  eq(validateContainer(data, "Full").length, 0, "no diagnostics");
  const bad = expectThrow(() => validate(data.subarray(0, 8), "Structural"));
  eq((bad as VsnError).code, 0x0002, "truncated");
  eq(validateContainer(data.subarray(0, 8), "Full").length, 1, "one diagnostic");
});

// Content level must REJECT a dependency cycle: Structural and Semantic both pass
// it, so only Content-level materialization can catch it. Proves it is load-bearing.
test("Content validation rejects a dependency cycle", () => {
  const one = extents1Descriptor([copyOperation(2, 0, 4)]);
  const two = extents1Descriptor([copyOperation(1, 0, 4)]);
  const b = new ContainerBuilder(MODE_MODERN);
  b.addObjectRaw(one, 1);
  b.addObjectRaw(two, 2);
  const data = b.build(1);
  validate(data, "Structural");
  validate(data, "Semantic");
  eq((expectThrow(() => validate(data, "Content")) as VsnError).code, 0x000C, "cycle");
  eq((expectThrow(() => validate(data, "Full")) as VsnError).code, 0x000C, "full");
  const diags = validateContainer(data, "Full");
  eq(diags.length, 1, "one diagnostic");
  eq(diags[0].severity, "error", "severity");
  eq(diags[0].operation, "Content", "operation context");
});

test("Content validation rejects a missing ObjectSerial dependency", () => {
  const dangling = extents1Descriptor([copyOperation(99, 0, 4)]);
  const b = new ContainerBuilder(MODE_MODERN);
  b.addObjectRaw(dangling, 1);
  const data = b.build(1);
  eq((expectThrow(() => validate(data, "Content")) as VsnError).code, 0x0008, "missing object");
});

// --- 0x0511 declared size (SR-27 / DR-6) -----------------------------------
//
// 0x0511 is the LOGICAL materialized content length, NEVER the representation
// payload length. DIRECT-1 coincides; EXTENTS-1 differs because the payload
// remainder is an operation collection. Frozen vector EXT-02/EXT-03 is the
// normative witness: serial 20 has a 17-byte remainder but declares 12.

function declaredSizes(data: Buffer): Map<number, number | null> {
  const out = new Map<number, number | null>();
  for (const rec of parse(data).records) {
    if (rec.rtype !== REC_CONTENT_OBJECT) continue;
    const s = rec.getField(FID_OBJECT_SERIAL);
    const z = rec.getField(FID_OBJECT_SIZE);
    if (s) out.set(Number(s.asUvarint()), z ? Number(z.asUvarint()) : null);
  }
  return out;
}

function buildExtents(ops: unknown[]): Buffer {
  const b = new ContainerBuilder(MODE_MODERN);
  b.addFile(Buffer.alloc(16, 0x11));
  const base = b.addObject(Buffer.from("ABCDEFGHIJ"));
  b.addObjectRaw(extents1Descriptor(ops), 2);
  b.addRevision(Buffer.alloc(16, 0x11), 1, base, "a.txt");
  b.setHead(Buffer.alloc(16, 0x11), 1);
  return b.build(1);
}

test("frozen vector declares logical length, not representation length", () => {
  const data = loadVector("EXT-02-and-EXT-03");
  const obj = parse(data).objects.find((o: { serial: bigint }) => Number(o.serial) === 20);
  const { identity: ident, remainder } = parseObjectHeader(obj.descriptor);
  eq(ident, REP_EXTENTS_1, "EXTENTS-1");
  eq(remainder.length, 17, "representation payload length");
  const logical = new VsnContainer(data).materialize(20);
  eq(logical.length, 12, "materialized length");
  eq(declaredSizes(data).get(20), 12, "declared = logical");
});

test("DIRECT-1 declared size equals logical length", () => {
  const store = create();
  store.createFile("a.txt", Buffer.from("hello world"));
  eq(declaredSizes(store.commit()).get(1), 11, "11 bytes");
});

test("EXTENTS-1 COPY declares materialized length", () => {
  const data = buildExtents([copyOperation(1, 0, 10)]);
  const obj = parse(data).objects.find((o: { serial: bigint }) => Number(o.serial) === 2);
  const { remainder } = parseObjectHeader(obj.descriptor);
  eq(remainder.length, 9, "representation payload is 9");
  eq(new VsnStore(data).materialize(2).length, 10, "materialized is 10");
  eq(declaredSizes(data).get(2), 10, "declared must be 10");
});

test("EXTENTS-1 LITERAL declares materialized length", () => {
  const data = buildExtents([literalOperation(Buffer.from("alpha"))]);
  eq(new VsnStore(data).materialize(2).length, 5, "materialized");
  eq(declaredSizes(data).get(2), 5, "declared");
});

test("EXTENTS-1 COPY + LITERAL declares materialized length", () => {
  const data = buildExtents([copyOperation(1, 0, 10), literalOperation(Buffer.from("!!"))]);
  eq(new VsnStore(data).materialize(2).length, 12, "materialized");
  eq(declaredSizes(data).get(2), 12, "declared");
});

test("rewritten container preserves the declared logical length", () => {
  const original = buildExtents([copyOperation(1, 0, 10), literalOperation(Buffer.from("!!"))]);
  const store = new VsnStore(original);
  const before = store.materialize(2);
  const rewritten = store.toBytes();          // rewrite
  const reparsed = new VsnStore(rewritten);   // parse again
  eqBytes(reparsed.materialize(2), before, "materialization survives round-trip");
  eq(declaredSizes(rewritten).get(2), 12, "declared logical length preserved");
  eq(declaredSizes(rewritten).get(1), 10, "declared DIRECT-1 length preserved");
});

test("DR-6 rejects a declared size that disagrees with materialization", () => {
  const data = buildExtents([copyOperation(1, 0, 10)]);
  validate(data, "Content");                       // correct value passes
  eq((expectThrow(() => validate(withDeclaredSize(data, 2, 9), "Content")) as VsnError).code,
     0x000C, "wrong declared size is invalid canonical state");
});

/** Re-encode forcing a specific ObjectSerial's declared 0x0511. */
function withDeclaredSize(data: Buffer, serial: number, size: number): Buffer {
  const parsed = parse(data);
  const records = parsed.records.map((rec) => {
    let fields = rec.fields.filter((f: { fid: number }) => f.fid !== FID_OBJECT_SIZE);
    if (rec.rtype === REC_CONTENT_OBJECT) {
      const s = rec.getField(FID_OBJECT_SERIAL);
      if (s && Number(s.asUvarint()) === serial)
        fields = [...fields, { fid: FID_OBJECT_SIZE, value: putUvarint(size) }];
    }
    return { rtype: rec.rtype, fields };
  });
  return encode(parsed.mode ?? MODE_MODERN, records,
                parsed.objects.map((o: { serial: bigint; descriptor: Buffer }) =>
                  ({ serial: o.serial, descriptor: o.descriptor })),
                parsed.trailerGeneration);
}

// --- LimitCleanUp (Library capability, NOT a VSN protocol rule) -------------
//
// Scope is one file's history; `limit` is the max retained revisions and must be
// >= 1; limit 0 is rejected; the newest `limit` are retained; retained
// RevisionIds / contents / ObjectSerials are never rewritten; the head revision
// is never removed; idempotent; persisted via the normal commit().

function storeWith(n: number): { store: VsnStore; fid: Buffer } {
  const store = create();
  const fid = store.createFile("a.txt", Buffer.from("v1"));
  for (let i = 2; i <= n; i++) store.writeFile(fid, Buffer.from(`v${i}`));
  return { store, fid };
}

function eqArr(actual: unknown, expected: unknown, what = "array"): void {
  eq(JSON.stringify(actual), JSON.stringify(expected), what);
}

test("LimitCleanUp: 1 revision, limit 5, removes nothing", () => {
  const { store, fid } = storeWith(1);
  eqArr(store.limitCleanup(fid, 5), []);
  eqArr(store.listRevisions(fid), [1]);
});

test("LimitCleanUp: 3 revisions, limit 5, removes nothing", () => {
  const { store, fid } = storeWith(3);
  eqArr(store.limitCleanup(fid, 5), []);
  eqArr(store.listRevisions(fid), [1, 2, 3]);
});

test("LimitCleanUp: 5 revisions, limit 5, removes nothing", () => {
  const { store, fid } = storeWith(5);
  eqArr(store.limitCleanup(fid, 5), []);
  eqArr(store.listRevisions(fid), [1, 2, 3, 4, 5]);
});

test("LimitCleanUp: 6 revisions, limit 5, keeps newest five", () => {
  const { store, fid } = storeWith(6);
  eqArr(store.limitCleanup(fid, 5), [1]);
  eqArr(store.listRevisions(fid), [2, 3, 4, 5, 6]);
});

test("LimitCleanUp: 10 revisions, limit 5, keeps 6..10", () => {
  const { store, fid } = storeWith(10);
  eqArr(store.limitCleanup(fid, 5), [1, 2, 3, 4, 5]);
  eqArr(store.listRevisions(fid), [6, 7, 8, 9, 10]);
});

test("LimitCleanUp: limit 1 keeps only the head", () => {
  const { store, fid } = storeWith(4);
  eqArr(store.limitCleanup(fid, 1), [1, 2, 3]);
  eqArr(store.listRevisions(fid), [4]);
});

test("LimitCleanUp: limit 0 is rejected and leaves history untouched", () => {
  const { store, fid } = storeWith(3);
  eq((expectThrow(() => store.limitCleanup(fid, 0)) as VsnError).code, 0x000C);
  eqArr(store.listRevisions(fid), [1, 2, 3]);
});

test("LimitCleanUp: negative limit is rejected", () => {
  const { store, fid } = storeWith(3);
  eq((expectThrow(() => store.limitCleanup(fid, -1)) as VsnError).code, 0x000C);
  eqArr(store.listRevisions(fid), [1, 2, 3]);
});

test("LimitCleanUp: repeated call is idempotent", () => {
  const { store, fid } = storeWith(10);
  eqArr(store.limitCleanup(fid, 5), [1, 2, 3, 4, 5]);
  eqArr(store.limitCleanup(fid, 5), []);
  eqArr(store.listRevisions(fid), [6, 7, 8, 9, 10]);
});

test("LimitCleanUp: smaller then larger limit does not recreate history", () => {
  const { store, fid } = storeWith(10);
  store.limitCleanup(fid, 3);
  eqArr(store.listRevisions(fid), [8, 9, 10]);
  store.limitCleanup(fid, 5);
  eqArr(store.listRevisions(fid), [8, 9, 10]);
  eqArr(new VsnStore(store.commit()).listRevisions(fid), [8, 9, 10]);
});

test("LimitCleanUp: removed revisions are unavailable after reopen", () => {
  const { store, fid } = storeWith(6);
  store.limitCleanup(fid, 5);
  const reopened = new VsnStore(store.commit());
  eqArr(reopened.listRevisions(fid), [2, 3, 4, 5, 6]);
  eq((expectThrow(() => reopened.getRevision(1)) as VsnError).code, 0x0009);
});

test("LimitCleanUp: retained revisions and ObjectSerials are byte-identical", () => {
  const { store, fid } = storeWith(10);
  const before = new Map(store.listRevisions(fid).map(
    (r) => [r, store.getRevision(r).objectSerial] as const));
  store.limitCleanup(fid, 5);
  const reopened = new VsnStore(store.commit());
  for (const rid of [6, 7, 8, 9, 10]) {
    const now = reopened.getRevision(rid).objectSerial;
    eq(now, before.get(rid), `serial ${rid}`);
    eqBytes(reopened.materialize(now!), store.materialize(before.get(rid)!),
            `content ${rid}`);
  }
});

test("LimitCleanUp: head, content and FileId survive", () => {
  const { store, fid } = storeWith(6);
  const head = store.getCurrentRevision(fid);
  const content = store.readFile(fid);
  store.limitCleanup(fid, 5);
  const reopened = new VsnStore(store.commit());
  eq(reopened.getCurrentRevision(fid), head, "head");
  eqBytes(reopened.readFile(fid), content, "content");
  eqBytes(reopened.getFileId("a.txt")!, fid, "file id");
});

test("LimitCleanUp: recovery still works from canonical state alone", () => {
  const { store, fid } = storeWith(10);
  store.limitCleanup(fid, 5);
  const data = store.commit();
  const result = recover(data);
  eq(result.recovered, true, "recovered");
  eq(result.acceptedGeneration, store.generation, "generation");
  eqArr(new VsnStore(data).listRevisions(fid), [6, 7, 8, 9, 10]);
});

test("LimitCleanUp: cleanup, new commit, cleanup again", () => {
  const { store, fid } = storeWith(6);
  store.limitCleanup(fid, 5);
  const reopened = new VsnStore(store.commit());
  reopened.writeFile(fid, Buffer.from("v7"));
  eqArr(reopened.listRevisions(fid), [2, 3, 4, 5, 6, 7]);
  eqArr(reopened.limitCleanup(fid, 5), [2]);
  eqArr(reopened.listRevisions(fid), [3, 4, 5, 6, 7]);
});

test("LimitCleanUp: object store is preserved for shared references", () => {
  const { store, fid } = storeWith(6);
  const objects = store.listObjects();
  store.limitCleanup(fid, 5);
  eqArr(store.listObjects(), objects, "objects retained");
});

test("LimitCleanUp: scope is per file", () => {
  const store = create();
  const a = store.createFile("a.txt", Buffer.from("a1"));
  const b = store.createFile("b.txt", Buffer.from("b1"));
  for (let i = 2; i <= 4; i++) {
    store.writeFile(a, Buffer.from(`a${i}`));
    store.writeFile(b, Buffer.from(`b${i}`));
  }
  eqArr(store.limitCleanup(a, 2), [1, 3]);
  eqArr(store.listRevisions(a), [5, 7]);
  eqArr(store.listRevisions(b), [2, 4, 6, 8], "b untouched");
});

test("LimitCleanUp: unknown FileId is rejected", () => {
  const store = create();
  store.createFile("a.txt", Buffer.from("v1"));
  eq((expectThrow(() => store.limitCleanup(Buffer.alloc(16), 5)) as VsnError).code,
     0x0009);
});

test("LimitCleanUp: no FileHead is left dangling", () => {
  const { store, fid } = storeWith(6);
  store.limitCleanup(fid, 5);
  const data = store.commit();
  const live = new VsnStore(data).listRevisions();
  let heads = 0;
  for (const rec of parse(data).records) {
    if (rec.rtype !== REC_FILE_HEAD) continue;
    heads++;
    const head = rec.getField(FID_HEAD_REV_ID)!;
    eq(live.includes(Number(head.asUvarint())), true, "head revision still exists");
  }
  eq(heads, 1, "a FileHead record is present");
});

test("LimitCleanUp: no new protocol record type appears", () => {
  const { store, fid } = storeWith(6);
  store.limitCleanup(fid, 5);
  const allowed = new Set([0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008, 0x0009]);
  for (const rec of parse(store.commit()).records)
    eq(allowed.has(rec.rtype), true,
       `record type ${rec.rtype} is a VSN record type`);
});

// --- LimitCleanUp audit coverage (parity with Python / C#) -----------------
//
// Mirrors the Python audit suite so cross-language semantics are provably
// identical: limit semantics, per-FileId scope, newest-N rule, return value,
// zero-limit behaviour, idempotency, monotonicity, FileHead, and recovery.

function ok2(cond: boolean, what: string): void { eq(cond, true, what); }

test("LimitCleanUp audit: limit boundary matrix", () => {
  const cases: [number, number, number][] = [
    [1, 1, 0], [2, 1, 1], [2, 2, 0], [2, 3, 0],
    [5, 1, 4], [5, 5, 0], [5, 6, 0],
    [10, 5, 5], [10, 1, 9], [10, 10, 0], [10, 11, 0],
  ];
  for (const [n, limit, expectedRemoved] of cases) {
    const { store, fid } = storeWith(n);
    const before = store.listRevisions(fid);
    const removed = store.limitCleanup(fid, limit);
    const after = store.listRevisions(fid);
    eq(removed.length, expectedRemoved, `n=${n} limit=${limit} removed`);
    eq(after.length, Math.min(n, limit), `n=${n} limit=${limit} retained`);
    // Retained set is always the NEWEST per-file revisions.
    eqArr(after, before.slice(before.length - after.length));
    eqArr(removed, before.slice(0, before.length - after.length));
  }
});

test("LimitCleanUp audit: monotonicity, both directions", () => {
  // smaller then larger: never resurrects deleted history
  const a1 = storeWith(10);
  a1.store.limitCleanup(a1.fid, 3);
  eqArr(a1.store.listRevisions(a1.fid), [8, 9, 10]);
  a1.store.limitCleanup(a1.fid, 5);
  eqArr(a1.store.listRevisions(a1.fid), [8, 9, 10]);
  const r1 = new VsnStore(a1.store.commit());
  for (let gone = 1; gone <= 7; gone++)
    eq((expectThrow(() => r1.getRevision(gone)) as VsnError).code, 0x0009, `rid ${gone}`);

  // larger then smaller: reduces the retained set
  const a2 = storeWith(10);
  a2.store.limitCleanup(a2.fid, 5);
  eqArr(a2.store.listRevisions(a2.fid), [6, 7, 8, 9, 10]);
  a2.store.limitCleanup(a2.fid, 3);
  eqArr(a2.store.listRevisions(a2.fid), [8, 9, 10]);
});

test("LimitCleanUp audit: per-file isolation ignores global numbering", () => {
  const store = create();
  const a = store.createFile("a.txt", Buffer.from("a1"));
  const b = store.createFile("b.txt", Buffer.from("b1"));
  for (let i = 2; i <= 5; i++) {
    store.writeFile(a, Buffer.from(`a${i}`));
    store.writeFile(b, Buffer.from(`b${i}`));
  }
  // a owns odd ids, b owns even ids.
  eqArr(store.listRevisions(a), [1, 3, 5, 7, 9]);
  eqArr(store.listRevisions(b), [2, 4, 6, 8, 10]);
  eqArr(store.limitCleanup(a, 3), [1, 3]);
  eqArr(store.listRevisions(a), [5, 7, 9]);
  eqArr(store.listRevisions(b), [2, 4, 6, 8, 10], "File B must be untouched");
  const r = new VsnStore(store.commit());
  eqArr(r.listRevisions(b), [2, 4, 6, 8, 10]);
  eqBytes(r.readFile(b), Buffer.from("b5"), "B content unchanged");
});

test("LimitCleanUp audit: FileHead is newest retained, never dangling", () => {
  const { store, fid } = storeWith(8);
  store.limitCleanup(fid, 5);
  const retained = store.listRevisions(fid);
  eqArr(retained, [4, 5, 6, 7, 8]);
  eq(store.getCurrentRevision(fid), retained[retained.length - 1]);
  const data = store.commit();
  for (const rec of parse(data).records) {
    if (rec.rtype === REC_FILE_HEAD)
      ok2(retained.includes(Number(rec.getField(FID_HEAD_REV_ID)!.asUvarint())),
          "FileHead is not dangling");
    if (rec.rtype === REC_REVISION)
      ok2(retained.includes(Number(rec.getField(FID_REV_ID)!.asUvarint())),
          "every Revision record is retained");
  }
});

test("LimitCleanUp audit: single retained revision is head and readable", () => {
  const { store, fid } = storeWith(6);
  store.limitCleanup(fid, 1);
  const r = new VsnStore(store.commit());
  eqArr(r.listRevisions(fid), [6]);
  eq(r.getCurrentRevision(fid), 6);
  eqBytes(r.readFile(fid), Buffer.from("v6"));
});

test("LimitCleanUp audit: deleted revisions unreachable via every API", () => {
  const { store, fid } = storeWith(6);
  store.limitCleanup(fid, 5);
  const r = new VsnStore(store.commit());
  eq((expectThrow(() => r.getRevision(1)) as VsnError).code, 0x0009, "getRevision");
  eq((expectThrow(() => r.checkoutRevision(fid, 1)) as VsnError).code, 0x0009, "checkout");
  eq((expectThrow(() => r.restoreRevision(fid, 1)) as VsnError).code, 0x0009, "restore");
  // getObjectSerial reports absence by returning null, like an unknown revision,
  // and must never return the deleted revision's stale ObjectSerial.
  eq(r.getObjectSerial(fid, 1), null, "getObjectSerial deleted");
  eq(r.getObjectSerial(fid, 1), r.getObjectSerial(fid, 9999), "same as unknown");
});

test("LimitCleanUp audit: revision deletion is not object GC", () => {
  const { store, fid } = storeWith(6);
  const objects = store.listObjects();
  const oldSerial = store.getRevision(1).objectSerial;
  const oldContent = store.materialize(oldSerial!);
  store.limitCleanup(fid, 5);
  const r = new VsnStore(store.commit());
  eq((expectThrow(() => r.getRevision(1)) as VsnError).code, 0x0009, "revision gone");
  eqBytes(r.materialize(oldSerial!), oldContent, "object NOT reclaimed");
  eqArr(r.listObjects(), objects, "object set unchanged");
});

test("LimitCleanUp audit: new commit after cleanup does not resurrect", () => {
  const { store, fid } = storeWith(8);
  store.limitCleanup(fid, 5);
  eqArr(store.listRevisions(fid), [4, 5, 6, 7, 8]);
  store.commit();
  store.writeFile(fid, Buffer.from("v9"));
  eqArr(store.listRevisions(fid), [4, 5, 6, 7, 8, 9]);
  eqArr(store.limitCleanup(fid, 5), [4]);
  const data = store.commit();
  const r = new VsnStore(data);
  eqArr(r.listRevisions(fid), [5, 6, 7, 8, 9]);
  eq(r.getCurrentRevision(fid), 9);
  eq(recover(data).recovered, true);
  for (const gone of [1, 2, 3, 4])
    eq((expectThrow(() => r.getRevision(gone)) as VsnError).code, 0x0009);
});

test("LimitCleanUp audit: full validation passes after cleanup", () => {
  const { store, fid } = storeWith(6);
  store.limitCleanup(fid, 2);
  const data = store.commit();
  for (const level of ["Structural", "Semantic", "Recovery", "Content", "Full"])
    validate(data, level as "Full");
});

// --- File API ---

test("file create/read/write/delete/rename", () => {
  const store = create();
  const fid = store.createFile("a.txt", Buffer.from("one"));
  eqBytes(store.readFile(fid), Buffer.from("one"), "read");
  store.writeFile(fid, Buffer.from("two"));
  eqBytes(store.readFile(fid), Buffer.from("two"), "after write");
  store.renameFile(fid, "b.txt");
  eq(store.getFileId("b.txt")!.toString("hex"), fid.toString("hex"), "renamed lookup");
  eqBytes(store.readFile(fid), Buffer.from("two"), "content preserved across rename");
  store.deleteFile(fid);
  eq(store.fileExists(fid), false, "deleted");
  eq(expectThrow(() => store.readFile(fid)) instanceof VsnError, true, "read deleted throws");
});

test("multiple files coexist and enumerate", () => {
  const store = create();
  const a = store.createFile("a.txt", Buffer.from("A"));
  const b = store.createFile("b.txt", Buffer.from("B"));
  const c = store.createFile("c.txt", Buffer.from("C"));
  const paths = store.listFiles().map((f) => f.path).sort();
  eq(paths.join(","), "a.txt,b.txt,c.txt", "paths");
  const data = store.commit();
  const re = VsnStore.open(data);
  eqBytes(re.readFile(a), Buffer.from("A"), "a");
  eqBytes(re.readFile(b), Buffer.from("B"), "b");
  eqBytes(re.readFile(c), Buffer.from("C"), "c");
});

test("FileId is 16 opaque bytes and stable across commit/reopen", () => {
  const store = create();
  const fid = store.createFile("a.txt", Buffer.from("x"));
  eq(fid.length, 16, "length");
  const data = store.commit();
  const re = VsnStore.open(data);
  eq(re.getFileId("a.txt")!.toString("hex"), fid.toString("hex"), "stable FileId");
  const meta = re.getFileMetadata(fid);
  eq(meta.path, "a.txt", "path");
  eq(meta.headRevision, 1, "head revision");
});

test("duplicate path is rejected", () => {
  const store = create();
  store.createFile("dup.txt", Buffer.from("1"));
  const e = expectThrow(() => store.createFile("dup.txt", Buffer.from("2")));
  eq((e as VsnError).code, 0x000A, "duplicate code");
});

// --- Revision API ---

test("revision list, retrieve, checkout, restore, compare", () => {
  const store = create();
  const fid = store.createFile("a.txt", Buffer.from("v1"));
  store.writeFile(fid, Buffer.from("v2"));
  store.writeFile(fid, Buffer.from("v3"));
  eq(store.listRevisions(fid).join(","), "1,2,3", "revisions");
  eq(store.getCurrentRevision(fid), 3, "head");
  eq(store.getRevision(1).presence, 1, "presence");
  eqBytes(store.checkoutRevision(fid, 1), Buffer.from("v1"), "checkout v1");
  eq(store.compareRevisions(fid, 1, 3), true, "compare differs");
  eq(store.compareRevisions(fid, 2, 2), false, "compare same");
  store.restoreRevision(fid, 1);
  eqBytes(store.readFile(fid), Buffer.from("v1"), "restored");
  eq(store.revisionMetadata(3).fileId.toString("hex"), fid.toString("hex"), "metadata");
});

test("checkout rejects a RevisionId from a different file", () => {
  const store = create();
  const a = store.createFile("a.txt", Buffer.from("a"));
  store.createFile("b.txt", Buffer.from("b"));
  const e = expectThrow(() => store.checkoutRevision(a, 2));
  eq((e as VsnError).code, 0x000B, "relationship code");
});

// --- Object API ---

test("object enumerate/inspect/serial/materialize/metadata", () => {
  const store = create();
  const fid = store.createFile("a.txt", Buffer.from("payload"));
  eq(store.listObjects().join(","), "1", "objects");
  const serial = store.getObjectSerial(fid)!;
  eq(serial, 1, "serial");
  const info = store.getObjectInfo(serial);
  eq(info.representationIdentity, REP_DIRECT_1, "rep identity");
  eq(info.representationVersion, 1, "rep version");
  eq(info.length, 7, "length");
  eqBytes(store.materialize(serial), Buffer.from("payload"), "materialize");
  eq(store.getObjectMetadata(serial).serial, serial, "metadata");
});

test("EXTENTS-1 object materializes through COPY + LITERAL", () => {
  const store = create();
  const fid = store.createFile("base.txt", Buffer.from("hello vsn\n"));
  const src = store.getObjectSerial(fid)!;
  const dst = store.addObjectDescriptor(extents1Descriptor([
    copyOperation(src, 0, 10), literalOperation(Buffer.from("!!")),
  ]));
  store.writeFile(fid, store.materialize(dst));
  eqBytes(store.readFile(fid), Buffer.from("hello vsn\n!!"), "extents content");
  eq(store.getObjectInfo(dst).representationIdentity, REP_EXTENTS_1, "extents rep");
});

// --- Transactions ---

test("transaction stage, inspect, rollback", () => {
  const store = create();
  const fid = store.createFile("a.txt", Buffer.from("base"));
  const tx = new Transaction();
  tx.stageUpdate(fid, Buffer.from("changed"));
  tx.stageCreate("new.txt", Buffer.from("new"));
  eq(tx.changeCount, 2, "staged");
  eq(tx.inspect()[0].operation, "update", "inspect");
  tx.rollback();
  eq(tx.changeCount, 0, "rolled back");
  eqBytes(store.readFile(fid), Buffer.from("base"), "unchanged");
});

test("transaction commit applies staged changes and commits", () => {
  const store = create();
  const fid = store.createFile("a.txt", Buffer.from("base"));
  const tx = new Transaction();
  tx.stageUpdate(fid, Buffer.from("updated"));
  tx.stageDelete(fid);
  const data = tx.commit(store);
  eq(store.fileExists(fid), false, "deleted after commit");
  const re = VsnStore.open(data);
  eq(re.fileExists(re.getFileId("a.txt") ?? Buffer.alloc(16)), false, "persisted");
});

test("ExpectedRevisionId success and failure as a precondition", () => {
  const store = create();
  const fid = store.createFile("a.txt", Buffer.from("base"));
  const ok = new Transaction(1);
  ok.stageUpdate(fid, Buffer.from("ok"));
  const data = ok.commit(store);
  // ExpectedRevisionId must NEVER be persisted as canonical state (RC-01).
  eq(data.includes(Buffer.from("expected_revision")), false, "not persisted");
  eq(recover(data).status, "RECOVERED", "commit marker authoritative");
  const store2 = VsnStore.open(data);
  const bad = new Transaction(1); // head is now 2
  bad.stageUpdate(fid, Buffer.from("no"));
  const e = expectThrow(() => bad.commit(store2));
  eq((e as VsnError).code, 0x000D, "precondition code");
});


test("commit twice on the same transaction is rejected", () => {
  const store = create();
  store.createFile("a.txt", Buffer.from("x"));
  const tx = new Transaction();
  tx.stageCreate("b.txt", Buffer.from("y"));
  tx.commit(store);
  const e = expectThrow(() => tx.commit(store));
  eq((e as VsnError).code, 0x000C, "already committed");
});

// --- Diff ---

test("object diff", () => {
  const left = create();
  const lf = left.createFile("a.txt", Buffer.from("a"));
  const right = create();
  right.createFile("a.txt", Buffer.from("a"));
  const rf = right.createFile("b.txt", Buffer.from("b"));
  const d = diff.diffObjects(left.listObjects(), right.listObjects());
  eq(d.shared.length, 1, "shared");
  eq(d.added.length, 1, "added");
  eq(d.removed.length, 0, "removed");
  void lf; void rf;
});

test("file diff and revision diff", () => {
  const left = create();
  left.createFile("a.txt", Buffer.from("one"));
  left.createFile("gone.txt", Buffer.from("bye"));
  const right = create();
  right.createFile("a.txt", Buffer.from("two"));
  right.createFile("new.txt", Buffer.from("hi"));
  const d = diff.diffFiles(left, right);
  eq(d.modified.join(","), "a.txt", "modified");
  eq(d.deleted.join(","), "gone.txt", "deleted");
  eq(d.added.join(","), "new.txt", "added");

  const store = create();
  const fid = store.createFile("r.txt", Buffer.from("v1"));
  store.writeFile(fid, Buffer.from("v2-longer"));
  const rd = diff.diffRevisions(store, fid, 1, 2);
  eq(rd.changed, true, "changed");
  eq(rd.addedBytes, 9 - 2, "added bytes");
});

// --- Merge ---

test("three-way merge auto-merges non-conflicting changes", () => {
  const base = create();
  base.createFile("a.txt", Buffer.from("base"));
  base.createFile("b.txt", Buffer.from("base"));
  const ours = create();
  ours.createFile("a.txt", Buffer.from("ours"));
  ours.createFile("b.txt", Buffer.from("base"));
  const theirs = create();
  theirs.createFile("a.txt", Buffer.from("base"));
  theirs.createFile("b.txt", Buffer.from("theirs"));
  const m = merge.threeWayMerge(base, ours, theirs);
  eq(merge.hasConflicts(m), false, "no conflicts");
  eqBytes(m.mergedFiles.get("a.txt")!, Buffer.from("ours"), "a");
  eqBytes(m.mergedFiles.get("b.txt")!, Buffer.from("theirs"), "b");
});

test("three-way merge reports conflicts without silent data loss", () => {
  const base = create();
  base.createFile("a.txt", Buffer.from("base"));
  const ours = create();
  ours.createFile("a.txt", Buffer.from("ours"));
  const theirs = create();
  theirs.createFile("a.txt", Buffer.from("theirs"));
  const m = merge.threeWayMerge(base, ours, theirs);
  eq(merge.hasConflicts(m), true, "has conflicts");
  eq(m.conflicts.length, 1, "one conflict");
  eq(m.conflicts[0].path, "a.txt", "path");
  eqBytes(m.conflicts[0].oursContent, Buffer.from("ours"), "ours");
  eqBytes(m.conflicts[0].theirsContent, Buffer.from("theirs"), "theirs");
});

test("explicit conflict resolution", () => {
  const base = create();
  base.createFile("a.txt", Buffer.from("base"));
  const ours = create();
  ours.createFile("a.txt", Buffer.from("ours"));
  const theirs = create();
  theirs.createFile("a.txt", Buffer.from("theirs"));
  const m = merge.threeWayMerge(base, ours, theirs);
  merge.resolveConflict(m, "a.txt", Buffer.from("resolved"));
  eq(merge.hasConflicts(m), false, "resolved");
  eqBytes(m.mergedFiles.get("a.txt")!, Buffer.from("resolved"), "content");
});


// --- Import / Export ---

test("byte-oriented import/export preserves arbitrary binary data", () => {
  const store = create();
  const payload = Buffer.from([0x00, 0x01, 0xff, 0x00, 0x7f, 0x80, 0x00]);
  const fid = importFile(store, "bin.dat", payload);
  eqBytes(exportFile(store, fid), payload, "round trip");
  const data = store.commit();
  eqBytes(exportFile(VsnStore.open(data), fid), payload, "persisted");
});

test("stream-oriented import/export", async () => {
  const store = create();
  const big = Buffer.alloc(200000);
  for (let i = 0; i < big.length; i++) big[i] = i % 251;
  const readable = Readable.from([big]);
  const fid = await io_ops.importStream(store, "big.bin", readable);
  const chunks: Buffer[] = [];
  const sink = new Writable({
    write(chunk, _enc, cb) { chunks.push(Buffer.from(chunk)); cb(); },
  });
  const written = await io_ops.exportStream(store, fid, sink);
  eq(written, big.length, "bytes written");
  eqBytes(Buffer.concat(chunks), big, "streamed content");
});

test("batch import/export", () => {
  const store = create();
  const files = new Map<string, Buffer>([
    ["a.txt", Buffer.from("A")], ["b.txt", Buffer.from("B")],
  ]);
  const ids = io_ops.importMultiple(store, files);
  eq(ids.size, 2, "imported");
  const out = io_ops.exportMultiple(store, [...ids.values()]);
  eq(out.size, 2, "exported");
  const values = [...out.values()].map((b) => b.toString()).sort();
  eq(values.join(","), "A,B", "content");
});

// --- Streaming ---

test("large object streams in chunks without full-memory materialization", () => {
  const store = create();
  const big = Buffer.alloc(300000);
  for (let i = 0; i < big.length; i++) big[i] = (i * 7) % 256;
  const fid = store.createFile("big.bin", big);
  const chunks: Buffer[] = [];
  for (const c of store.readFileStream(fid, 65536)) chunks.push(c);
  eq(chunks.length >= 5, true, "chunked");
  eqBytes(Buffer.concat(chunks), big, "streamed equals materialized");
});

test("EXTENTS-1 object streams identically to materialization", () => {
  const store = create();
  const fid = store.createFile("base.txt", Buffer.from("hello vsn\n"));
  const src = store.getObjectSerial(fid)!;
  const dst = store.addObjectDescriptor(extents1Descriptor([
    copyOperation(src, 0, 10), literalOperation(Buffer.from("!!")),
  ]));
  const chunks: Buffer[] = [];
  for (const c of store.materializeStream(dst, 4)) chunks.push(c);
  eqBytes(Buffer.concat(chunks), store.materialize(dst), "stream equals materialize");
});

// --- Diagnostics ---

test("structured diagnostics carry code, name, severity, category, context", () => {
  const store = create();
  store.createFile("a.txt", Buffer.from("x"));
  const data = store.commit();
  const bad = data.subarray(0, 20);
  const diags = validateContainer(bad, "Full");
  eq(diags.length, 1, "one diagnostic");
  eq(diags[0].code, 0x0002, "code");
  eq(diags[0].name, "TRUNCATED", "name");
  eq(diags[0].severity, "error", "severity");
  eq(diags[0].category, "protocol", "category");
  eq(typeof diags[0].message, "string", "message");
});


// --- Integrity ---

test("library-level integrity verification uses canonical state", () => {
  const store = create();
  const fid = store.createFile("a.txt", Buffer.from("integrity"));
  store.commit();
  const report = verifyIntegrity(store);
  eq(report.valid, true, "valid");
  eq(report.fileCount, 1, "files");
  eq(report.objectCount, 1, "objects");
  eq(report.revisionCount, 1, "revisions");
  eq(report.contentHash, canonicalHash(store.canonicalData), "hash matches canonical bytes");
  eq(report.errors.length, 0, "no errors");
  void fid;
});

// --- Storage management (derived data) ---

test("derived index/cache build, rebuild, gc, stats, cleanup", () => {
  const store = create();
  store.createFile("a.txt", Buffer.from("aaa"));
  store.createFile("b.txt", Buffer.from("bbbb"));
  store.commit();
  const sm = new StorageManager();
  sm.buildIndexes(store);
  eq(sm.isValid, true, "valid");
  eq(sm.lookupFile("a.txt")!.length, 16, "index lookup");
  sm.cachePut(1, Buffer.from("cached"));
  eq(sm.cacheCount(), 1, "cache");
  const stats = sm.stats(store);
  eq(stats.fileCount, 2, "file count");
  eq(stats.objectCount, 2, "object count");
  eq(stats.indexEntries >= 2, true, "index entries");
  eq(sm.gc(), 1, "gc removed");
  eq(sm.cacheCount(), 0, "cache cleared");
  sm.invalidate();
  eq(sm.isValid, false, "invalidated");
  sm.rebuild(store);
  eq(sm.isValid, true, "rebuilt");
});

test("recovery remains functional after all derived data is deleted", () => {
  const store = create();
  const fid = store.createFile("a.txt", Buffer.from("survives"));
  store.writeFile(fid, Buffer.from("survives!"));
  const data = store.commit();
  const sm = new StorageManager();
  sm.buildIndexes(store);
  sm.cachePut(1, Buffer.from("derived"));
  // Delete every derived structure.
  sm.invalidate();
  eq(sm.isValid, false, "derived gone");
  eq(sm.cacheCount(), 0, "cache gone");
  // Recovery and reads must still work from canonical bytes alone.
  const rr = recoverContainer(data);
  eq(rr.status, "RECOVERED", "recovered");
  eq(rr.acceptedGeneration, 1, "generation");
  const re = VsnStore.open(data);
  eqBytes(re.readFile(fid), Buffer.from("survives!"), "content from canonical state");
  eq(re.listFiles().length, 1, "files from canonical state");
});

test("recovery without indexes, caches, checkpoints, or private databases", () => {
  const data = loadVector("EXT-02-and-EXT-03");
  const rr = recover(data);
  eq(rr.recovered, true, "recovered");
  eq(rr.acceptedGeneration, 1, "generation");
  // Derived data is never canonical authority: a stale index cannot change this.
  eqBytes(open(data).materialize(BigInt(20)), Buffer.from("hello vsn\n!!"), "content");
});

// --- Malformed container handling ---

test("malformed container handling across levels", () => {
  const store = create();
  store.createFile("a.txt", Buffer.from("x"));
  const good = store.commit();
  eq(expectThrow(() => VsnStore.open(good.subarray(0, 10))) instanceof VsnError, true, "open");
  eq(recover(good.subarray(0, 10)).status, "TRUNCATED", "recover truncated");
  const corrupt = Buffer.from(good);
  corrupt[4] = 0x09; // break container format version
  eq(recover(corrupt).status, "MALFORMED", "recover malformed");
  eq(validateContainer(corrupt, "Structural")[0].code, 0x0003, "diagnostic code");
});

await run();


