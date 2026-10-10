export declare const ERRORS: Readonly<Record<number, string>>;
/** Frozen error name for a protocol error identifier. */
export declare function errorName(code: number): string;
/** Base for all VSN library errors, carrying a frozen error identifier. */
export declare class VsnError extends Error {
    readonly code: number;
    readonly byteOffset?: number;
    constructor(code: number, message: string, byteOffset?: number);
}
/** Resource refusal is NOT a protocol error (RC-29); it is a reader decision. */
export declare class ResourceRefusal extends Error {
    constructor(message: string);
}
