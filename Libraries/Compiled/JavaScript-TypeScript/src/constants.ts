// VSN frozen constants (GR-28, GR-17, VR-*)
export const REC_END_OF_RECORDS = 0x0000;
export const REC_FILE_IDENTITY = 0x0001;
export const REC_REVISION = 0x0002;
export const REC_REVISION_SET = 0x0003;
export const REC_FILE_HEAD = 0x0004;
export const REC_CONTENT_OBJECT = 0x0005;
export const REC_COMMIT_MARKER = 0x0006;
export const REC_MODE_DECLARATION = 0x0007;     // OBSOLETE: deprecated, kept for reader compatibility  // OBSOLETE: kept for reader compatibility only
export const REC_STORAGE_POLICY = 0x0009;     // New: authoritative storage classification
export const REC_REPRESENTATION_DESCRIPTOR = 0x0008;

export const FID_RECORDS_END = 0x0000;
export const FID_FILE_ID = 0x0101;
export const FID_REV_ID = 0x0201;
export const FID_REV_FILE_ID = 0x0202;
export const FID_REV_OBJECT_SERIAL = 0x0203;
export const FID_REV_PATH = 0x0210;
export const FID_REV_PRESENCE = 0x0211;
export const FID_HEAD_FILE_ID = 0x0401;
export const FID_HEAD_REV_ID = 0x0402;
export const FID_OBJECT_SERIAL = 0x0501;
export const FID_OBJECT_SIZE = 0x0511;
export const FID_COMMIT_GENERATION = 0x0601;
export const FID_MODE = 0x0701;               // OBSOLETE: ModeDeclaration field (deprecated)
export const FID_STORAGE_POLICY = 0x0901;      // StoragePolicy.field_id (new)

// Modes -- OBSOLETE: deprecated, kept for reader compatibility only
export const MODE_MODERN = 0x01;               // OBSOLETE: was MODERN wire mode
export const MODE_ENTERPRISE = 0x02;           // OBSOLETE: was ENTERPRISE wire mode

// Storage Policy values -- authoritative classification (directly on wire)
export const STORAGE_HIGHLY_VERTICAL    = 1;   // maximum optimization effort
export const STORAGE_VERTICAL           = 2;   // bounded optimization effort
export const STORAGE_HORIZONTAL         = 3;   // low optimization effort
export const STORAGE_HIGHLY_HORIZONTAL  = 4;   // minimal optimization effort

export const REP_DIRECT_1 = 0x0001;
export const REP_EXTENTS_1 = 0x0002;
export const REP_VERSION_1 = 1;

export const PRESENT = 1;
export const DELETED = 2;
export const DIRECTORY = 3;

export const OP_LITERAL_BYTES = 0;
export const OP_OBJECT_SOURCE = 1;
export const OP_NUMERIC = 2;
export const OP_NESTED = 3;

export const MAGIC = Buffer.from("VSN-", "ascii");

// Remaining frozen field IDs (GR-17)
export const FID_RSET_ID = 0x0301;
export const FID_RSET_MEMBERS = 0x0302;
export const FID_RSET_STATE = 0x0303;
export const FID_RSET_DIGEST = 0x0310;
export const FID_HEAD_GENERATION = 0x0410;
export const FID_OBJECT_HASH = 0x0510;
export const FID_COMMIT_HASH = 0x0610;
export const FID_REP_IDENTITY = 0x0801;
export const FID_REP_VERSION = 0x0802;
export const FID_REP_METADATA = 0x0810;

// Record type registry bounds (GR-28)
export const REC_EXTENSION_MIN = 0x8000;
export const REC_EXTENSION_MAX = 0xfffe;
export const REC_RESERVED = 0xffff;

// Hash algorithm identifiers (VR-17) - verification only, never identity
export const HASH_NONE = 0x00;
export const HASH_SHA256 = 0x01;
export const HASH_BLAKE3 = 0x02;

// ---- Writer Storage Policy (informative, NOT on wire) ----
export enum StoragePolicy {
    HIGHLY_VERTICAL = 1,
    VERTICAL = 2,
    HORIZONTAL = 3,
    HIGHLY_HORIZONTAL = 4,
}



