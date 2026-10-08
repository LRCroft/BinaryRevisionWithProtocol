export declare function parseObjectHeader(descriptor: Buffer): {
    identity: number;
    version: number;
    remainder: Buffer;
};
export declare function materializeDirect(remainder: Buffer): Buffer;
export declare function materializeExtents(remainder: Buffer, resolve: (serial: bigint) => Buffer): Buffer;
/** Yield DIRECT-1 content in chunks without copying the whole object. */
export declare function materializeDirectStream(remainder: Buffer, chunkSize?: number): Generator<Buffer>;
/**
 * Yield EXTENTS-1 content in chunks. LITERAL and COPY operations are emitted
 * as chunked views; a COPY source is resolved because it needs random access.
 */
export declare function materializeExtentsStream(remainder: Buffer, resolve: (serial: bigint) => Buffer, chunkSize?: number): Generator<Buffer>;
