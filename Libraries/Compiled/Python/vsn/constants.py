"""VSN-1 frozen record, field, and registry constants (GR-28, GR-17, VR-*-).

Values are protocol-assigned and MUST NOT be invented by a library.
"""
from __future__ import annotations
from enum import IntEnum

# Record types (GR-28)
REC_END_OF_RECORDS = 0x0000
REC_FILE_IDENTITY = 0x0001
REC_REVISION = 0x0002
REC_REVISION_SET = 0x0003
REC_FILE_HEAD = 0x0004
REC_CONTENT_OBJECT = 0x0005
REC_COMMIT_MARKER           = 0x0006
REC_STORAGE_POLICY          = 0x0009
REC_REPRESENTATION_DESCRIPTOR = 0x0008
REC_MODE_DECLARATION        = 0x0007  # OBSOLETE: deprecated, no longer emitted by canonical writers
REC_EXTENSION_MIN           = 0x8000
REC_EXTENSION_MAX = 0xFFFE
REC_RESERVED = 0xFFFF

# Field IDs (GR-17)
FID_RECORDS_END = 0x0000
FID_FILE_ID = 0x0101          # FileIdentity.FileId (normative field allocation)
FID_REV_ID = 0x0201
FID_REV_FILE_ID = 0x0202
FID_REV_OBJECT_SERIAL = 0x0203
FID_REV_PATH = 0x0210
FID_REV_PRESENCE = 0x0211
FID_RSET_ID = 0x0301
FID_RSET_MEMBERS = 0x0302
FID_RSET_STATE = 0x0303
FID_RSET_DIGEST = 0x0310
FID_HEAD_FILE_ID = 0x0401
FID_HEAD_REV_ID = 0x0402
FID_HEAD_GENERATION = 0x0410
FID_OBJECT_SERIAL = 0x0501
FID_OBJECT_HASH = 0x0510
FID_OBJECT_SIZE = 0x0511
FID_COMMIT_GENERATION = 0x0601
FID_COMMIT_HASH       = 0x0610
FID_MODE              = 0x0701          # OBSOLETE: ModeDeclaration field ID (deprecated, no longer on wire)
FID_STORAGE_POLICY    = 0x0901          # StoragePolicy.field_id
FID_REP_IDENTITY     = 0x0801
FID_REP_VERSION = 0x0802
FID_REP_METADATA = 0x0810

# VSN modes (GR-38) -- OBSOLETE: deprecated, kept for reader compatibility only
MODE_MODERN       = 0x01   # OBSOLETE: was MODERN wire mode
MODE_ENTERPRISE   = 0x02   # OBSOLETE: was ENTERPRISE wire mode

# Storage Policy (REC_STORAGE_POLICY / FID_STORAGE_POLICY) -- authoritative classification
STORAGE_HIGHLY_VERTICAL    = 1
STORAGE_VERTICAL           = 2
STORAGE_HORIZONTAL         = 3
STORAGE_HIGHLY_HORIZONTAL  = 4
VALID_STORAGE_POLICIES     = {STORAGE_HIGHLY_VERTICAL, STORAGE_VERTICAL, STORAGE_HORIZONTAL, STORAGE_HIGHLY_HORIZONTAL}

# Representation identities (VR-*)
REP_DIRECT_1 = 0x0001
REP_EXTENTS_1 = 0x0002
REP_VERSION_1 = 1

# Presence (SR-09)
PRESENT = 1
DELETED = 2
DIRECTORY = 3

# Operand kind tags (VR-23)
OP_LITERAL_BYTES = 0
OP_OBJECT_SOURCE = 1
OP_NUMERIC = 2
OP_NESTED = 3

# Hash algorithm identifiers (VR-17)
HASH_NONE = 0x00
HASH_SHA256 = 0x01
HASH_BLAKE3 = 0x02

# ---- Writer Storage Policy (NORMATIVE on wire via REC_STORAGE_POLICY) ----
# Exactly four values per the frozen Writer Storage Policy Contract.
# These ARE authoritative classification directly encoded in .vsn container binary.


class StoragePolicy(IntEnum):
    """Writer-side storage-policy profile -- NORMATIVE on wire.

    Exactly four values -- no additional values may be added without
    amending the frozen contract (library_api_contract_policy.md).
    
    Storage Policy is directly encoded in .vsn containers via
    REC_STORAGE_POLICY (0x0009) / FID_STORAGE_POLICY (0x0901).
    It IS the authoritative classification on wire.
    """
    HIGHLY_VERTICAL = 1
    VERTICAL = 2
    HORIZONTAL = 3
    HIGHLY_HORIZONTAL = 4


# DEPRECATED (OBSOLETE): WireMode -- CANCELLED architecture. Kept ONLY for
# backward compatibility with writer_options.py validation layer.
# The policy-to-wire-mode mapping is PERMANENTLY CANCELLED (Phase 2).
# Storage Policy IS the authoritative classification on wire. These values
# MUST NOT be used to emit ModeDeclaration or derive storage behavior.
class WireMode(IntEnum):
    MODERN = 0x01
    ENTERPRISE = 0x02


# DEPRECATED (OBSOLETE): CANCELLED mapping. Never emitted by canonical writers.
# This table MUST NOT be used for wire-level classification.
STORAGE_POLICY_TO_WIRE_MODE: dict[StoragePolicy, int] = {
    StoragePolicy.HIGHLY_VERTICAL:   WireMode.MODERN,
    StoragePolicy.VERTICAL:         WireMode.MODERN,
    StoragePolicy.HORIZONTAL:       WireMode.ENTERPRISE,
    StoragePolicy.HIGHLY_HORIZONTAL: WireMode.ENTERPRISE,
}


# DEPRECATED (OBSOLETE): CANCELLED reverse mapping. Kept for compat only.
WIRE_MODE_TO_POLICIES: dict[int, list[StoragePolicy]] = {
    WireMode.MODERN.value:       [StoragePolicy.HIGHLY_VERTICAL, StoragePolicy.VERTICAL],
    WireMode.ENTERPRISE.value:   [StoragePolicy.HORIZONTAL, StoragePolicy.HIGHLY_HORIZONTAL],
}
