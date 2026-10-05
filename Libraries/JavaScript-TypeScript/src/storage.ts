import type { VsnStore } from "./store.js";
import { REC_CONTENT_OBJECT } from "./constants.js";

/** Storage statistics for a container (derived observation). */
export interface StorageStats {
  containerBytes: number;
  recordCount: number;
  objectCount: number;
  fileCount: number;
  revisionCount: number;
  indexEntries: number;
  cacheEntries: number;
  cacheBytes: number;
}

/**
 * Manages derived storage (indexes, caches) for a VsnStore.
 *
 * All derived data is rebuildable from canonical VSN content. Recovery and
 * acceptance never depend on it (SR-02, SR-03); it is never canonical
 * authority. Deleting every derived structure leaves recovery functional.
 */
export class StorageManager {
  private objectIndex = new Map<number, unknown>();
  private fileIndex = new Map<string, Buffer>();
  private contentCache = new Map<number, Buffer>();
  private valid = false;

  /** Build derived indexes from canonical state. */
  buildIndexes(store: VsnStore): void {
    this.objectIndex.clear();
    this.fileIndex.clear();
    for (const serial of store.listObjects()) this.objectIndex.set(serial, store.getObjectInfo(serial));
    for (const info of store.listFiles()) if (info.path) this.fileIndex.set(info.path, info.fileId);
    this.valid = true;
  }

  /** Invalidate all derived data (simulates derived-store deletion). */
  invalidate(): void {
    this.objectIndex.clear();
    this.fileIndex.clear();
    this.contentCache.clear();
    this.valid = false;
  }

  /** Rebuild derived data from canonical state. */
  rebuild(store: VsnStore): void {
    this.invalidate();
    this.buildIndexes(store);
  }

  /** Garbage-collect cached content; returns entries removed. */
  gc(): number {
    const n = this.contentCache.size;
    this.contentCache.clear();
    return n;
  }

  /** Store a derived cache entry (never canonical). */
  cachePut(serial: number, content: Buffer): void { this.contentCache.set(serial, content); }
  cacheGet(serial: number): Buffer | undefined { return this.contentCache.get(serial); }
  cacheCount(): number { return this.contentCache.size; }

  /** Canonical object-record count observed via the derived index. */
  canonicalObjectCount(store: VsnStore): number {
    const parsed = store.parsedContainer;
    if (!parsed) return 0;
    return parsed.records.filter((r) => r.rtype === REC_CONTENT_OBJECT).length;
  }

  /** Storage statistics. */
  stats(store: VsnStore): StorageStats {
    const parsed = store.parsedContainer;
    let cacheBytes = 0;
    for (const v of this.contentCache.values()) cacheBytes += v.length;
    return {
      containerBytes: store.canonicalData.length,
      recordCount: parsed ? parsed.records.length : 0,
      objectCount: store.listObjects().length,
      fileCount: store.listFiles().length,
      revisionCount: store.listRevisions().length,
      indexEntries: this.objectIndex.size + this.fileIndex.size,
      cacheEntries: this.contentCache.size,
      cacheBytes,
    };
  }

  get isValid(): boolean { return this.valid; }
  lookupFile(path: string): Buffer | undefined { return this.fileIndex.get(path); }
}
