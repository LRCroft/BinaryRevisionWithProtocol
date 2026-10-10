import { parse } from "./container.js";
import type { ParsedContainer } from "./container.js";
import { parseObjectHeader } from "./representations.js";
import { recover } from "./recovery.js";
import { VsnContainer } from "./api.js";
import { VsnError } from "./errors.js";
import {
  REC_MODE_DECLARATION, REC_FILE_IDENTITY, REC_REVISION, REC_CONTENT_OBJECT,
  REC_FILE_HEAD, FID_MODE, FID_FILE_ID, FID_REV_ID, FID_OBJECT_SERIAL,
  FID_OBJECT_SIZE,
  FID_REV_FILE_ID, FID_REV_OBJECT_SERIAL, FID_HEAD_FILE_ID, FID_HEAD_REV_ID,
  MODE_MODERN, MODE_ENTERPRISE, REP_EXTENTS_1,
} from "./constants.js";

export type ValidationLevel =
  | "Structural" | "Semantic" | "Recovery" | "Content" | "Full";

/** Structural: magic, versions, framing, lengths, ordering. */
export function validateStructural(data: Buffer): void {
  parse(data);
}

function checkMode(parsed: ParsedContainer): void {
  const modes = parsed.records.filter((r) => r.rtype === REC_MODE_DECLARATION);
  if (modes.length !== 1)
    throw new VsnError(0x000C, `expected exactly one ModeDeclaration, got ${modes.length}`);
  const m = modes[0].getField(FID_MODE);
  if (!m || m.value.length !== 1)
    throw new VsnError(0x000C, "ModeDeclaration missing mode value");
  const mode = m.value[0];
  if (mode !== MODE_MODERN && mode !== MODE_ENTERPRISE)
    throw new VsnError(0x0001, `reserved mode value 0x${mode.toString(16).padStart(2, "0")}`);
  // GR-43: ENTERPRISE must not use EXTENTS-1 reconstruction semantics.
  if (mode === MODE_ENTERPRISE) {
    for (const obj of parsed.objects) {
      const { identity } = parseObjectHeader(obj.descriptor);
      if (identity === REP_EXTENTS_1)
        throw new VsnError(0x000C, "ENTERPRISE mode forbids EXTENTS-1 (GR-43)");
    }
  }
}
function checkIdentities(parsed: ParsedContainer): void {
  const seenFile = new Set<string>();
  const seenRev = new Set<bigint>();
  const seenObj = new Set<bigint>();
  for (const rec of parsed.records) {
    if (rec.rtype === REC_FILE_IDENTITY) {
      const f = rec.getField(FID_FILE_ID);
      const key = f ? f.value.toString("hex") : "null";
      if (seenFile.has(key)) throw new VsnError(0x000A, "duplicate FileIdentity");
      seenFile.add(key);
    } else if (rec.rtype === REC_REVISION) {
      const r = rec.getField(FID_REV_ID);
      if (r) {
        const rid = r.asUvarint();
        if (seenRev.has(rid)) throw new VsnError(0x000A, `duplicate RevisionId ${rid}`);
        seenRev.add(rid);
      }
    } else if (rec.rtype === REC_CONTENT_OBJECT) {
      const s = rec.getField(FID_OBJECT_SERIAL);
      if (s) {
        const sid = s.asUvarint();
        if (seenObj.has(sid)) throw new VsnError(0x000A, `duplicate ObjectSerial ${sid}`);
        seenObj.add(sid);
      }
    }
  }
}

/** Dependency validation: every canonical reference must resolve (RX-*). */
function checkReferences(parsed: ParsedContainer): void {
  const fileIds = new Set<string>();
  for (const r of parsed.records) {
    if (r.rtype === REC_FILE_IDENTITY) {
      const f = r.getField(FID_FILE_ID);
      if (f) fileIds.add(f.value.toString("hex"));
    }
  }
  const objIds = new Set<string>();
  for (const o of parsed.objects) objIds.add(o.serial.toString());
  const revIds = new Set<string>();
  for (const r of parsed.records) {
    if (r.rtype === REC_REVISION) {
      const r2 = r.getField(FID_REV_ID);
      if (r2) revIds.add(r2.asUvarint().toString());
    }
  }
  for (const rec of parsed.records) {
    if (rec.rtype === REC_REVISION) {
      const f = rec.getField(FID_REV_FILE_ID);
      if (!f || !fileIds.has(f.value.toString("hex")))
        throw new VsnError(0x0009, "Revision references missing FileId");
      const obj = rec.getField(FID_REV_OBJECT_SERIAL);
      if (obj && !objIds.has(obj.asUvarint().toString()))
        throw new VsnError(0x0008, "Revision references missing ObjectSerial");
    } else if (rec.rtype === REC_FILE_HEAD) {
      const f = rec.getField(FID_HEAD_FILE_ID);
      if (!f || !fileIds.has(f.value.toString("hex")))
        throw new VsnError(0x0009, "FileHead references missing FileId");
      const r = rec.getField(FID_HEAD_REV_ID);
      if (!r || !revIds.has(r.asUvarint().toString()))
        throw new VsnError(0x0009, "FileHead references missing RevisionId");
    }
  }
}
/** Semantic: identity uniqueness, reference resolution, mode constraints. */
export function validateSemantic(data: Buffer): void {
  const parsed = parse(data);
  checkMode(parsed);
  checkIdentities(parsed);
  checkReferences(parsed);
}

/**
 * Content: dependency validation plus dependency cycle detection.
 * Every object must materialize; a cycle is an invalid canonical state.
 *
 * DR-6 additionally requires that when 0x0511 is PRESENT, the materialized
 * output length MUST equal it; a mismatch is invalid canonical state (0x000C,
 * matching frozen vector EXT-12). Absence of 0x0511 stays fully valid (SR-27).
 * Reuses the existing INVALID_CANONICAL_STATE identifier; no new identifier is
 * introduced, and no derived storage is consulted.
 */
export function validateContent(data: Buffer): void {
  const parsed = parse(data);
  const declared = new Map<number, bigint>();
  for (const rec of parsed.records) {
    if (rec.rtype !== REC_CONTENT_OBJECT) continue;
    const s = rec.getField(FID_OBJECT_SERIAL);
    const z = rec.getField(FID_OBJECT_SIZE);
    if (s && z) declared.set(Number(s.asUvarint()), z.asUvarint());
  }
  const c = new VsnContainer(data);
  for (const obj of c.objects) {
    const content = c.materialize(obj.serial);
    const want = declared.get(Number(obj.serial));
    if (want !== undefined && want !== BigInt(content.length))
      throw new VsnError(0x000C,
        `declared size ${want} does not match materialized length ` +
        `${content.length} for ObjectSerial ${obj.serial} (DR-6)`);
  }
}

/** Run validation at a requested depth. */
export function validate(data: Buffer, level: ValidationLevel = "Full"): void {
  const levels: ValidationLevel[] = ["Structural", "Semantic", "Recovery", "Content", "Full"];
  if (!levels.includes(level)) throw new Error(`unknown validation level ${level}`);
  if (level === "Structural" || level === "Full") validateStructural(data);
  if (level === "Semantic" || level === "Full") validateSemantic(data);
  if (level === "Recovery" || level === "Full") recover(data);
  if (level === "Content" || level === "Full") validateContent(data);
}