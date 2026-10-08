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
export declare function canonicalHash(data: Buffer): string;
/**
 * Verify a store: structural/semantic/recovery/content validation plus a
 * consistency check that every accepted file materializes without error.
 */
export declare function verifyIntegrity(store: VsnStore): IntegrityReport;
