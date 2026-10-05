import {
  MAGIC, FID_RECORDS_END, REC_END_OF_RECORDS, REC_MODE_DECLARATION,
  REP_DIRECT_1, REP_EXTENTS_1, REP_VERSION_1,
  OP_LITERAL_BYTES, OP_OBJECT_SOURCE, OP_NUMERIC, OP_NESTED,
} from "./constants.js";
import { putU16, putUvarint } from "./primitives.js";

export interface EncodedField { fid: number; value: Buffer; }
export interface EncodedRecord { rtype: number; fields: EncodedField[]; }
export interface EncodedObject { serial: bigint; descriptor: Buffer; }

function field(fid: number, value: Buffer): Buffer {
  return Buffer.concat([putU16(fid), putUvarint(value.length), value]);
}

function record(rtype: number, fields: EncodedField[]): Buffer {
  const payload = Buffer.concat(fields.map((f) => field(f.fid, f.value)));
  return Buffer.concat([putU16(rtype), putUvarint(payload.length), payload]);
}

/**
 * Encode a canonical VSN-1 container.
 * GR-13: the trailer canonical record count excludes ModeDeclaration.
 * Identity is never derived from a hash or an offset.
 */
export function encode(
  _mode: number,
  records: EncodedRecord[],
  objects: EncodedObject[],
  generation: bigint | number,
): Buffer {
  const parts: Buffer[] = [
    MAGIC, putU16(1), putU16(1), field(FID_RECORDS_END, Buffer.alloc(0)),
  ];
  for (const r of records) parts.push(record(r.rtype, r.fields));
  parts.push(putU16(REC_END_OF_RECORDS));
  for (const o of objects) {
    parts.push(putUvarint(o.serial), putUvarint(o.descriptor.length), o.descriptor);
  }
  parts.push(putUvarint(0));
  let canonical = 0;
  for (const r of records) if (r.rtype !== REC_MODE_DECLARATION) canonical += 1;
  parts.push(putUvarint(canonical), putUvarint(generation));
  return Buffer.concat(parts);
}

/** DR-0 descriptor: DIRECT-1 v1 header + raw logical content. */
export function direct1Descriptor(content: Buffer): Buffer {
  return Buffer.concat([putU16(REP_DIRECT_1), putUvarint(REP_VERSION_1), content]);
}

/** LITERAL operation: NESTED[ LITERAL_BYTES(bytes), NUMERIC(0) ]. */
export function literalOperation(bytes: Buffer): Buffer {
  return Buffer.concat([
    putUvarint(OP_NESTED), putUvarint(2),
    putUvarint(OP_LITERAL_BYTES), putUvarint(bytes.length), bytes,
    putUvarint(OP_NUMERIC), putUvarint(0),
  ]);
}

/** COPY operation: NESTED[ OBJECT_SOURCE(serial), NUMERIC(offset), NUMERIC(length) ]. */
export function copyOperation(
  serial: bigint | number, offset: bigint | number, length: bigint | number,
): Buffer {
  return Buffer.concat([
    putUvarint(OP_NESTED), putUvarint(3),
    putUvarint(OP_OBJECT_SOURCE), putUvarint(serial),
    putUvarint(OP_NUMERIC), putUvarint(offset),
    putUvarint(OP_NUMERIC), putUvarint(length),
  ]);
}

/** DR-0 descriptor: EXTENTS-1 v1 header + operation collection. */
export function extents1Descriptor(operations: Buffer[]): Buffer {
  return Buffer.concat([
    putU16(REP_EXTENTS_1), putUvarint(REP_VERSION_1),
    putUvarint(operations.length), ...operations,
  ]);
}

