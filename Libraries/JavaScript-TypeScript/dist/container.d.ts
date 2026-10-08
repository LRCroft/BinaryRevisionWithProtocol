export interface Field {
    fid: number;
    value: Buffer;
    asUvarint(): bigint;
}
export interface Record {
    rtype: number;
    payload: Buffer;
    fields: Field[];
    byteOffset: number;
    getField(fid: number): Field | undefined;
}
export interface ObjectEntry {
    serial: bigint;
    length: number;
    descriptor: Buffer;
    byteOffset: number;
}
export interface ParsedContainer {
    containerFormatVersion: number;
    encodingVersion: number;
    records: Record[];
    objects: ObjectEntry[];
    trailerRecordCount: bigint;
    trailerGeneration: bigint;
    mode: number | null;
    byteLength: number;
}
export declare function parse(data: Buffer): ParsedContainer;
