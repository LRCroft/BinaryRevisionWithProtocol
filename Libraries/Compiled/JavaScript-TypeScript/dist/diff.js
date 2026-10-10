"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.diffObjects = diffObjects;
exports.diffFiles = diffFiles;
exports.diffRevisions = diffRevisions;
exports.contentEqual = contentEqual;
/** Diff two object-serial sets. */
function diffObjects(left, right) {
    const l = new Set(left), r = new Set(right);
    const shared = [...l].filter((s) => r.has(s)).sort((a, b) => a - b);
    const added = [...r].filter((s) => !l.has(s)).sort((a, b) => a - b);
    const removed = [...l].filter((s) => !r.has(s)).sort((a, b) => a - b);
    return { shared, added, removed };
}
/** Diff files between two stores by path and logical content. */
function diffFiles(left, right) {
    const leftFiles = new Map();
    for (const i of left.listFiles())
        if (i.path)
            leftFiles.set(i.path, i.fileId);
    const rightFiles = new Map();
    for (const i of right.listFiles())
        if (i.path)
            rightFiles.set(i.path, i.fileId);
    const result = { added: [], deleted: [], modified: [], unchanged: [], renamed: [] };
    const all = [...new Set([...leftFiles.keys(), ...rightFiles.keys()])].sort();
    for (const path of all) {
        const inLeft = leftFiles.has(path);
        const inRight = rightFiles.has(path);
        if (inLeft && !inRight)
            result.deleted.push(path);
        else if (inRight && !inLeft)
            result.added.push(path);
        else {
            const a = left.readFile(leftFiles.get(path));
            const b = right.readFile(rightFiles.get(path));
            if (a.equals(b))
                result.unchanged.push(path);
            else
                result.modified.push(path);
        }
    }
    return result;
}
/** Diff logical content between two revisions of one file. */
function diffRevisions(store, fileId, revA, revB) {
    const contentA = store.checkoutRevision(fileId, revA);
    const contentB = store.checkoutRevision(fileId, revB);
    const changed = !contentA.equals(contentB);
    return {
        revisionA: revA, revisionB: revB, contentA, contentB,
        changed, addedBytes: changed ? contentB.length - contentA.length : 0,
    };
}
function contentEqual(a, b) { return a.equals(b); }
//# sourceMappingURL=diff.js.map