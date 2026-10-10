// VSN protocol conformance tests: frozen vectors, framing, registries,
// representations, dependencies, uvarint boundaries, and negative cases.
import * as fs from "fs";
import * as path from "path";
import * as crypto from "crypto";
import { test, run, expectThrow, eq, eqBytes } from "./harness.js";
import {
  open, parse, ContainerBuilder, VsnContainer, VsnError,
  readUvarint, putUvarint, readU16, putU16,
  validate, validateStructural, validateSemantic, validateContent,
  recover, direct1Descriptor, extents1Descriptor, literalOperation, copyOperation,
  encode,
  FID_FILE_ID, REC_FILE_IDENTITY, REC_MODE_DECLARATION, REC_COMMIT_MARKER,
  REC_CONTENT_OBJECT, MODE_MODERN, MODE_ENTERPRISE, PRESENT, DELETED,
  REP_DIRECT_1, REP_EXTENTS_1, REP_VERSION_1,
} from "../src/index.js";

const TV_DIR = path.resolve("..", "TestVectors");
const VECTORS = ["DIRECT-01", "DIRECT-02", "DIRECT-03", "EXT-01", "EXT-02-and-EXT-03"];

function loadVector(name: string): Buffer {
  return fs.readFileSync(path.join(TV_DIR, name + ".vsn"));
}

// --- Frozen vectors ---

test("manifest hashes and byte lengths", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(TV_DIR, "manifest.json"), "utf-8"));
  for (const v of manifest.vectors) {
    const data = loadVector(v.name);
    eq(crypto.createHash("sha256").update(data).digest("hex"), v.sha256, `${v.name} sha`);
    eq(data.length, v.bytes, `${v.name} length`);
  }
});

test("all 5 frozen vectors materialize to the intended logical bytes", () => {
  eqBytes(open(loadVector("DIRECT-01")).materialize(BigInt(42)), Buffer.alloc(0), "DIRECT-01");
  const d2 = open(loadVector("DIRECT-02")).materialize(BigInt(7));
  eq(d2.length, 256, "DIRECT-02 length");
  for (let i = 0; i < 256; i++) eq(d2[i], i, `DIRECT-02[${i}]`);
  eqBytes(open(loadVector("DIRECT-03")).materialize(BigInt(9)),
    Buffer.from([0x41, 0x00, 0x42, 0xff]), "DIRECT-03");
  eqBytes(open(loadVector("EXT-01")).materialize(BigInt(20)), Buffer.from("alpha"), "EXT-01");
  const e2 = open(loadVector("EXT-02-and-EXT-03"));
  eqBytes(e2.materialize(BigInt(10)), Buffer.from("hello vsn\n"), "EXT-02");
  eqBytes(e2.materialize(BigInt(20)), Buffer.from("hello vsn\n!!"), "EXT-03");
});

test("FileIdentity.FileId field id is 0x0101 and is 16 bytes", () => {
  eq(FID_FILE_ID, 0x0101, "FID_FILE_ID");
  eq(REC_FILE_IDENTITY, 0x0001, "REC_FILE_IDENTITY");
  for (const name of VECTORS) {
    for (const rec of parse(loadVector(name)).records) {
      if (rec.rtype === REC_FILE_IDENTITY) {
        const f = rec.getField(FID_FILE_ID);
        if (!f) throw new Error(`${name}: FileIdentity must carry field 0x0101`);
        eq(f.value.length, 16, `${name} FileId length`);
      }
    }
  }
});

test("trailer canonical record count excludes ModeDeclaration", () => {
  const parsed = parse(loadVector("DIRECT-01"));
  eq(parsed.records.length, 7, "records");
  eq(parsed.records.filter((r) => r.rtype !== REC_MODE_DECLARATION).length, 6, "canonical");
  eq(Number(parsed.trailerRecordCount), 6, "trailer count");
  eq(Number(parsed.trailerGeneration), 1, "trailer generation");
});

// --- Representations (DR-0) ---

