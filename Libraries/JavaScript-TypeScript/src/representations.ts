import { REP_DIRECT_1, REP_EXTENTS_1, REP_VERSION_1, OP_NESTED, OP_LITERAL_BYTES, OP_OBJECT_SOURCE, OP_NUMERIC } from "./constants.js";
import { VsnError, readUvarint } from "./primitives.js";

export function parseObjectHeader(descriptor: Buffer): { identity: number; version: number; remainder: Buffer } {
  if (descriptor.length < 2) throw new VsnError(0x0002, "truncated object header", 0);
  const off = { value: 0 };
  const identity = (descriptor[0] << 8) | descriptor[1];
  off.value = 2;
  const version = Number(readUvarint(descriptor, off));
  return { identity, version, remainder: descriptor.subarray(off.value) };
}

export function materializeDirect(remainder: Buffer): Buffer {
  return Buffer.from(remainder);
}

type Operand = { kind: "lit"; value: Buffer } | { kind: "src"; serial: bigint } | { kind: "num"; value: bigint };

function readOperand(buf: Buffer, off: { value: number }): Operand {
  const kind = Number(readUvarint(buf, off));
  if (kind === OP_LITERAL_BYTES) {
    const ln = Number(readUvarint(buf, off));
    if (off.value + ln > buf.length) throw new VsnError(0x0002, "truncated literal operand", off.value);
    const val = buf.subarray(off.value, off.value + ln);
    off.value += ln;
    return { kind: "lit", value: Buffer.from(val) };
  }
  if (kind === OP_OBJECT_SOURCE) return { kind: "src", serial: readUvarint(buf, off) };
  if (kind === OP_NUMERIC) return { kind: "num", value: readUvarint(buf, off) };
  throw new VsnError(0x0006, `unknown operand kind ${kind}`);
}

function applyOperation(operands: Operand[], resolve: (serial: bigint) => Buffer, visited: Set<bigint>): Buffer {
  if (operands.length === 0) throw new VsnError(0x000C, "empty operation");
  const head = operands[0];
  if (head.kind === "src") {
    if (operands.length !== 3 || operands[1].kind !== "num" || operands[2].kind !== "num")
      throw new VsnError(0x000C, "malformed COPY");
    const src = head.serial;
    const off = Number(operands[1].value);
    const len = Number(operands[2].value);
    if (visited.has(src)) throw new VsnError(0x000C, `cycle at ${src}`);
    const srcBytes = resolve(src);
    if (off < 0 || len < 0 || off + len > srcBytes.length) throw new VsnError(0x000C, "COPY out of bounds");
    return srcBytes.subarray(off, off + len);
  }
  if (head.kind === "lit") return head.value;
  throw new VsnError(0x000C, `unknown op head ${head.kind}`);
}

export function materializeExtents(remainder: Buffer, resolve: (serial: bigint) => Buffer): Buffer {
  const off = { value: 0 };
  const opCount = Number(readUvarint(remainder, off));
  const parts: Buffer[] = [];
  for (let i = 0; i < opCount; i++) {
    const kind = Number(readUvarint(remainder, off));
    if (kind !== OP_NESTED) throw new VsnError(0x000C, `op must be NESTED, got ${kind}`);
    const n = Number(readUvarint(remainder, off));
    const operands: Operand[] = [];
    for (let j = 0; j < n; j++) operands.push(readOperand(remainder, off));
    parts.push(applyOperation(operands, resolve, new Set()));
  }
  if (off.value !== remainder.length) throw new VsnError(0x000C, "trailing bytes");
  return Buffer.concat(parts);
}

/** Yield DIRECT-1 content in chunks without copying the whole object. */
export function* materializeDirectStream(remainder: Buffer, chunkSize = 65536): Generator<Buffer> {
  for (let i = 0; i < remainder.length; i += chunkSize)
    yield remainder.subarray(i, Math.min(i + chunkSize, remainder.length));
}

/**
 * Yield EXTENTS-1 content in chunks. LITERAL and COPY operations are emitted
 * as chunked views; a COPY source is resolved because it needs random access.
 */
export function* materializeExtentsStream(
  remainder: Buffer, resolve: (serial: bigint) => Buffer, chunkSize = 65536,
): Generator<Buffer> {
  const off = { value: 0 };
  const opCount = Number(readUvarint(remainder, off));
  for (let i = 0; i < opCount; i++) {
    const kind = Number(readUvarint(remainder, off));
    if (kind !== OP_NESTED) throw new VsnError(0x000C, `op must be NESTED, got ${kind}`);
    const n = Number(readUvarint(remainder, off));
    const operands: Operand[] = [];
    for (let j = 0; j < n; j++) operands.push(readOperand(remainder, off));
    const buf = applyOperation(operands, resolve, new Set());
    for (let k = 0; k < buf.length; k += chunkSize)
      yield buf.subarray(k, Math.min(k + chunkSize, buf.length));
  }
  if (off.value !== remainder.length) throw new VsnError(0x000C, "trailing bytes");
}
