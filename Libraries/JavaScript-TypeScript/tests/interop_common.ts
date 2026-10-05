// Cross-language interoperability: shared scenario definitions and a
// language-neutral description of a container's canonical interpretation.
import * as fs from "fs";
import * as path from "path";
import {
  parse, VsnContainer, ContainerBuilder, recover,
  extents1Descriptor, literalOperation, copyOperation,
  REC_FILE_IDENTITY, REC_REVISION, REC_FILE_HEAD, FID_FILE_ID, FID_REV_ID,
  FID_REV_FILE_ID, FID_REV_OBJECT_SERIAL, FID_REV_PATH, FID_HEAD_FILE_ID,
  FID_HEAD_REV_ID, MODE_MODERN, MODE_ENTERPRISE, readUvarint,
} from "../src/index.js";

export const SCENARIOS = ["basic", "extents", "enterprise", "multifile"] as const;
export type ScenarioName = (typeof SCENARIOS)[number];

function fid(byte: number): Buffer { return Buffer.alloc(16, byte); }

/** Build a scenario deterministically; identical bytes across all languages. */
export function buildScenario(name: ScenarioName): Buffer {
  const b = new ContainerBuilder(MODE_MODERN);
  if (name === "basic") {
    const f = fid(0x01);
    b.addFile(f);
    const s = b.addObject(Buffer.from("hello vsn\n"));
    b.addRevision(f, 1, s, "hello.txt");
    b.setHead(f, 1);
    return b.build(1);
  }
  if (name === "extents") {
    const a = fid(0x02);
    const c = fid(0x03);
    b.addFile(a);
    b.addFile(c);
    const s1 = b.addObject(Buffer.from("hello vsn\n"), 1);
    const s2 = b.addObjectRaw(extents1Descriptor([
      copyOperation(1, 0, 10), literalOperation(Buffer.from("!!")),
    ]), 2);
    b.addRevision(a, 1, s1, "a.txt");
    b.addRevision(c, 2, s2, "b.txt");
    b.setHead(a, 1);
    b.setHead(c, 2);
    return b.build(2);
  }
  if (name === "enterprise") {
    const f = fid(0x04);
    const e = new ContainerBuilder(MODE_ENTERPRISE);
    e.addFile(f);
    const s = e.addObject(Buffer.from("enterprise"));
    e.addRevision(f, 1, s, "e.txt");
    e.setHead(f, 1);
    return e.build(1);
  }
  // multifile: binary content including NUL and 0xFF
  const f1 = fid(0x05);
  const f2 = fid(0x06);
  const f3 = fid(0x07);
  b.addFile(f1); b.addFile(f2); b.addFile(f3);
  const s1 = b.addObject(Buffer.from([0x00, 0x01, 0xff, 0x00, 0x7f]), 1);
  const s2 = b.addObject(Buffer.from("plain text"), 2);
  const s3 = b.addObject(Buffer.alloc(0), 3);
  b.addRevision(f1, 1, s1, "bin.dat");
  b.addRevision(f2, 2, s2, "text.txt");
  b.addRevision(f3, 3, s3, "empty.txt");
  b.setHead(f1, 1); b.setHead(f2, 2); b.setHead(f3, 3);
  return b.build(3);
}

export interface FileDesc {
  fileId: string; path: string | null; headRevision: number | null;
  objectSerial: number | null; repIdentity: number | null; repVersion: number | null;
  contentBase64: string;
}

export interface ContainerDesc {
  mode: number; generation: number;
  recoveryStatus: string; acceptedGeneration: number;
  files: FileDesc[];
}

/** Describe a container's canonical interpretation in a language-neutral way. */
export function describe(data: Buffer): ContainerDesc {
  const parsed = parse(data);
  const c = new VsnContainer(data);
  const pathByFile = new Map<string, string>();
  const revByFile = new Map<string, number>();
  const serialByRev = new Map<number, number | null>();
  const revFile = new Map<number, string>();
  for (const rec of parsed.records) {
    if (rec.rtype === REC_REVISION) {
      const rid = rec.getField(FID_REV_ID)!.asUvarint();
      const fidF = rec.getField(FID_REV_FILE_ID)!;
      const key = Buffer.from(fidF.value).toString("hex");
      revFile.set(Number(rid), key);
      const p = rec.getField(FID_REV_PATH);
      if (p) pathByFile.set(key, p.value.toString("utf8"));
      const os = rec.getField(FID_REV_OBJECT_SERIAL);
      serialByRev.set(Number(rid), os ? Number(os.asUvarint()) : null);
    } else if (rec.rtype === REC_FILE_HEAD) {
      const key = Buffer.from(rec.getField(FID_HEAD_FILE_ID)!.value).toString("hex");
      revByFile.set(key, Number(rec.getField(FID_HEAD_REV_ID)!.asUvarint()));
    }
  }
  const files: FileDesc[] = [];
  for (const rec of parsed.records) {
    if (rec.rtype !== REC_FILE_IDENTITY) continue;
    const key = Buffer.from(rec.getField(FID_FILE_ID)!.value).toString("hex");
    const head = revByFile.has(key) ? revByFile.get(key)! : null;
    const serial = head !== null ? serialByRev.get(head) ?? null : null;
    let content = Buffer.alloc(0);
    let repIdentity: number | null = null;
    let repVersion: number | null = null;
    if (serial !== null) {
      const info = c.objects.find((o) => Number(o.serial) === serial);
      if (info) {
        const rem = info.descriptor;
        repIdentity = rem.readUInt16BE(0);
        const off = { value: 2 };
        repVersion = Number(readUvarint(rem, off));
      }
      content = c.materialize(BigInt(serial));
    }
    files.push({
      fileId: key, path: pathByFile.get(key) ?? null, headRevision: head,
      objectSerial: serial, repIdentity, repVersion,
      contentBase64: content.toString("base64"),
    });
  }
  files.sort((x, y) => x.fileId.localeCompare(y.fileId));
  const rr = recover(data);
  return {
    mode: parsed.mode ?? 0, generation: Number(parsed.trailerGeneration),
    recoveryStatus: rr.status, acceptedGeneration: rr.acceptedGeneration, files,
  };
}

/** Write every scenario into <dir>/<lang>/; returns the written file names. */
export function writeAll(dir: string, lang: string): string[] {
  const out = path.join(dir, lang);
  fs.mkdirSync(out, { recursive: true });
  const names: string[] = [];
  for (const s of SCENARIOS) {
    fs.writeFileSync(path.join(out, s + ".vsn"), buildScenario(s));
    names.push(s);
  }
  return names;
}

