"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Transaction = void 0;
const errors_js_1 = require("./errors.js");
/**
 * Transaction with staging, precondition, and commit.
 *
 * ExpectedRevisionId is a precondition ONLY and is NEVER persisted as
 * canonical state (RC-01). The CommitMarker remains the sole acceptance
 * authority: a transaction commits by producing canonical bytes.
 */
class Transaction {
    expectedRevisionId;
    staged = [];
    committed = false;
    constructor(expectedRevisionId = null) {
        this.expectedRevisionId = expectedRevisionId;
    }
    stageCreate(path, content = Buffer.alloc(0)) {
        this.staged.push({ operation: "create", path, content });
    }
    stageUpdate(fileId, content) {
        this.staged.push({ operation: "update", fileId, content });
    }
    stageDelete(fileId) {
        this.staged.push({ operation: "delete", fileId });
    }
    stageRename(fileId, newPath) {
        this.staged.push({ operation: "rename", fileId, newPath });
    }
    /** Inspect staged changes (does not touch canonical state). */
    inspect() {
        return this.staged.map((c) => ({ ...c }));
    }
    get changeCount() { return this.staged.length; }
    /** Discard all staged changes. */
    rollback() { this.staged = []; }
    /** Apply staged changes and commit; returns canonical bytes. */
    commit(store) {
        if (this.committed)
            throw new errors_js_1.VsnError(0x000C, "transaction already committed");
        if (this.expectedRevisionId !== null) {
            for (const change of this.staged) {
                if (change.fileId !== undefined) {
                    const current = store.getCurrentRevision(change.fileId);
                    if (current !== this.expectedRevisionId)
                        throw new errors_js_1.VsnError(0x000D, `ExpectedRevisionId mismatch: expected ${this.expectedRevisionId}, got ${current}`);
                    break;
                }
            }
        }
        for (const change of this.staged) {
            if (change.operation === "create")
                store.createFile(change.path, change.content ?? Buffer.alloc(0));
            else if (change.operation === "update")
                store.writeFile(change.fileId, change.content);
            else if (change.operation === "delete")
                store.deleteFile(change.fileId);
            else if (change.operation === "rename")
                store.renameFile(change.fileId, change.newPath);
        }
        this.committed = true;
        return store.commit();
    }
}
exports.Transaction = Transaction;
//# sourceMappingURL=transactions.js.map