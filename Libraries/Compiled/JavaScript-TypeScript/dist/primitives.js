"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.VsnError = void 0;
exports.readUvarint = readUvarint;
exports.readU16 = readU16;
exports.putUvarint = putUvarint;
exports.putU16 = putU16;
const errors_js_1 = require("./errors.js");
Object.defineProperty(exports, "VsnError", { enumerable: true, get: function () { return errors_js_1.VsnError; } });
function readUvarint(buf, offset) {
    let result = BigInt(0);
    let shift = 0;
    for (let i = 0; i < 10; i++) {
        if (offset.value >= buf.length)
            throw new errors_js_1.VsnError(0x0002, "truncated uvarint");
        const b = buf[offset.value++];
        result |= BigInt(b & 0x7f) << BigInt(shift);
        if ((b & 0x80) === 0) {
            if (i > 0 && b === 0)
                throw new errors_js_1.VsnError(0x0001, "non-minimal uvarint");
            return result;
        }
        shift += 7;
    }
    throw new errors_js_1.VsnError(0x0001, "uvarint overflow");
}
function readU16(buf, offset) {
    if (offset.value + 2 > buf.length)
        throw new errors_js_1.VsnError(0x0002, "truncated u16");
    const val = buf.readUInt16BE(offset.value);
    offset.value += 2;
    return val;
}
function putUvarint(value) {
    const bytes = [];
    let v = typeof value === "number" ? BigInt(value) : value;
    do {
        let b = Number(v & BigInt(0x7f));
        v >>= BigInt(7);
        if (v !== BigInt(0))
            b |= 0x80;
        bytes.push(b);
    } while (v !== BigInt(0));
    return Buffer.from(bytes);
}
function putU16(value) {
    const buf = Buffer.alloc(2);
    buf.writeUInt16BE(value, 0);
    return buf;
}
//# sourceMappingURL=primitives.js.map