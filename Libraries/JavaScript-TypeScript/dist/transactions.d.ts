import type { VsnStore } from "./store.js";
export type StagedOperation = "create" | "update" | "delete" | "rename";
/** A single staged change within a transaction. */
export interface StagedChange {
    operation: StagedOperation;
    fileId?: Buffer;
    path?: string;
    content?: Buffer;
    newPath?: string;
}
/**
 * Transaction with staging, precondition, and commit.
 *
 * ExpectedRevisionId is a precondition ONLY and is NEVER persisted as
 * canonical state (RC-01). The CommitMarker remains the sole acceptance
 * authority: a transaction commits by producing canonical bytes.
 */
export declare class Transaction {
    expectedRevisionId: number | null;
    private staged;
    private committed;
    constructor(expectedRevisionId?: number | null);
    stageCreate(path: string, content?: Buffer): void;
    stageUpdate(fileId: Buffer, content: Buffer): void;
    stageDelete(fileId: Buffer): void;
    stageRename(fileId: Buffer, newPath: string): void;
    /** Inspect staged changes (does not touch canonical state). */
    inspect(): StagedChange[];
    get changeCount(): number;
    /** Discard all staged changes. */
    rollback(): void;
    /** Apply staged changes and commit; returns canonical bytes. */
    commit(store: VsnStore): Buffer;
}
