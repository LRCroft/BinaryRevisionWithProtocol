"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.importBytes = importBytes;
exports.exportBytes = exportBytes;
exports.importStream = importStream;
exports.exportStream = exportStream;
exports.importMultiple = importMultiple;
exports.exportMultiple = exportMultiple;
const errors_js_1 = require("./errors.js");
/** Import raw bytes as a new file; returns the FileId. */
function importBytes(store, path, content) {
    if (!Buffer.isBuffer(content))
        throw new errors_js_1.VsnError(0x0001, "content must be bytes");
    return store.createFile(path, content);
}
/** Export materialized file content as bytes. */
function exportBytes(store, fileId) {
    return store.readFile(fileId);
}
/** Import from a Node Readable stream, chunk by chunk (streaming). */
async function importStream(store, path, stream) {
    const chunks = [];
    for await (const chunk of stream)
        chunks.push(Buffer.from(chunk));
    return store.createFile(path, Buffer.concat(chunks));
}
/** Export file content to a Node Writable stream; returns bytes written. */
async function exportStream(store, fileId, stream, chunkSize = 65536) {
    let total = 0;
    for (const chunk of store.readFileStream(fileId, chunkSize)) {
        if (!stream.write(chunk)) {
            await new Promise((resolve) => stream.once("drain", () => resolve()));
        }
        total += chunk.length;
    }
    return total;
}
/** Import multiple files; returns a map path -> FileId. */
function importMultiple(store, files) {
    const result = new Map();
    for (const [path, content] of files)
        result.set(path, store.createFile(path, content));
    return result;
}
/** Export multiple files; returns a map FileId(hex) -> content. */
function exportMultiple(store, fileIds) {
    const result = new Map();
    for (const fid of fileIds)
        result.set(fid.toString("hex"), store.readFile(fid));
    return result;
}
//# sourceMappingURL=io_ops.js.map