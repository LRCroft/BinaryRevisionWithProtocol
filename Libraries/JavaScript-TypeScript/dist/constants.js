"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FID_REP_VERSION = exports.FID_REP_IDENTITY = exports.FID_COMMIT_HASH = exports.FID_OBJECT_HASH = exports.FID_HEAD_GENERATION = exports.FID_RSET_DIGEST = exports.FID_RSET_STATE = exports.FID_RSET_MEMBERS = exports.FID_RSET_ID = exports.MAGIC = exports.OP_NESTED = exports.OP_NUMERIC = exports.OP_OBJECT_SOURCE = exports.OP_LITERAL_BYTES = exports.DIRECTORY = exports.DELETED = exports.PRESENT = exports.REP_VERSION_1 = exports.REP_EXTENTS_1 = exports.REP_DIRECT_1 = exports.STORAGE_HIGHLY_HORIZONTAL = exports.STORAGE_HORIZONTAL = exports.STORAGE_VERTICAL = exports.STORAGE_HIGHLY_VERTICAL = exports.MODE_ENTERPRISE = exports.MODE_MODERN = exports.FID_STORAGE_POLICY = exports.FID_MODE = exports.FID_COMMIT_GENERATION = exports.FID_OBJECT_SIZE = exports.FID_OBJECT_SERIAL = exports.FID_HEAD_REV_ID = exports.FID_HEAD_FILE_ID = exports.FID_REV_PRESENCE = exports.FID_REV_PATH = exports.FID_REV_OBJECT_SERIAL = exports.FID_REV_FILE_ID = exports.FID_REV_ID = exports.FID_FILE_ID = exports.FID_RECORDS_END = exports.REC_REPRESENTATION_DESCRIPTOR = exports.REC_STORAGE_POLICY = exports.REC_MODE_DECLARATION = exports.REC_COMMIT_MARKER = exports.REC_CONTENT_OBJECT = exports.REC_FILE_HEAD = exports.REC_REVISION_SET = exports.REC_REVISION = exports.REC_FILE_IDENTITY = exports.REC_END_OF_RECORDS = void 0;
exports.StoragePolicy = exports.HASH_BLAKE3 = exports.HASH_SHA256 = exports.HASH_NONE = exports.REC_RESERVED = exports.REC_EXTENSION_MAX = exports.REC_EXTENSION_MIN = exports.FID_REP_METADATA = void 0;
// VSN-1 frozen constants (GR-28, GR-17, VR-*)
exports.REC_END_OF_RECORDS = 0x0000;
exports.REC_FILE_IDENTITY = 0x0001;
exports.REC_REVISION = 0x0002;
exports.REC_REVISION_SET = 0x0003;
exports.REC_FILE_HEAD = 0x0004;
exports.REC_CONTENT_OBJECT = 0x0005;
exports.REC_COMMIT_MARKER = 0x0006;
exports.REC_MODE_DECLARATION = 0x0007; // OBSOLETE: deprecated, kept for reader compatibility  // OBSOLETE: kept for reader compatibility only
exports.REC_STORAGE_POLICY = 0x0009; // New: authoritative storage classification
exports.REC_REPRESENTATION_DESCRIPTOR = 0x0008;
exports.FID_RECORDS_END = 0x0000;
exports.FID_FILE_ID = 0x0101;
exports.FID_REV_ID = 0x0201;
exports.FID_REV_FILE_ID = 0x0202;
exports.FID_REV_OBJECT_SERIAL = 0x0203;
exports.FID_REV_PATH = 0x0210;
exports.FID_REV_PRESENCE = 0x0211;
exports.FID_HEAD_FILE_ID = 0x0401;
exports.FID_HEAD_REV_ID = 0x0402;
exports.FID_OBJECT_SERIAL = 0x0501;
exports.FID_OBJECT_SIZE = 0x0511;
exports.FID_COMMIT_GENERATION = 0x0601;
exports.FID_MODE = 0x0701; // OBSOLETE: ModeDeclaration field (deprecated)
exports.FID_STORAGE_POLICY = 0x0901; // StoragePolicy.field_id (new)
// Modes -- OBSOLETE: deprecated, kept for reader compatibility only
exports.MODE_MODERN = 0x01; // OBSOLETE: was MODERN wire mode
exports.MODE_ENTERPRISE = 0x02; // OBSOLETE: was ENTERPRISE wire mode
// Storage Policy values -- authoritative classification (directly on wire)
exports.STORAGE_HIGHLY_VERTICAL = 1; // maximum optimization effort
exports.STORAGE_VERTICAL = 2; // bounded optimization effort
exports.STORAGE_HORIZONTAL = 3; // low optimization effort
exports.STORAGE_HIGHLY_HORIZONTAL = 4; // minimal optimization effort
exports.REP_DIRECT_1 = 0x0001;
exports.REP_EXTENTS_1 = 0x0002;
exports.REP_VERSION_1 = 1;
exports.PRESENT = 1;
exports.DELETED = 2;
exports.DIRECTORY = 3;
exports.OP_LITERAL_BYTES = 0;
exports.OP_OBJECT_SOURCE = 1;
exports.OP_NUMERIC = 2;
exports.OP_NESTED = 3;
exports.MAGIC = Buffer.from("VSN-", "ascii");
// Remaining frozen field IDs (GR-17)
exports.FID_RSET_ID = 0x0301;
exports.FID_RSET_MEMBERS = 0x0302;
exports.FID_RSET_STATE = 0x0303;
exports.FID_RSET_DIGEST = 0x0310;
exports.FID_HEAD_GENERATION = 0x0410;
exports.FID_OBJECT_HASH = 0x0510;
exports.FID_COMMIT_HASH = 0x0610;
exports.FID_REP_IDENTITY = 0x0801;
exports.FID_REP_VERSION = 0x0802;
exports.FID_REP_METADATA = 0x0810;
// Record type registry bounds (GR-28)
exports.REC_EXTENSION_MIN = 0x8000;
exports.REC_EXTENSION_MAX = 0xfffe;
exports.REC_RESERVED = 0xffff;
// Hash algorithm identifiers (VR-17) - verification only, never identity
exports.HASH_NONE = 0x00;
exports.HASH_SHA256 = 0x01;
exports.HASH_BLAKE3 = 0x02;
// ---- Writer Storage Policy (informative, NOT on wire) ----
var StoragePolicy;
(function (StoragePolicy) {
    StoragePolicy[StoragePolicy["HIGHLY_VERTICAL"] = 1] = "HIGHLY_VERTICAL";
    StoragePolicy[StoragePolicy["VERTICAL"] = 2] = "VERTICAL";
    StoragePolicy[StoragePolicy["HORIZONTAL"] = 3] = "HORIZONTAL";
    StoragePolicy[StoragePolicy["HIGHLY_HORIZONTAL"] = 4] = "HIGHLY_HORIZONTAL";
})(StoragePolicy || (exports.StoragePolicy = StoragePolicy = {}));
//# sourceMappingURL=constants.js.map