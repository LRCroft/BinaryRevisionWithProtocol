import type { VsnStore } from "./store.js";
/** Object-set difference (derived data; never canonical). */
export interface ObjectDiff {
    shared: number[];
    added: number[];
    removed: number[];
}
/** File-state difference between two stores. */
export interface FileDiff {
    added: string[];
    deleted: string[];
    modified: string[];
    unchanged: string[];
    renamed: [string, string][];
}
/** Revision content difference. */
export interface RevisionDiff {
    revisionA: number;
    revisionB: number;
    contentA: Buffer;
    contentB: Buffer;
    changed: boolean;
    addedBytes: number;
}
/** Diff two object-serial sets. */
export declare function diffObjects(left: number[], right: number[]): ObjectDiff;
/** Diff files between two stores by path and logical content. */
export declare function diffFiles(left: VsnStore, right: VsnStore): FileDiff;
/** Diff logical content between two revisions of one file. */
export declare function diffRevisions(store: VsnStore, fileId: Buffer, revA: number, revB: number): RevisionDiff;
export declare function contentEqual(a: Buffer, b: Buffer): boolean;
