"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.VsnContainer = void 0;
exports.open = open;
const container_js_1 = require("./container.js");
const representations_js_1 = require("./representations.js");
const constants_js_1 = require("./constants.js");
const primitives_js_1 = require("./primitives.js");
class VsnContainer {
    parsed;
    objectIndex;
    contentCache = new Map();
    constructor(data) {
        this.parsed = (0, container_js_1.parse)(data);
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
            throw new primitives_js_1.VsnError(0x000C, `cycle at ${serial}`);
        const cached = this.contentCache.get(key);
        if (cached)
            return cached;
        const entry = this.objectIndex.get(key);
        if (!entry)
            throw new primitives_js_1.VsnError(0x0008, `missing object ${serial}`);
        const { identity, version, remainder } = (0, representations_js_1.parseObjectHeader)(entry.descriptor);
        let result;
        if (identity === constants_js_1.REP_DIRECT_1 && version === constants_js_1.REP_VERSION_1) {
            result = (0, representations_js_1.materializeDirect)(remainder);
        }
        else if (identity === constants_js_1.REP_EXTENTS_1 && version === constants_js_1.REP_VERSION_1) {
            result = (0, representations_js_1.materializeExtents)(remainder, (s) => this.materialize(s, new Set([...visited, serial])));
        }
        else {
            throw new primitives_js_1.VsnError(0x0006, `unsupported rep 0x${identity.toString(16)} v${version}`);
        }
        this.contentCache.set(key, result);
        return result;
    }
    files() {
        const heads = [];
        for (const rec of this.parsed.records) {
            if (rec.rtype === constants_js_1.REC_FILE_HEAD) {
                const f = rec.getField(constants_js_1.FID_HEAD_FILE_ID);
                const r = rec.getField(constants_js_1.FID_HEAD_REV_ID);
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
            throw new primitives_js_1.VsnError(0x000C, `cycle at ${serial}`);
        const entry = this.objectIndex.get(serial.toString());
        if (!entry)
            throw new primitives_js_1.VsnError(0x0008, `missing object ${serial}`);
        const { identity, version, remainder } = (0, representations_js_1.parseObjectHeader)(entry.descriptor);
        if (identity === constants_js_1.REP_DIRECT_1 && version === constants_js_1.REP_VERSION_1) {
            yield* (0, representations_js_1.materializeDirectStream)(remainder, chunkSize);
            return;
        }
        if (identity === constants_js_1.REP_EXTENTS_1 && version === constants_js_1.REP_VERSION_1) {
            const next = new Set([...visited, serial]);
            yield* (0, representations_js_1.materializeExtentsStream)(remainder, (s) => this.materialize(s, new Set(next)), chunkSize);
            return;
        }
        throw new primitives_js_1.VsnError(0x0006, `unsupported rep 0x${identity.toString(16)} v${version}`);
    }
}
exports.VsnContainer = VsnContainer;
function open(data) {
    return new VsnContainer(data);
}
//# sourceMappingURL=api.js.map