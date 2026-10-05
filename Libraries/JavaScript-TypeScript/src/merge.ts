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

export function hasConflicts(result: MergeResult): boolean {
  return result.conflicts.length > 0;
}

function filesByPath(store: VsnStore): Map<string, Buffer> {
  const map = new Map<string, Buffer>();
  for (const i of store.listFiles()) if (i.path) map.set(i.path, i.fileId);
  return map;
}

function readOrNull(store: VsnStore, fileId: Buffer | undefined): Buffer | null {
  return fileId === undefined ? null : store.readFile(fileId);
}

/**
 * Three-way merge of file states.
 *
 * base = common ancestor, ours = our changes, theirs = their changes.
 * Non-conflicting changes auto-merge; conflicting changes are reported and
 * never silently dropped (no silent data loss).
 */
export function threeWayMerge(base: VsnStore, ours: VsnStore, theirs: VsnStore): MergeResult {
  const baseFiles = filesByPath(base);
  const oursFiles = filesByPath(ours);
  const theirsFiles = filesByPath(theirs);
  const result: MergeResult = { mergedFiles: new Map(), conflicts: [], added: [], deleted: [] };
  const all = [...new Set([...baseFiles.keys(), ...oursFiles.keys(), ...theirsFiles.keys()])].sort();

  for (const path of all) {
    const baseC = readOrNull(base, baseFiles.get(path));
    const oursC = readOrNull(ours, oursFiles.get(path));
    const theirsC = readOrNull(theirs, theirsFiles.get(path));
    const eq = (a: Buffer | null, b: Buffer | null): boolean =>
      a === null ? b === null : b !== null && a.equals(b);

    if (eq(oursC, theirsC)) {
      if (oursC !== null) result.mergedFiles.set(path, oursC);
      continue;
    }
    if (eq(oursC, baseC) && !eq(theirsC, baseC)) {
      if (theirsC !== null) result.mergedFiles.set(path, theirsC);
      else result.deleted.push(path);
      continue;
    }
    if (eq(theirsC, baseC) && !eq(oursC, baseC)) {
      if (oursC !== null) result.mergedFiles.set(path, oursC);
      else result.deleted.push(path);
      continue;
    }
    result.conflicts.push({
      path, baseContent: baseC ?? Buffer.alloc(0),
      oursContent: oursC ?? Buffer.alloc(0), theirsContent: theirsC ?? Buffer.alloc(0),
    });
  }
  return result;
}

/** Resolve a conflict explicitly by supplying the final content. */
export function resolveConflict(result: MergeResult, path: string, content: Buffer): void {
  result.conflicts = result.conflicts.filter((c) => c.path !== path);
  result.mergedFiles.set(path, content);
}
