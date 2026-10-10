import type { VsnStore } from "./store.js";

/** Object-set difference (derived data; never canonical). */
export interface ObjectDiff { shared: number[]; added: number[]; removed: number[]; }

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
export function diffObjects(left: number[], right: number[]): ObjectDiff {
  const l = new Set(left), r = new Set(right);
  const shared = [...l].filter((s) => r.has(s)).sort((a, b) => a - b);
  const added = [...r].filter((s) => !l.has(s)).sort((a, b) => a - b);
  const removed = [...l].filter((s) => !r.has(s)).sort((a, b) => a - b);
  return { shared, added, removed };
}

/** Diff files between two stores by path and logical content. */
export function diffFiles(left: VsnStore, right: VsnStore): FileDiff {
  const leftFiles = new Map<string, Buffer>();
  for (const i of left.listFiles()) if (i.path) leftFiles.set(i.path, i.fileId);
  const rightFiles = new Map<string, Buffer>();
  for (const i of right.listFiles()) if (i.path) rightFiles.set(i.path, i.fileId);
  const result: FileDiff = { added: [], deleted: [], modified: [], unchanged: [], renamed: [] };
  const all = [...new Set([...leftFiles.keys(), ...rightFiles.keys()])].sort();
  for (const path of all) {
    const inLeft = leftFiles.has(path);
    const inRight = rightFiles.has(path);
    if (inLeft && !inRight) result.deleted.push(path);
    else if (inRight && !inLeft) result.added.push(path);
    else {
      const a = left.readFile(leftFiles.get(path)!);
      const b = right.readFile(rightFiles.get(path)!);
      if (a.equals(b)) result.unchanged.push(path);
      else result.modified.push(path);
    }
  }
  return result;
}

/** Diff logical content between two revisions of one file. */
export function diffRevisions(
  store: VsnStore, fileId: Buffer, revA: number, revB: number,
): RevisionDiff {
  const contentA = store.checkoutRevision(fileId, revA);
  const contentB = store.checkoutRevision(fileId, revB);
  const changed = !contentA.equals(contentB);
  return {
    revisionA: revA, revisionB: revB, contentA, contentB,
    changed, addedBytes: changed ? contentB.length - contentA.length : 0,
  };
}

export function contentEqual(a: Buffer, b: Buffer): boolean { return a.equals(b); }
