import { Readable, Writable } from "stream";
import { VsnError } from "./errors.js";
import type { VsnStore } from "./store.js";

/** Import raw bytes as a new file; returns the FileId. */
export function importBytes(store: VsnStore, path: string, content: Buffer): Buffer {
  if (!Buffer.isBuffer(content)) throw new VsnError(0x0001, "content must be bytes");
  return store.createFile(path, content);
}

/** Export materialized file content as bytes. */
export function exportBytes(store: VsnStore, fileId: Buffer): Buffer {
  return store.readFile(fileId);
}

/** Import from a Node Readable stream, chunk by chunk (streaming). */
export async function importStream(
  store: VsnStore, path: string, stream: Readable,
): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) chunks.push(Buffer.from(chunk as Buffer));
  return store.createFile(path, Buffer.concat(chunks));
}

/** Export file content to a Node Writable stream; returns bytes written. */
export async function exportStream(
  store: VsnStore, fileId: Buffer, stream: Writable, chunkSize = 65536,
): Promise<number> {
  let total = 0;
  for (const chunk of store.readFileStream(fileId, chunkSize)) {
    if (!stream.write(chunk)) {
      await new Promise<void>((resolve) => stream.once("drain", () => resolve()));
    }
    total += chunk.length;
  }
  return total;
}

/** Import multiple files; returns a map path -> FileId. */
export function importMultiple(store: VsnStore, files: Map<string, Buffer>): Map<string, Buffer> {
  const result = new Map<string, Buffer>();
  for (const [path, content] of files) result.set(path, store.createFile(path, content));
  return result;
}

/** Export multiple files; returns a map FileId(hex) -> content. */
export function exportMultiple(store: VsnStore, fileIds: Buffer[]): Map<string, Buffer> {
  const result = new Map<string, Buffer>();
  for (const fid of fileIds) result.set(fid.toString("hex"), store.readFile(fid));
  return result;
}