test("DIRECT-1 descriptor round-trips through a built container", () => {
  const fid = Buffer.alloc(16, 0x11);
  const b = new ContainerBuilder(MODE_MODERN);
  b.addFile(fid);
  const serial = b.addObject(Buffer.from("direct!"));
  b.addRevision(fid, 1, serial, "a.txt");
  b.setHead(fid, 1);
  const c = open(b.build(1));
  eqBytes(c.materialize(BigInt(serial)), Buffer.from("direct!"), "direct");
  eq(c.mode, MODE_MODERN, "mode");
});

test("EXTENTS-1 LITERAL operation", () => {
  const fid = Buffer.alloc(16, 0x22);
  const b = new ContainerBuilder(MODE_MODERN);
  b.addFile(fid);
  const serial = b.addObjectRaw(extents1Descriptor([literalOperation(Buffer.from("alpha"))]));
  b.addRevision(fid, 1, serial, "a.txt");
  b.setHead(fid, 1);
  eqBytes(open(b.build(1)).materialize(BigInt(serial)), Buffer.from("alpha"), "literal");
});

test("EXTENTS-1 COPY + LITERAL dependency", () => {
  const fid = Buffer.alloc(16, 0x33);
  const b = new ContainerBuilder(MODE_MODERN);
  b.addFile(fid);
  const src = b.addObject(Buffer.from("hello vsn\n"));
  const dst = b.addObjectRaw(extents1Descriptor([
    copyOperation(src, 0, 10), literalOperation(Buffer.from("!!")),
  ]));
  b.addRevision(fid, 1, src, "a.txt");
  b.addRevision(fid, 2, dst, "b.txt");
  b.setHead(fid, 2);
  const c = open(b.build(2));
  eqBytes(c.materialize(BigInt(src)), Buffer.from("hello vsn\n"), "src");
  eqBytes(c.materialize(BigInt(dst)), Buffer.from("hello vsn\n!!"), "dst");
});

test("dependency validation rejects a missing ObjectSerial", () => {
  const fid = Buffer.alloc(16, 0x44);
  const b = new ContainerBuilder(MODE_MODERN);
  b.addFile(fid);
  b.addRevision(fid, 1, 999, "a.txt"); // no such object
  b.setHead(fid, 1);
  const e = expectThrow(() => validate(b.build(1), "Semantic"));
  eq((e as VsnError).code, 0x0008, "error code");
});

test("dependency cycle is rejected during materialization", () => {
  // object 1 COPYs from object 2, object 2 COPYs from object 1.
  const b = new ContainerBuilder(MODE_MODERN);
  const fid = Buffer.alloc(16, 0x55);
  b.addFile(fid);
  b.addObjectRaw(extents1Descriptor([copyOperation(2, 0, 1)]), 1);
  b.addObjectRaw(extents1Descriptor([copyOperation(1, 0, 1)]), 2);
  b.addRevision(fid, 1, 1, "a.txt");
  b.setHead(fid, 1);
  const c = open(b.build(1));
  const e = expectThrow(() => c.materialize(BigInt(1)));
  eq((e as VsnError).code, 0x000C, "cycle error code");
});

test("EXTENTS-1 COPY range out of bounds is rejected", () => {
  const fid = Buffer.alloc(16, 0x56);
  const b = new ContainerBuilder(MODE_MODERN);
  b.addFile(fid);
  const src = b.addObject(Buffer.from("abc"));
  const dst = b.addObjectRaw(extents1Descriptor([copyOperation(src, 0, 99)]));
  b.addRevision(fid, 1, dst, "a.txt");
  b.setHead(fid, 1);
  const c = open(b.build(1));
  const e = expectThrow(() => c.materialize(BigInt(dst)));
  eq((e as VsnError).code, 0x000C, "bounds error code");
});


// --- uvarint boundaries ---

