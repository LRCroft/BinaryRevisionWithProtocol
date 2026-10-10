"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parse = parse;
const constants_js_1 = require("./constants.js");
const primitives_js_1 = require("./primitives.js");
/** Bounds-checked slice: physical end mid-unit is truncation (GR-47). */
function sliceChecked(data, off, len, what) {
    if (len < 0 || off.value + len > data.length) {
        throw new primitives_js_1.VsnError(0x0002, `truncated ${what}`, off.value);
    }
    const out = data.subarray(off.value, off.value + len);
    off.value += len;
    return out;
}
function makeField(fid, value) {
    return {
        fid,
        value,
        asUvarint() {
            const off = { value: 0 };
            return (0, primitives_js_1.readUvarint)(this.value, off);
        },
    };
}
function makeRecord(rtype, payload, byteOffset) {
    return {
        rtype,
        payload,
        fields: [],
        byteOffset,
        getField(fid) {
            return this.fields.find((f) => f.fid === fid);
        },
    };
}
function parseFields(payload, rec) {
    const off = { value: 0 };
    let last = -1;
    while (off.value < payload.length) {
        const start = off.value;
        const fid = (0, primitives_js_1.readU16)(payload, off);
        if (last >= 0 && fid <= last)
            throw new primitives_js_1.VsnError(0x0011, `FieldId ${fid} not ascending`, start);
        last = fid;
        const ln = (0, primitives_js_1.readUvarint)(payload, off);
        const val = sliceChecked(payload, off, Number(ln), "field value");
        rec.fields.push(makeField(fid, val));
    }
}
function parse(data) {
    const off = { value: 0 };
    if (data.length < 4 || !data.subarray(0, 4).equals(constants_js_1.MAGIC))
        throw new primitives_js_1.VsnError(0x0001, "bad magic", 0);
    off.value = 4;
    const cfv = (0, primitives_js_1.readU16)(data, off);
    if (cfv !== 1)
        throw new primitives_js_1.VsnError(0x0003, `unsupported CFV ${cfv}`);
    const ev = (0, primitives_js_1.readU16)(data, off);
    if (ev !== 1)
        throw new primitives_js_1.VsnError(0x0004, `unsupported EV ${ev}`);
    // Header fields
    while (true) {
        const fid = (0, primitives_js_1.readU16)(data, off);
        const ln = (0, primitives_js_1.readUvarint)(data, off);
        if (fid === constants_js_1.FID_RECORDS_END) {
            if (ln !== BigInt(0))
                throw new primitives_js_1.VsnError(0x0001, "RecordsEnd length != 0");
            break;
        }
        sliceChecked(data, off, Number(ln), "header field");
    }
    const records = [];
    while (true) {
        const start = off.value;
        const rt = (0, primitives_js_1.readU16)(data, off);
        if (rt === constants_js_1.REC_END_OF_RECORDS)
            break;
        const rl = (0, primitives_js_1.readUvarint)(data, off);
        const payload = sliceChecked(data, off, Number(rl), "record payload");
        const rec = makeRecord(rt, payload, start);
        // REC_STORAGE_POLICY (0x0009) is a canonical field-bearing record; it MUST be
        // included in field parsing or the writer's storage policy is lost on read-back.
        if (rt <= constants_js_1.REC_STORAGE_POLICY)
            parseFields(payload, rec);
        records.push(rec);
    }
    const objects = [];
    while (true) {
        const start = off.value;
        const serial = (0, primitives_js_1.readUvarint)(data, off);
        if (serial === BigInt(0))
            break;
        const ol = (0, primitives_js_1.readUvarint)(data, off);
        const desc = sliceChecked(data, off, Number(ol), "object descriptor");
        objects.push({ serial, length: Number(ol), descriptor: desc, byteOffset: start });
    }
    const rc = (0, primitives_js_1.readUvarint)(data, off);
    const gen = (0, primitives_js_1.readUvarint)(data, off);
    let mode = null;
    let storagePolicy = null;
    for (const rec of records) {
        if (rec.rtype === constants_js_1.REC_MODE_DECLARATION) {
            const m = rec.getField(constants_js_1.FID_MODE);
            if (m && m.value.length > 0)
                mode = m.value[0];
        }
        if (rec.rtype === constants_js_1.REC_STORAGE_POLICY) {
            const sp = rec.getField(constants_js_1.FID_STORAGE_POLICY);
            if (sp && sp.value.length > 0)
                storagePolicy = sp.value[0];
        }
    }
    return {
        containerFormatVersion: cfv,
        encodingVersion: ev,
        records,
        objects,
        trailerRecordCount: rc,
        trailerGeneration: gen,
        mode,
        storagePolicy,
        byteLength: data.length,
    };
}
//# sourceMappingURL=container.js.map