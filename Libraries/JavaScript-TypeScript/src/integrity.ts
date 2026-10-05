import { createHash } from "crypto";
import { VsnError } from "./errors.js";
import { validate } from "./validate.js";
import type { VsnStore } from "./store.js";

/**
 * Library-level integrity verification over the canonical state.
 *
 * Hashes are verification/acceleration mechanisms ONLY; they are never
 * canonical identity and never recovery authority (BP-09, SR-40).
 */
export interface IntegrityReport {
  valid: boolean;
  mode: number;
  generation: number;
  fileCount: number;
  objectCount: number;
  revisionCount: number;
  contentHash: string;
  errors: string[];
}

/** Hash the canonical bytes (verification only, never identity). */
export function canonicalHash(data: Buffer): string {
  return createHash("sha256").update(data).digest("hex");
}

/**
 * Verify a store: structural/semantic/recovery/content validation plus a
 * consistency check that every accepted file materializes without error.
 */
export function verifyIntegrity(store: VsnStore): IntegrityReport {
  const errors: string[] = [];
  // Verify the committed canonical state when one exists.
  const canonical = store.canonicalData;
  const data = canonical.length > 0 ? canonical : store.toBytes();
  try {
    validate(data, "Full");
  } catch (e) {
    errors.push(e instanceof Error ? e.message : String(e));
  }
  for (const info of store.listFiles()) {
    if (!store.fileExists(info.fileId)) continue;
    try {
      store.readFile(info.fileId);
    } catch (e) {
      errors.push(`${info.path}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }
  const meta = store.inspect();
  return {
    valid: errors.length === 0, mode: meta.mode, generation: meta.generation,
    fileCount: meta.fileCount, objectCount: meta.objectCount,
    revisionCount: meta.revisionCount, contentHash: canonicalHash(data), errors,
  };
}
