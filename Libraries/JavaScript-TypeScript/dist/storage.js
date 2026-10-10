"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.StorageManager = void 0;
const constants_js_1 = require("./constants.js");
/**
 * Manages derived storage (indexes, caches) for a VsnStore.
 *
 * All derived data is rebuildable from canonical VSN content. Recovery and
 * acceptance never depend on it (SR-02, SR-03); it is never canonical
 * authority. Deleting every derived structure leaves recovery functional.
 */
class StorageManager {
    objectIndex = new Map();
    fileIndex = new Map();
    contentCache = new Map();
    valid = false;
    /** Build derived indexes from canonical state. */
    buildIndexes(store) {
        this.objectIndex.clear();
        this.fileIndex.clear();
        for (const serial of store.listObjects())
            this.objectIndex.set(serial, store.getObjectInfo(serial));
        for (const info of store.listFiles())
            if (info.path)
                this.fileIndex.set(info.path, info.fileId);
        this.valid = true;
    }
    /** Invalidate all derived data (simulates derived-store deletion). */
    invalidate() {
        this.objectIndex.clear();
        this.fileIndex.clear();
        this.contentCache.clear();
        this.valid = false;
    }
    /** Rebuild derived data from canonical state. */
    rebuild(store) {
        this.invalidate();
        this.buildIndexes(store);
    }
    /** Garbage-collect cached content; returns entries removed. */
    gc() {
        const n = this.contentCache.size;
        this.contentCache.clear();
        return n;
    }
    /** Store a derived cache entry (never canonical). */
    cachePut(serial, content) { this.contentCache.set(serial, content); }
    cacheGet(serial) { return this.contentCache.get(serial); }
    cacheCount() { return this.contentCache.size; }
    /** Canonical object-record count observed via the derived index. */
    canonicalObjectCount(store) {
        const parsed = store.parsedContainer;
        if (!parsed)
            return 0;
        return parsed.records.filter((r) => r.rtype === constants_js_1.REC_CONTENT_OBJECT).length;
    }
    /** Storage statistics. */
    stats(store) {
        const parsed = store.parsedContainer;
        let cacheBytes = 0;
        for (const v of this.contentCache.values())
            cacheBytes += v.length;
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
    get isValid() { return this.valid; }
    lookupFile(path) { return this.fileIndex.get(path); }
}
exports.StorageManager = StorageManager;
//# sourceMappingURL=storage.js.map