import { VsnError } from "./errors.js";
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
export class Transaction {
  expectedRevisionId: number | null;
  private staged: StagedChange[] = [];
  private committed = false;

  constructor(expectedRevisionId: number | null = null) {
    this.expectedRevisionId = expectedRevisionId;
  }

  stageCreate(path: string, content: Buffer = Buffer.alloc(0)): void {
    this.staged.push({ operation: "create", path, content });
  }

  stageUpdate(fileId: Buffer, content: Buffer): void {
    this.staged.push({ operation: "update", fileId, content });
  }

  stageDelete(fileId: Buffer): void {
    this.staged.push({ operation: "delete", fileId });
  }

  stageRename(fileId: Buffer, newPath: string): void {
    this.staged.push({ operation: "rename", fileId, newPath });
  }

  /** Inspect staged changes (does not touch canonical state). */
  inspect(): StagedChange[] {
    return this.staged.map((c) => ({ ...c }));
  }

  get changeCount(): number { return this.staged.length; }

  /** Discard all staged changes. */
  rollback(): void { this.staged = []; }

  /** Apply staged changes and commit; returns canonical bytes. */
  commit(store: VsnStore): Buffer {
    if (this.committed) throw new VsnError(0x000C, "transaction already committed");
    if (this.expectedRevisionId !== null) {
      for (const change of this.staged) {
        if (change.fileId !== undefined) {
          const current = store.getCurrentRevision(change.fileId);
          if (current !== this.expectedRevisionId)
            throw new VsnError(0x000D,
              `ExpectedRevisionId mismatch: expected ${this.expectedRevisionId}, got ${current}`);
          break;
        }
      }
    }
    for (const change of this.staged) {
      if (change.operation === "create") store.createFile(change.path!, change.content ?? Buffer.alloc(0));
      else if (change.operation === "update") store.writeFile(change.fileId!, change.content!);
      else if (change.operation === "delete") store.deleteFile(change.fileId!);
      else if (change.operation === "rename") store.renameFile(change.fileId!, change.newPath!);
    }
    this.committed = true;
    return store.commit();
  }
}
