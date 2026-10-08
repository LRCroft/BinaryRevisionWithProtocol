import { VsnError } from "./errors.js";
export { VsnError };
export declare function readUvarint(buf: Buffer, offset: {
    value: number;
}): bigint;
export declare function readU16(buf: Buffer, offset: {
    value: number;
}): number;
export declare function putUvarint(value: bigint | number): Buffer;
export declare function putU16(value: number): Buffer;
