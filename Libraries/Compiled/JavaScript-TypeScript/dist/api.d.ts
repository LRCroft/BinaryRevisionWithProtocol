import { ObjectEntry } from "./container.js";
export declare class VsnContainer {
    private parsed;
    private objectIndex;
    private contentCache;
    constructor(data: Buffer);
    get mode(): number | null;
    get records(): import("./container.js").Record[];
    get objects(): ObjectEntry[];
    materialize(serial: bigint, visited?: Set<bigint>): Buffer;
    files(): Array<{
        fileId: Buffer;
        revisionId: bigint;
    }>;
    /** Stream an object's logical content in chunks. */
    materializeStream(serial: bigint, chunkSize?: number, visited?: Set<bigint>): Generator<Buffer>;
}
export declare function open(data: Buffer): VsnContainer;
