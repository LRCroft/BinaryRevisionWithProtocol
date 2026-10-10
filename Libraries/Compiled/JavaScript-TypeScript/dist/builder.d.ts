import type { EncodedRecord, EncodedObject } from "./writer.js";
/** Build a VSN container incrementally with explicit, deterministic identities. */
export declare class ContainerBuilder {
    mode: number;
    readonly records: EncodedRecord[];
    readonly objects: EncodedObject[];
    private fileIds;
    private revisionIds;
    private objectSerials;
    private nextObjectSerial;
    constructor(mode?: number);
    /** Add a FileIdentity record (FileId is 16 bytes, FieldId 0x0101). */
    addFile(fileId: Buffer): this;
    /** Add a Revision record; the FileId must already be declared. */
    addRevision(fileId: Buffer, revisionId: number | bigint, objectSerial?: number | bigint | null, path?: string | null, presence?: number): this;
    /** Add a ContentObject record + DIRECT-1 object; returns the ObjectSerial. */
    addObject(content: Buffer, serial?: number): number;
    /**
     * Materialize an object descriptor to its LOGICAL content.
     * SR-29: declared size 0x0511 is the expected logical content length in
     * bytes (validation metadata over logical content, never representation bytes).
     */
    private logicalContent;
    /** Add a ContentObject record + an explicit descriptor (e.g. EXTENTS-1). */
    addObjectRaw(descriptor: Buffer, serial?: number): number;
    /** Add a FileHead record; FileId and RevisionId must already be declared. */
    setHead(fileId: Buffer, revisionId: number | bigint): this;
    /** Produce canonical bytes. ModeDeclaration is prepended, CommitMarker is
     *  appended, and the trailer canonical count excludes ModeDeclaration (GR-13). */
    build(generation?: number | bigint): Buffer;
}

