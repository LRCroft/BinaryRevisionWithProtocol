"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.encode = encode;
exports.direct1Descriptor = direct1Descriptor;
exports.literalOperation = literalOperation;
exports.copyOperation = copyOperation;
exports.extents1Descriptor = extents1Descriptor;
const constants_js_1 = require("./constants.js");
const primitives_js_1 = require("./primitives.js");
function field(fid, value) {
    return Buffer.concat([(0, primitives_js_1.putU16)(fid), (0, primitives_js_1.putUvarint)(value.length), value]);
}
function record(rtype, fields) {
    const payload = Buffer.concat(fields.map((f) => field(f.fid, f.value)));
    return Buffer.concat([(0, primitives_js_1.putU16)(rtype), (0, primitives_js_1.putUvarint)(payload.length), payload]);
}
/**
 * Encode a canonical VSN container.
 * GR-13: the trailer canonical record count excludes ModeDeclaration.
 * Identity is never derived from a hash or an offset.
 */
function encode(_mode, records, objects, generation) {
    const parts = [
        constants_js_1.MAGIC,
        (0, primitives_js_1.putU16)(1), (0, primitives_js_1.putU16)(1), field(constants_js_1.FID_RECORDS_END, Buffer.alloc(0)),
    ];
    for (const r of records)
        parts.push(record(r.rtype, r.fields));
    parts.push((0, primitives_js_1.putU16)(constants_js_1.REC_END_OF_RECORDS));
    for (const o of objects) {
        parts.push((0, primitives_js_1.putUvarint)(o.serial), (0, primitives_js_1.putUvarint)(o.descriptor.length), o.descriptor);
    }
    parts.push((0, primitives_js_1.putUvarint)(0));
    let canonical = 0;
    for (const r of records)
        if (r.rtype !== constants_js_1.REC_MODE_DECLARATION)
            canonical += 1;
    parts.push((0, primitives_js_1.putUvarint)(canonical), (0, primitives_js_1.putUvarint)(generation));
    return Buffer.concat(parts);
}
/** DR-0 descriptor: DIRECT-1 v1 header + raw logical content. */
function direct1Descriptor(content) {
    return Buffer.concat([(0, primitives_js_1.putU16)(constants_js_1.REP_DIRECT_1), (0, primitives_js_1.putUvarint)(constants_js_1.REP_VERSION_1), content]);
}
/** LITERAL operation: NESTED[ LITERAL_BYTES(bytes), NUMERIC(0) ]. */
function literalOperation(bytes) {
    return Buffer.concat([
        (0, primitives_js_1.putUvarint)(constants_js_1.OP_NESTED), (0, primitives_js_1.putUvarint)(2),
        (0, primitives_js_1.putUvarint)(constants_js_1.OP_LITERAL_BYTES), (0, primitives_js_1.putUvarint)(bytes.length), bytes,
        (0, primitives_js_1.putUvarint)(constants_js_1.OP_NUMERIC), (0, primitives_js_1.putUvarint)(0),
    ]);
}
/** COPY operation: NESTED[ OBJECT_SOURCE(serial), NUMERIC(offset), NUMERIC(length) ]. */
function copyOperation(serial, offset, length) {
    return Buffer.concat([
        (0, primitives_js_1.putUvarint)(constants_js_1.OP_NESTED), (0, primitives_js_1.putUvarint)(3),
        (0, primitives_js_1.putUvarint)(constants_js_1.OP_OBJECT_SOURCE), (0, primitives_js_1.putUvarint)(serial),
        (0, primitives_js_1.putUvarint)(constants_js_1.OP_NUMERIC), (0, primitives_js_1.putUvarint)(offset),
        (0, primitives_js_1.putUvarint)(constants_js_1.OP_NUMERIC), (0, primitives_js_1.putUvarint)(length),
    ]);
}
/** DR-0 descriptor: EXTENTS-1 v1 header + operation collection. */
function extents1Descriptor(operations) {
    return Buffer.concat([
        (0, primitives_js_1.putU16)(constants_js_1.REP_EXTENTS_1), (0, primitives_js_1.putUvarint)(constants_js_1.REP_VERSION_1),
        (0, primitives_js_1.putUvarint)(operations.length), ...operations,
    ]);
}
//# sourceMappingURL=writer.js.map
