"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.validateStructural = validateStructural;
exports.validateSemantic = validateSemantic;
exports.validateContent = validateContent;
exports.validate = validate;
const container_js_1 = require("./container.js");
const representations_js_1 = require("./representations.js");
const recovery_js_1 = require("./recovery.js");
const api_js_1 = require("./api.js");
const errors_js_1 = require("./errors.js");
const constants_js_1 = require("./constants.js");
/** Structural: magic, versions, framing, lengths, ordering. */
function validateStructural(data) {
    (0, container_js_1.parse)(data);
}
function checkMode(parsed) {
    const modes = parsed.records.filter((r) => r.rtype === constants_js_1.REC_MODE_DECLARATION);
    if (modes.length !== 1)
        throw new errors_js_1.VsnError(0x000C, `expected exactly one ModeDeclaration, got ${modes.length}`);
    const m = modes[0].getField(constants_js_1.FID_MODE);
    if (!m || m.value.length !== 1)
        throw new errors_js_1.VsnError(0x000C, "ModeDeclaration missing mode value");
    const mode = m.value[0];
    if (mode !== constants_js_1.MODE_MODERN && mode !== constants_js_1.MODE_ENTERPRISE)
        throw new errors_js_1.VsnError(0x0001, `reserved mode value 0x${mode.toString(16).padStart(2, "0")}`);
    // GR-43: ENTERPRISE must not use EXTENTS-1 reconstruction semantics.
    if (mode === constants_js_1.MODE_ENTERPRISE) {
        for (const obj of parsed.objects) {
            const { identity } = (0, representations_js_1.parseObjectHeader)(obj.descriptor);
            if (identity === constants_js_1.REP_EXTENTS_1)
                throw new errors_js_1.VsnError(0x000C, "ENTERPRISE mode forbids EXTENTS-1 (GR-43)");
        }
    }
}
function checkIdentities(parsed) {
    const seenFile = new Set();
    const seenRev = new Set();
    const seenObj = new Set();
    for (const rec of parsed.records) {
        if (rec.rtype === constants_js_1.REC_FILE_IDENTITY) {
            const f = rec.getField(constants_js_1.FID_FILE_ID);
            const key = f ? f.value.toString("hex") : "null";
            if (seenFile.has(key))
                throw new errors_js_1.VsnError(0x000A, "duplicate FileIdentity");
            seenFile.add(key);
        }
        else if (rec.rtype === constants_js_1.REC_REVISION) {
            const r = rec.getField(constants_js_1.FID_REV_ID);
            if (r) {
                const rid = r.asUvarint();
                if (seenRev.has(rid))
                    throw new errors_js_1.VsnError(0x000A, `duplicate RevisionId ${rid}`);
                seenRev.add(rid);
            }
        }
        else if (rec.rtype === constants_js_1.REC_CONTENT_OBJECT) {
            const s = rec.getField(constants_js_1.FID_OBJECT_SERIAL);
            if (s) {
                const sid = s.asUvarint();
                if (seenObj.has(sid))
                    throw new errors_js_1.VsnError(0x000A, `duplicate ObjectSerial ${sid}`);
                seenObj.add(sid);
            }
        }
    }
}
/** Dependency validation: every canonical reference must resolve (RX-*). */
function checkReferences(parsed) {
    const fileIds = new Set();
    for (const r of parsed.records) {
        if (r.rtype === constants_js_1.REC_FILE_IDENTITY) {
            const f = r.getField(constants_js_1.FID_FILE_ID);
            if (f)
                fileIds.add(f.value.toString("hex"));
        }
    }
    const objIds = new Set();
    for (const o of parsed.objects)
        objIds.add(o.serial.toString());
    const revIds = new Set();
    for (const r of parsed.records) {
        if (r.rtype === constants_js_1.REC_REVISION) {
            const r2 = r.getField(constants_js_1.FID_REV_ID);
            if (r2)
                revIds.add(r2.asUvarint().toString());
        }
    }
    for (const rec of parsed.records) {
        if (rec.rtype === constants_js_1.REC_REVISION) {
            const f = rec.getField(constants_js_1.FID_REV_FILE_ID);
            if (!f || !fileIds.has(f.value.toString("hex")))
                throw new errors_js_1.VsnError(0x0009, "Revision references missing FileId");
            const obj = rec.getField(constants_js_1.FID_REV_OBJECT_SERIAL);
            if (obj && !objIds.has(obj.asUvarint().toString()))
                throw new errors_js_1.VsnError(0x0008, "Revision references missing ObjectSerial");
        }
        else if (rec.rtype === constants_js_1.REC_FILE_HEAD) {
            const f = rec.getField(constants_js_1.FID_HEAD_FILE_ID);
            if (!f || !fileIds.has(f.value.toString("hex")))
                throw new errors_js_1.VsnError(0x0009, "FileHead references missing FileId");
            const r = rec.getField(constants_js_1.FID_HEAD_REV_ID);
            if (!r || !revIds.has(r.asUvarint().toString()))
                throw new errors_js_1.VsnError(0x0009, "FileHead references missing RevisionId");
        }
    }
}
/** Semantic: identity uniqueness, reference resolution, mode constraints. */
function validateSemantic(data) {
    const parsed = (0, container_js_1.parse)(data);
    checkMode(parsed);
    checkIdentities(parsed);
    checkReferences(parsed);
}
/**
 * Content: dependency validation plus dependency cycle detection.
 * Every object must materialize; a cycle is an invalid canonical state.
 *
 * DR-6 additionally requires that when 0x0511 is PRESENT, the materialized
 * output length MUST equal it; a mismatch is invalid canonical state (0x000C,
 * matching frozen vector EXT-12). Absence of 0x0511 stays fully valid (SR-27).
 * Reuses the existing INVALID_CANONICAL_STATE identifier; no new identifier is
 * introduced, and no derived storage is consulted.
 */
function validateContent(data) {
    const parsed = (0, container_js_1.parse)(data);
    const declared = new Map();
    for (const rec of parsed.records) {
        if (rec.rtype !== constants_js_1.REC_CONTENT_OBJECT)
            continue;
        const s = rec.getField(constants_js_1.FID_OBJECT_SERIAL);
        const z = rec.getField(constants_js_1.FID_OBJECT_SIZE);
        if (s && z)
            declared.set(Number(s.asUvarint()), z.asUvarint());
    }
    const c = new api_js_1.VsnContainer(data);
    for (const obj of c.objects) {
        const content = c.materialize(obj.serial);
        const want = declared.get(Number(obj.serial));
        if (want !== undefined && want !== BigInt(content.length))
            throw new errors_js_1.VsnError(0x000C, `declared size ${want} does not match materialized length ` +
                `${content.length} for ObjectSerial ${obj.serial} (DR-6)`);
    }
}
/** Run validation at a requested depth. */
function validate(data, level = "Full") {
    const levels = ["Structural", "Semantic", "Recovery", "Content", "Full"];
    if (!levels.includes(level))
        throw new Error(`unknown validation level ${level}`);
    if (level === "Structural" || level === "Full")
        validateStructural(data);
    if (level === "Semantic" || level === "Full")
        validateSemantic(data);
    if (level === "Recovery" || level === "Full")
        (0, recovery_js_1.recover)(data);
    if (level === "Content" || level === "Full")
        validateContent(data);
}
//# sourceMappingURL=validate.js.map