test("uvarint boundary values round-trip and stay minimal", () => {
  const values = [0n, 1n, 127n, 128n, 16383n, 16384n, 2097151n, 2097152n,
    268435455n, 268435456n, 34359738367n, 34359738368n, 2n ** 63n, 2n ** 64n - 1n];
  for (const v of values) {
    const enc = putUvarint(v);
    const off = { value: 0 };
    eq(readUvarint(enc, off), v, `uvarint ${v}`);
    eq(off.value, enc.length, `consumed ${v}`);
  }
  eq(putUvarint(0n).length, 1, "0 encodes to 1 byte");
  eq(putUvarint(127n).length, 1, "127 encodes to 1 byte");
  eq(putUvarint(128n).length, 2, "128 encodes to 2 bytes");
});

test("non-minimal uvarint is rejected", () => {
  const e = expectThrow(() => { const o = { value: 0 }; readUvarint(Buffer.from([0x80, 0x00]), o); });
  eq((e as VsnError).code, 0x0001, "non-minimal code");
});

test("uvarint overflow (>10 bytes) is rejected", () => {
  const e = expectThrow(() => {
    const o = { value: 0 };
    readUvarint(Buffer.from([0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01]), o);
  });
  eq((e as VsnError).code, 0x0001, "overflow code");
});

test("u16be round-trips", () => {
  eq(readU16(putU16(0x0101), { value: 0 }), 0x0101, "u16");
});

// --- Malformed framing and negative cases ---

test("invalid magic is rejected", () => {
  const e = expectThrow(() => parse(Buffer.alloc(100)));
  eq((e as VsnError).code, 0x0001, "magic code");
});

test("invalid container format version is rejected", () => {
  const data = Buffer.from([0x56, 0x53, 0x4e, 0x2d, 0x00, 0x02, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]);
  const e = expectThrow(() => parse(data));
  eq((e as VsnError).code, 0x0003, "cfv code");
});

test("invalid encoding version is rejected", () => {
  const data = Buffer.from([0x56, 0x53, 0x4e, 0x2d, 0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00]);
  const e = expectThrow(() => parse(data));
  eq((e as VsnError).code, 0x0004, "ev code");
});

test("truncation of a frozen vector is detected as TRUNCATED", () => {
  const data = loadVector("DIRECT-01");
  const rr = recover(data.subarray(0, data.length - 5));
  eq(rr.status, "TRUNCATED", "status");
  eq(rr.recovered, false, "recovered");
});

test("truncated framing raises TRUNCATED", () => {
  const data = loadVector("DIRECT-02");
  const e = expectThrow(() => parse(data.subarray(0, 20)));
  eq((e as VsnError).code, 0x0002, "truncated code");
});

test("invalid field ordering (non-ascending FieldId) is rejected", () => {
  // Hand-build a record whose fields descend: 0x0201 then 0x0101.
  const payload = Buffer.concat([
    putU16(0x0201), putUvarint(1), Buffer.from([0x01]),
    putU16(0x0101), putUvarint(1), Buffer.from([0x01]),
  ]);
  const rec = Buffer.concat([putU16(0x0002), putUvarint(payload.length), payload]);
  const data = Buffer.concat([
    Buffer.from("VSN-", "ascii"), putU16(1), putU16(1),
    putU16(0x0000), putUvarint(0),
    rec,
    putU16(0x0000), putUvarint(0), putUvarint(1), putUvarint(1),
  ]);
  const e = expectThrow(() => parse(data));
  eq((e as VsnError).code, 0x0011, "ordering code");
});


test("unsupported representation identity is rejected", () => {
  const fid = Buffer.alloc(16, 0x66);
  const b = new ContainerBuilder(MODE_MODERN);
  b.addFile(fid);
  const bad = Buffer.concat([putU16(0x00ff), putUvarint(REP_VERSION_1), Buffer.from("x")]);
  const serial = b.addObjectRaw(bad);
  b.addRevision(fid, 1, serial, "a.txt");
  b.setHead(fid, 1);
  const c = open(b.build(1));
  const e = expectThrow(() => c.materialize(BigInt(serial)));
  eq((e as VsnError).code, 0x0006, "rep code");
});

test("reserved mode value is rejected", () => {
  const fid = Buffer.alloc(16, 0x77);
  const b = new ContainerBuilder(0x03); // reserved
  b.addFile(fid);
  const serial = b.addObject(Buffer.from("x"));
  b.addRevision(fid, 1, serial, "a.txt");
  b.setHead(fid, 1);
  const e = expectThrow(() => validate(b.build(1), "Semantic"));
  eq((e as VsnError).code, 0x0001, "reserved mode code");
});

