export interface EncodedField {
    fid: number;
    value: Buffer;
}
export interface EncodedRecord {
    rtype: number;
    fields: EncodedField[];
}
export interface EncodedObject {
    serial: bigint;
    descriptor: Buffer;
}
/**
 * Encode a canonical VSN-1 container.
 * GR-13: the trailer canonical record count excludes ModeDeclaration.
 * Identity is never derived from a hash or an offset.
 */
export declare function encode(_mode: number, records: EncodedRecord[], objects: EncodedObject[], generation: bigint | number): Buffer;
/** DR-0 descriptor: DIRECT-1 v1 header + raw logical content. */
export declare function direct1Descriptor(content: Buffer): Buffer;
/** LITERAL operation: NESTED[ LITERAL_BYTES(bytes), NUMERIC(0) ]. */
export declare function literalOperation(bytes: Buffer): Buffer;
/** COPY operation: NESTED[ OBJECT_SOURCE(serial), NUMERIC(offset), NUMERIC(length) ]. */
export declare function copyOperation(serial: bigint | number, offset: bigint | number, length: bigint | number): Buffer;
/** DR-0 descriptor: EXTENTS-1 v1 header + operation collection. */
export declare function extents1Descriptor(operations: Buffer[]): Buffer;
