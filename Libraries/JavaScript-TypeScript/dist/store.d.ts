import type { ParsedContainer } from "./container.js";
declare class Mutex {
    private _queue;
    private _locked;
    acquire(): Promise<void>;
    release(): void;
    withLock<T>(fn: () => T): Promise<T>;
}
export { Mutex };
export interface FileInfo {
    fileId: Buffer;
    path: string | null;
    headRevision: number | null;
}
export interface RevisionInfo {
    revisionId: number;
    fileId: Buffer;
    objectSerial: number | null;
    path: string | null;
    presence: number;
}
export interface ObjectInfo {
    serial: number;
    length: number;
    representationIdentity: number;
    representationVersion: number;
}
export interface ContainerInfo {
    mode: number;
    generation: number;
    fileCount: number;
    objectCount: number;
    revisionCount: number;
}
/** Generated FileId: 16 opaque bytes of identity, never a content hash. */
export declare function generateFileId(): Buffer;
/** Mutable VSN-1 container with the full library API. */
export declare class VsnStore {
    private data;
    private parsed;
    private closed;
    private modeValue;
    private fileIds;
    private revisions;
    private objects;
    private contentCache;
    private nextObjectSerial;
    private nextRevisionId;
    private generationValue;
    constructor(data?: Buffer, mode?: number);
    static create(mode?: number): VsnStore;
    static createWithPolicy(policy: number): VsnStore;
    private buildState;
    private applyRevisionRecord;
    private checkOpen;
    get mode(): number;
    get generation(): number;
    get isClosed(): boolean;
    close(): void;
    reopen(data?: Buffer): void;
    inspect(): ContainerInfo;
    /** Create a file and its first Revision; returns the FileId. */
    createFile(path: string, content?: Buffer): Buffer;
    static open(data: Buffer): VsnStore;
    readFile(fileId: Buffer): Buffer;
    writeFile(fileId: Buffer, content: Buffer): void;
    deleteFile(fileId: Buffer): void;
    renameFile(fileId: Buffer, newPath: string): void;
    listFiles(): FileInfo[];
    fileExists(fileId: Buffer): boolean;
    getFileId(path: string): Buffer | null;
    getFileMetadata(fileId: Buffer): FileInfo;
    listRevisions(fileId?: Buffer): number[];
    getRevision(revisionId: number): RevisionInfo;
    getCurrentRevision(fileId: Buffer): number | null;
    /** Compare two revisions of a file; returns whether content differs. */
    compareRevisions(fileId: Buffer, revA: number, revB: number): boolean;
    /** Revision metadata including the owning FileId and presence. */
    revisionMetadata(revisionId: number): RevisionInfo;
    checkoutRevision(fileId: Buffer, revisionId: number): Buffer;
    restoreRevision(fileId: Buffer, revisionId: number): void;
    /**
     * LimitCleanUp: retain only the newest `limit` revisions of a file.
     *
     * LIBRARY capability, not a VSN-1 protocol rule. Scope is a single file's
     * history, matching the VSN revision model in which every Revision names one
     * FileId and each file has its own head.
     *
     * `limit` is the maximum number of revisions retained and MUST be >= 1;
     * limit 0 is rejected (0x000C) so a slipped argument cannot silently destroy
     * an entire history. If the file already has <= limit revisions, nothing is
     * removed.
     *
     * Retained revisions are never rewritten: their RevisionId, contents and
     * ObjectSerial are untouched, so the next commit() re-emits them identically.
     * The head revision is the newest, so it is always retained and the FileHead
     * record can never be left dangling.
     *
     * Objects are deliberately NOT removed: the object section is a shared content
     * store that a retained revision elsewhere, or an EXTENTS-1 COPY operand, may
     * still reference. Reclaiming objects is a separate operation.
     *
     * @returns the removed RevisionIds in ascending order. Idempotent: a repeated
     * call removes nothing. The change is applied atomically to in-memory state;
     * persist it with the normal commit().
     */
    limitCleanup(fileId: Buffer, limit: number): number[];
    addObject(content: Buffer): number;
    /** Register an explicit object descriptor (used for EXTENTS-1/COPY vectors). */
    addObjectDescriptor(descriptor: Buffer, serial?: number): number;
    listObjects(): number[];
    getObjectInfo(serial: number): ObjectInfo;
    getObjectMetadata(serial: number): ObjectInfo;
    getObjectSerial(fileId: Buffer, revisionId?: number): number | null;
    materialize(serial: number, visited?: Set<number>): Buffer;
    /** Produce canonical VSN-1 bytes from current state (SR-* closure). */
    toBytes(): Buffer;
    /** Commit current state; CommitMarker is the sole acceptance authority. */
    commit(): Buffer;
    /** Validate this store's canonical state at a requested level. */
    validate(level?: "Structural" | "Semantic" | "Recovery" | "Content" | "Full"): void;
    /** Internal accessors used by StorageManager (derived data only). */
    get canonicalData(): Buffer;
    get parsedContainer(): ParsedContainer | null;
    /** Stream an object's logical content in chunks (no full copy required). */
    materializeStream(serial: number, chunkSize?: number, visited?: Set<number>): Generator<Buffer>;
    /** Stream a file's accepted content in chunks (SR-38 recovery path). */
    readFileStream(fileId: Buffer, chunkSize?: number): Generator<Buffer>;
}
