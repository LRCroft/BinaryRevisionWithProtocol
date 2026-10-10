import { VsnError } from "./errors.js";
import type { ValidationLevel } from "./validate.js";
/** Diagnostic severity (library vocabulary, not a protocol identifier). */
export declare const Severity: {
    readonly ERROR: "error";
    readonly WARNING: "warning";
    readonly INFO: "info";
};
export type Severity = (typeof Severity)[keyof typeof Severity];
/** Diagnostic category: frozen protocol error vs library-only vs derived data. */
export declare const Category: {
    readonly PROTOCOL: "protocol";
    readonly LIBRARY: "library";
    readonly DERIVED: "derived";
};
export type Category = (typeof Category)[keyof typeof Category];
/** Structured diagnostic carrying full context. */
export interface Diagnostic {
    code: number;
    name: string;
    severity: Severity;
    category: Category;
    message: string;
    byteOffset?: number;
    recordType?: number;
    fieldId?: number;
    objectSerial?: bigint;
    fileId?: Buffer;
    revisionId?: bigint;
    repIdentity?: number;
    repVersion?: number;
    operation?: string;
    cause?: unknown;
}
/** Build a PROTOCOL-category diagnostic from a frozen VSN error. */
export declare function fromVsnError(e: VsnError, operation?: string): Diagnostic;
/** Validation levels implied by a requested level, matching Python. */
export declare function validationLevels(level: ValidationLevel): ValidationLevel[];
/** Run validation and return diagnostics instead of throwing. */
export declare function validateWithDiagnostics(data: Buffer, level?: ValidationLevel): Diagnostic[];
