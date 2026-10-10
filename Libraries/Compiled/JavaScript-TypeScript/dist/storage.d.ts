import type { VsnStore } from "./store.js";
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
export declare class StorageManager {
    private objectIndex;
    private fileIndex;
    private contentCache;
    private valid;
    /** Build derived indexes from canonical state. */
    buildIndexes(store: VsnStore): void;
    /** Invalidate all derived data (simulates derived-store deletion). */
    invalidate(): void;
    /** Rebuild derived data from canonical state. */
    rebuild(store: VsnStore): void;
    /** Garbage-collect cached content; returns entries removed. */
    gc(): number;
    /** Store a derived cache entry (never canonical). */
    cachePut(serial: number, content: Buffer): void;
    cacheGet(serial: number): Buffer | undefined;
    cacheCount(): number;
    /** Canonical object-record count observed via the derived index. */
    canonicalObjectCount(store: VsnStore): number;
    /** Storage statistics. */
    stats(store: VsnStore): StorageStats;
    get isValid(): boolean;
    lookupFile(path: string): Buffer | undefined;
}
