export * from "./constants.js";
export * from "./errors.js";
export * from "./primitives.js";
export * from "./container.js";
export * from "./representations.js";
export * from "./api.js";
export * from "./writer.js";
export * from "./builder.js";
export * from "./recovery.js";
export * from "./validate.js";
export * from "./diagnostics.js";
export * from "./transactions.js";
export * from "./store.js";
export * from "./io_ops.js";
export * from "./diff.js";
export * from "./merge.js";
export * from "./storage.js";
export * from "./integrity.js";
export * as diff from "./diff.js";
export * as merge from "./merge.js";
export * as io_ops from "./io_ops.js";
export * as storage from "./storage.js";
export * as container from "./container.js";
export * as representations from "./representations.js";
export * as validate_module from "./validate.js";
export * as recovery from "./recovery.js";
export * as diagnostics from "./diagnostics.js";
import { VsnStore } from "./store.js";
import type { Diagnostic } from "./diagnostics.js";
import type { ValidationLevel } from "./validate.js";
import type { RecoveryResult } from "./recovery.js";
import { Transaction } from "./transactions.js";
/** Create a new VSN container store. */
export declare function create(mode?: number): VsnStore;
/** Validate a container, returning diagnostics rather than throwing. */
export declare function validateContainer(data: Buffer, level?: ValidationLevel): Diagnostic[];
/** Recover a container from potentially corrupted data. */
export declare function recoverContainer(data: Buffer): RecoveryResult;
/** Import a file into a store; returns the FileId. */
export declare function importFile(store: VsnStore, path: string, content: Buffer): Buffer;
/** Export a file from a store; returns content bytes. */
export declare function exportFile(store: VsnStore, fileId: Buffer): Buffer;
/** Create a new transaction. */
export declare function transaction(expectedRevisionId?: number | null): Transaction;
/** Inspect a store and return container metadata. */
export declare function inspectContainer(store: VsnStore): {
    mode: number;
    generation: number;
    fileCount: number;
    objectCount: number;
    revisionCount: number;
};
export { StoragePolicy, MODE_MODERN, MODE_ENTERPRISE } from "./constants.js";
