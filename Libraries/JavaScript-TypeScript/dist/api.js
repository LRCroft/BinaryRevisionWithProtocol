import { parse } from "./container.js";
import { parseObjectHeader, materializeDirect, materializeExtents, materializeDirectStream, materializeExtentsStream, } from "./representations.js";
import { REP_DIRECT_1, REP_EXTENTS_1, REP_VERSION_1, REC_FILE_HEAD, FID_HEAD_FILE_ID, FID_HEAD_REV_ID } from "./constants.js";
import { VsnError } from "./primitives.js";
export class VsnContainer {
    parsed;
    objectIndex;
    contentCache = new Map();
    constructor(data) {
        this.parsed = parse(data);
        this.objectIndex = new Map();
        for (const obj of this.parsed.objects) {
            this.objectIndex.set(obj.serial.toString(), obj);
        }
    }
    get mode() { return this.parsed.mode; }
    get records() { return this.parsed.records; }
    get objects() { return this.parsed.objects; }
    materialize(serial, visited) {
        if (!visited)
            visited = new Set();
        const key = serial.toString();
        if (visited.has(serial))
            throw new VsnError(0x000C, `cycle at ${serial}`);
        const cached = this.contentCache.get(key);
        if (cached)
            return cached;
        const entry = this.objectIndex.get(key);
        if (!entry)
            throw new VsnError(0x0008, `missing object ${serial}`);
        const { identity, version, remainder } = parseObjectHeader(entry.descriptor);
        let result;
        if (identity === REP_DIRECT_1 && version === REP_VERSION_1) {
            result = materializeDirect(remainder);
        }
        else if (identity === REP_EXTENTS_1 && version === REP_VERSION_1) {
            result = materializeExtents(remainder, (s) => this.materialize(s, new Set([...visited, serial])));
        }
        else {
            throw new VsnError(0x0006, `unsupported rep 0x${identity.toString(16)} v${version}`);
        }
        this.contentCache.set(key, result);
        return result;
    }
    files() {
        const heads = [];
        for (const rec of this.parsed.records) {
            if (rec.rtype === REC_FILE_HEAD) {
                const f = rec.getField(FID_HEAD_FILE_ID);
                const r = rec.getField(FID_HEAD_REV_ID);
                if (f && r)
                    heads.push({ fileId: f.value, revisionId: r.asUvarint() });
            }
        }
        return heads;
    }
    /** Stream an object's logical content in chunks. */
    *materializeStream(serial, chunkSize = 65536, visited) {
        visited ??= new Set();
        if (visited.has(serial))
            throw new VsnError(0x000C, `cycle at ${serial}`);
        const entry = this.objectIndex.get(serial.toString());
        if (!entry)
            throw new VsnError(0x0008, `missing object ${serial}`);
        const { identity, version, remainder } = parseObjectHeader(entry.descriptor);
        if (identity === REP_DIRECT_1 && version === REP_VERSION_1) {
            yield* materializeDirectStream(remainder, chunkSize);
            return;
        }
        if (identity === REP_EXTENTS_1 && version === REP_VERSION_1) {
            const next = new Set([...visited, serial]);
            yield* materializeExtentsStream(remainder, (s) => this.materialize(s, new Set(next)), chunkSize);
            return;
        }
        throw new VsnError(0x0006, `unsupported rep 0x${identity.toString(16)} v${version}`);
    }
}
export function open(data) {
    return new VsnContainer(data);
}
//# sourceMappingURL=api.js.map