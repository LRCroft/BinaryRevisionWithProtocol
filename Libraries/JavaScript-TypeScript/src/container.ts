import { MAGIC, FID_RECORDS_END, FID_MODE, REC_END_OF_RECORDS, REC_MODE_DECLARATION, REC_STORAGE_POLICY, FID_STORAGE_POLICY } from "./constants.js";
import { VsnError, readUvarint, readU16 } from "./primitives.js";

/** Bounds-checked slice: physical end mid-unit is truncation (GR-47). */
function sliceChecked(data: Buffer, off: { value: number }, len: number, what: string): Buffer {
  if (len < 0 || off.value + len > data.length) {
    throw new VsnError(0x0002, `truncated ${what}`, off.value);
  }
  const out = data.subarray(off.value, off.value + len);
  off.value += len;
  return out;
}

export interface Field {
  fid: number;
  value: Buffer;
  asUvarint(): bigint;
}

export interface Record {
  rtype: number;
  payload: Buffer;
  fields: Field[];
  byteOffset: number;
  getField(fid: number): Field | undefined;
}

export interface ObjectEntry {
  serial: bigint;
  length: number;
  descriptor: Buffer;
  byteOffset: number;
}

export interface ParsedContainer {
  containerFormatVersion: number;
  encodingVersion: number;
  records: Record[];
  objects: ObjectEntry[];
  trailerRecordCount: bigint;
  trailerGeneration: bigint;
  mode: number | null;
  storagePolicy: number | null;
  byteLength: number;
}

function makeField(fid: number, value: Buffer): Field {
  return {
    fid,
    value,
    asUvarint() {
      const off = { value: 0 };
      return readUvarint(this.value, off);
    },
  };
}

function makeRecord(rtype: number, payload: Buffer, byteOffset: number): Record {
  return {
    rtype,
    payload,
    fields: [],
    byteOffset,
    getField(fid: number) {
      return this.fields.find((f) => f.fid === fid);
    },
  };
}

function parseFields(payload: Buffer, rec: Record): void {
  const off = { value: 0 };
  let last = -1;
  while (off.value < payload.length) {
    const start = off.value;
    const fid = readU16(payload, off);
    if (last >= 0 && fid <= last) throw new VsnError(0x0011, `FieldId ${fid} not ascending`, start);
    last = fid;
    const ln = readUvarint(payload, off);
    const val = sliceChecked(payload, off, Number(ln), "field value");
    rec.fields.push(makeField(fid, val));
  }
}

export function parse(data: Buffer): ParsedContainer {
  const off = { value: 0 };
  if (data.length < 4 || !data.subarray(0, 4).equals(MAGIC))
    throw new VsnError(0x0001, "bad magic", 0);
  off.value = 4;
  const cfv = readU16(data, off);
  if (cfv !== 1) throw new VsnError(0x0003, `unsupported CFV ${cfv}`);
  const ev = readU16(data, off);
  if (ev !== 1) throw new VsnError(0x0004, `unsupported EV ${ev}`);

  // Header fields
  while (true) {
    const fid = readU16(data, off);
    const ln = readUvarint(data, off);
    if (fid === FID_RECORDS_END) {
      if (ln !== BigInt(0)) throw new VsnError(0x0001, "RecordsEnd length != 0");
      break;
    }
    sliceChecked(data, off, Number(ln), "header field");
  }

  const records: Record[] = [];
  while (true) {
    const start = off.value;
    const rt = readU16(data, off);
    if (rt === REC_END_OF_RECORDS) break;
    const rl = readUvarint(data, off);
    const payload = sliceChecked(data, off, Number(rl), "record payload");
    const rec = makeRecord(rt, payload, start);
    if (rt <= 0x0008) parseFields(payload, rec);
    records.push(rec);
  }

  const objects: ObjectEntry[] = [];
  while (true) {
    const start = off.value;
    const serial = readUvarint(data, off);
    if (serial === BigInt(0)) break;
    const ol = readUvarint(data, off);
    const desc = sliceChecked(data, off, Number(ol), "object descriptor");
    objects.push({ serial, length: Number(ol), descriptor: desc, byteOffset: start });
  }

  const rc = readUvarint(data, off);
  const gen = readUvarint(data, off);

  let mode: number | null = null;
  let storagePolicy: number | null = null;
  for (const rec of records) {
    if (rec.rtype === REC_MODE_DECLARATION) {
      const m = rec.getField(FID_MODE);
      if (m && m.value.length > 0) mode = m.value[0];
    }
    if (rec.rtype === REC_STORAGE_POLICY) {
      const sp = rec.getField(FID_STORAGE_POLICY);
      if (sp && sp.value.length > 0) storagePolicy = sp.value[0];
    }
  }

  return {
    containerFormatVersion: cfv,
    encodingVersion: ev,
    records,
    objects,
    trailerRecordCount: rc,
    trailerGeneration: gen,
    mode,
    storagePolicy,
    byteLength: data.length,
  };
}
