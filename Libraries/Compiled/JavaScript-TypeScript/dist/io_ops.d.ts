import { Readable, Writable } from "stream";
import type { VsnStore } from "./store.js";
/** Import raw bytes as a new file; returns the FileId. */
export declare function importBytes(store: VsnStore, path: string, content: Buffer): Buffer;
/** Export materialized file content as bytes. */
export declare function exportBytes(store: VsnStore, fileId: Buffer): Buffer;
/** Import from a Node Readable stream, chunk by chunk (streaming). */
export declare function importStream(store: VsnStore, path: string, stream: Readable): Promise<Buffer>;
/** Export file content to a Node Writable stream; returns bytes written. */
export declare function exportStream(store: VsnStore, fileId: Buffer, stream: Writable, chunkSize?: number): Promise<number>;
/** Import multiple files; returns a map path -> FileId. */
export declare function importMultiple(store: VsnStore, files: Map<string, Buffer>): Map<string, Buffer>;
/** Export multiple files; returns a map FileId(hex) -> content. */
export declare function exportMultiple(store: VsnStore, fileIds: Buffer[]): Map<string, Buffer>;
