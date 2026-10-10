"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ContainerBuilder = void 0;
const constants_js_1 = require("./constants.js");
const primitives_js_1 = require("./primitives.js");
const writer_js_1 = require("./writer.js");
const representations_js_1 = require("./representations.js");
/** Build a VSN container incrementally with explicit, deterministic identities. */
class ContainerBuilder {
    mode;
    records = [];
    objects = [];
    fileIds = new Set();
    revisionIds = new Set();
    objectSerials = new Set();
    nextObjectSerial = 1;
    constructor(mode = constants_js_1.MODE_MODERN) { this.mode = mode; }
    /** Add a FileIdentity record (FileId is 16 bytes, FieldId 0x0101). */
    addFile(fileId) {
        if (fileId.length !== 16)
            throw new Error("FileId must be 16 bytes");
        const key = fileId.toString("hex");
        if (this.fileIds.has(key))
            throw new Error("duplicate FileId");
        this.fileIds.add(key);
        this.records.push({ rtype: constants_js_1.REC_FILE_IDENTITY, fields: [{ fid: constants_js_1.FID_FILE_ID, value: fileId }] });
        return this;
    }
    /** Add a Revision record; the FileId must already be declared. */
    addRevision(fileId, revisionId, objectSerial = null, path = null, presence = constants_js_1.PRESENT) {
        const key = fileId.toString("hex");
        if (!this.fileIds.has(key))
            throw new Error("FileId not declared");
        const rid = Number(revisionId);
        if (this.revisionIds.has(rid))
            throw new Error("duplicate RevisionId");
        this.revisionIds.add(rid);
        const fields = [
            { fid: constants_js_1.FID_REV_ID, value: (0, primitives_js_1.putUvarint)(rid) },
            { fid: constants_js_1.FID_REV_FILE_ID, value: fileId },
        ];
        if (objectSerial !== null)
            fields.push({ fid: constants_js_1.FID_REV_OBJECT_SERIAL, value: (0, primitives_js_1.putUvarint)(Number(objectSerial)) });
        if (path !== null)
            fields.push({ fid: constants_js_1.FID_REV_PATH, value: Buffer.from(path, "utf8") });
        fields.push({ fid: constants_js_1.FID_REV_PRESENCE, value: Buffer.from([presence]) });
        this.records.push({ rtype: constants_js_1.REC_REVISION, fields });
        return this;
    }
    /** Add a ContentObject record + DIRECT-1 object; returns the ObjectSerial. */
    addObject(content, serial) {
        const sid = serial ?? this.nextObjectSerial;
        if (serial === undefined)
            this.nextObjectSerial += 1;
        if (sid >= this.nextObjectSerial)
            this.nextObjectSerial = sid + 1;
        if (this.objectSerials.has(sid))
            throw new Error("duplicate ObjectSerial");
        this.objectSerials.add(sid);
        this.records.push({
            rtype: constants_js_1.REC_CONTENT_OBJECT,
            fields: [
                { fid: constants_js_1.FID_OBJECT_SERIAL, value: (0, primitives_js_1.putUvarint)(sid) },
                { fid: constants_js_1.FID_OBJECT_SIZE, value: (0, primitives_js_1.putUvarint)(content.length) },
            ],
        });
        this.objects.push({ serial: BigInt(sid), descriptor: (0, writer_js_1.direct1Descriptor)(content) });
        return sid;
    }
    /**
     * Materialize an object descriptor to its LOGICAL content.
     * SR-29: declared size 0x0511 is the expected logical content length in
     * bytes (validation metadata over logical content, never representation bytes).
     */
    logicalContent(descriptor, visited = new Set()) {
        const key = descriptor.toString("hex");
        if (visited.has(key))
            throw new primitives_js_1.VsnError(0x000C, "dependency cycle");
        visited.add(key);
        const { identity, version, remainder } = (0, representations_js_1.parseObjectHeader)(descriptor);
        if (identity === constants_js_1.REP_DIRECT_1 && version === constants_js_1.REP_VERSION_1)
            return (0, representations_js_1.materializeDirect)(remainder);
        if (identity === constants_js_1.REP_EXTENTS_1 && version === constants_js_1.REP_VERSION_1)
            return (0, representations_js_1.materializeExtents)(remainder, (s) => {
                const entry = this.objects.find((o) => o.serial === s);
                if (!entry)
                    throw new primitives_js_1.VsnError(0x0008, `missing object ${s}`);
                return this.logicalContent(entry.descriptor, new Set(visited));
            });
        throw new primitives_js_1.VsnError(0x0006, `unsupported representation 0x${identity.toString(16)} v${version}`);
    }
    /** Add a ContentObject record + an explicit descriptor (e.g. EXTENTS-1). */
    addObjectRaw(descriptor, serial) {
        const sid = serial ?? this.nextObjectSerial;
        if (serial === undefined)
            this.nextObjectSerial += 1;
        if (sid >= this.nextObjectSerial)
            this.nextObjectSerial = sid + 1;
        if (this.objectSerials.has(sid))
            throw new Error("duplicate ObjectSerial");
        this.objectSerials.add(sid);
        this.objects.push({ serial: BigInt(sid), descriptor });
        // 0x0511 is the LOGICAL content length (SR-29), never representation bytes.
        // It is optional (SR-27): omit it when the logical length cannot be
        // resolved yet (missing dependency, cycle, unsupported representation).
        const fields = [{ fid: constants_js_1.FID_OBJECT_SERIAL, value: (0, primitives_js_1.putUvarint)(sid) }];
        try {
            fields.push({ fid: constants_js_1.FID_OBJECT_SIZE, value: (0, primitives_js_1.putUvarint)(this.logicalContent(descriptor).length) });
        }
        catch {
            /* 0x0511 omitted: fully valid under SR-27 */
        }
        this.records.push({ rtype: constants_js_1.REC_CONTENT_OBJECT, fields });
        return sid;
    }
    /** Add a FileHead record; FileId and RevisionId must already be declared. */
    setHead(fileId, revisionId) {
        const key = fileId.toString("hex");
        if (!this.fileIds.has(key))
            throw new Error("FileId not declared");
        const rid = Number(revisionId);
        if (!this.revisionIds.has(rid))
            throw new Error("RevisionId not declared");
        this.records.push({
            rtype: constants_js_1.REC_FILE_HEAD,
            fields: [
                { fid: constants_js_1.FID_HEAD_FILE_ID, value: fileId },
                { fid: constants_js_1.FID_HEAD_REV_ID, value: (0, primitives_js_1.putUvarint)(rid) },
            ],
        });
        return this;
    }
    /** Produce canonical bytes. ModeDeclaration is prepended, CommitMarker is
     *  appended, and the trailer canonical count excludes ModeDeclaration (GR-13). */
    build(generation = 1) {
        const records = [
            { rtype: constants_js_1.REC_MODE_DECLARATION, fields: [{ fid: constants_js_1.FID_MODE, value: Buffer.from([this.mode]) }] },
            ...this.records,
            { rtype: constants_js_1.REC_COMMIT_MARKER, fields: [{ fid: constants_js_1.FID_COMMIT_GENERATION, value: (0, primitives_js_1.putUvarint)(Number(generation)) }] },
        ];
        return (0, writer_js_1.encode)(this.mode, records, this.objects, Number(generation));
    }
}
exports.ContainerBuilder = ContainerBuilder;
//# sourceMappingURL=builder.js.map
