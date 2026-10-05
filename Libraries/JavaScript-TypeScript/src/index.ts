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

// Namespace re-exports mirror the Python module namespaces (vsn.diff, etc.).
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
import { validateWithDiagnostics } from "./diagnostics.js";
import type { Diagnostic } from "./diagnostics.js";
import type { ValidationLevel } from "./validate.js";
import { recover } from "./recovery.js";
import type { RecoveryResult } from "./recovery.js";
import { importBytes, exportBytes } from "./io_ops.js";
import { Transaction } from "./transactions.js";

/** Create a new VSN container store. */
export function create(mode: number = 1): VsnStore { return VsnStore.create(mode); }

/** Validate a container, returning diagnostics rather than throwing. */
export function validateContainer(data: Buffer, level: ValidationLevel = "Full"): Diagnostic[] {
  return validateWithDiagnostics(data, level);
}

/** Recover a container from potentially corrupted data. */
export function recoverContainer(data: Buffer): RecoveryResult { return recover(data); }

/** Import a file into a store; returns the FileId. */
export function importFile(store: VsnStore, path: string, content: Buffer): Buffer {
  return importBytes(store, path, content);
}

/** Export a file from a store; returns content bytes. */
export function exportFile(store: VsnStore, fileId: Buffer): Buffer {
  return exportBytes(store, fileId);
}

/** Create a new transaction. */
export function transaction(expectedRevisionId: number | null = null): Transaction {
  return new Transaction(expectedRevisionId);
}

/** Inspect a store and return container metadata. */
export function inspectContainer(store: VsnStore): {
  mode: number; generation: number; fileCount: number; objectCount: number; revisionCount: number;
} {
  return store.inspect();
}

