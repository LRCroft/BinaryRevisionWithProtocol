import type { VsnStore } from "./store.js";
/** A three-way merge conflict. */
export interface Conflict {
    path: string;
    baseContent: Buffer;
    oursContent: Buffer;
    theirsContent: Buffer;
}
/** Result of a three-way merge (library state only; no protocol records). */
export interface MergeResult {
    mergedFiles: Map<string, Buffer>;
    conflicts: Conflict[];
    added: string[];
    deleted: string[];
}
export declare function hasConflicts(result: MergeResult): boolean;
/**
 * Three-way merge of file states.
 *
 * base = common ancestor, ours = our changes, theirs = their changes.
 * Non-conflicting changes auto-merge; conflicting changes are reported and
 * never silently dropped (no silent data loss).
 */
export declare function threeWayMerge(base: VsnStore, ours: VsnStore, theirs: VsnStore): MergeResult;
/** Resolve a conflict explicitly by supplying the final content. */
export declare function resolveConflict(result: MergeResult, path: string, content: Buffer): void;