test("ENTERPRISE mode uses DIRECT-1 semantics", () => {
  const fid = Buffer.alloc(16, 0x88);
  const b = new ContainerBuilder(MODE_ENTERPRISE);
  b.addFile(fid);
  const serial = b.addObject(Buffer.from("enterprise"));
  b.addRevision(fid, 1, serial, "a.txt");
  b.setHead(fid, 1);
  const data = b.build(1);
  validate(data, "Full");
  eqBytes(open(data).materialize(BigInt(serial)), Buffer.from("enterprise"), "content");
});

test("ENTERPRISE mode rejects EXTENTS-1 reconstruction semantics (GR-43)", () => {
  const fid = Buffer.alloc(16, 0x99);
  const b = new ContainerBuilder(MODE_ENTERPRISE);
  b.addFile(fid);
  const serial = b.addObjectRaw(extents1Descriptor([literalOperation(Buffer.from("nope"))]));
  b.addRevision(fid, 1, serial, "a.txt");
  b.setHead(fid, 1);
  const e = expectThrow(() => validate(b.build(1), "Semantic"));
  eq((e as VsnError).code, 0x000C, "GR-43 code");
});

test("mode does not fork the VSN grammar (same framing both modes)", () => {
  const fid = Buffer.alloc(16, 0xaa);
  const modern = new ContainerBuilder(MODE_MODERN);
  modern.addFile(fid);
  const s = modern.addObject(Buffer.from("same"));
  modern.addRevision(fid, 1, s, "a.txt");
  modern.setHead(fid, 1);
  const enterprise = new ContainerBuilder(MODE_ENTERPRISE);
  enterprise.addFile(fid);
  const s2 = enterprise.addObject(Buffer.from("same"));
  enterprise.addRevision(fid, 1, s2, "a.txt");
  enterprise.setHead(fid, 1);
  const a = parse(modern.build(1));
  const c = parse(enterprise.build(1));
  eq(a.records.length, c.records.length, "record count");
  eq(a.objects.length, c.objects.length, "object count");
  eq(a.mode, MODE_MODERN, "modern mode");
  eq(c.mode, MODE_ENTERPRISE, "enterprise mode");
});

test("DR-0 object header parses identity and version", () => {
  const desc = direct1Descriptor(Buffer.from("payload"));
  eq(desc.readUInt16BE(0), REP_DIRECT_1, "identity");
  const off = { value: 2 };
  eq(Number(readUvarint(desc, off)), REP_VERSION_1, "version");
  eqBytes(desc.subarray(off.value), Buffer.from("payload"), "remainder");
});

test("recovery selects the highest accepted generation", () => {
  const data = loadVector("DIRECT-01");
  eq(recover(data).acceptedGeneration, 1, "generation");
  eq(recover(data).status, "RECOVERED", "status");
  eq(recover(data).recovered, true, "recovered");
});

test("recovery works without any index, cache, checkpoint, or derived data", () => {
  const data = loadVector("EXT-02-and-EXT-03");
  const rr = recover(data);
  eq(rr.status, "RECOVERED", "status");
  eqBytes(open(data).materialize(BigInt(20)), Buffer.from("hello vsn\n!!"), "content");
});

test("no CommitMarker yields NO_MARKER", () => {
  const b = new ContainerBuilder(MODE_MODERN);
  b.addFile(Buffer.alloc(16, 0xbb));
  // encode directly without the builder's auto-appended CommitMarker
  const records = [
    { rtype: REC_MODE_DECLARATION, fields: [{ fid: 0x0701, value: Buffer.from([MODE_MODERN]) }] },
    { rtype: REC_FILE_IDENTITY, fields: [{ fid: FID_FILE_ID, value: Buffer.alloc(16, 0xbb) }] },
  ];
  const data = encode(MODE_MODERN, records, [], 0);
  eq(recover(data).status, "NO_MARKER", "status");
});

await run();


