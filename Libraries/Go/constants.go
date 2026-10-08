// Package vsn is the Go implementation of the VSN-1 Library.
//
// The frozen VSN-1 protocol (grammar, record types, field ids, representations,
// error identifiers) is unchanged; this package only implements Library-level
// behaviour above it, mirroring the Python/C#/TypeScript references.
package vsn

// Frozen VSN error identifiers (VR-28, VR-29).
const (
	ErrOK                          uint16 = 0x0000
	ErrMalformedContainer          uint16 = 0x0001
	ErrTruncated                   uint16 = 0x0002
	ErrUnsupportedContainerVersion uint16 = 0x0003
	ErrUnsupportedEncodingVersion  uint16 = 0x0004
	ErrUnsupportedProtocolVersion  uint16 = 0x0005
	ErrUnsupportedRepresentation   uint16 = 0x0006
	ErrUnsupportedTransform        uint16 = 0x0007
	ErrMissingObject               uint16 = 0x0008
	ErrMissingCanonicalReference   uint16 = 0x0009
	ErrDuplicateIdentity           uint16 = 0x000A
	ErrInvalidRelationship         uint16 = 0x000B
	ErrInvalidCanonicalState       uint16 = 0x000C
	ErrVerificationUnavailable     uint16 = 0x000D
	ErrVerificationMismatch        uint16 = 0x000E
	ErrInvalidUTF8                 uint16 = 0x000F
	ErrReservedValue               uint16 = 0x0010
	ErrInvalidFieldOrdering        uint16 = 0x0011
	ErrInvalidLength               uint16 = 0x0012
	ErrUnknownMandatoryRecord      uint16 = 0x0013
	ErrAccessOrDecryptionFailure   uint16 = 0x0014
)

// errorNames maps a frozen identifier to its registry name.
var errorNames = map[uint16]string{
	ErrOK:                          "OK",
	ErrMalformedContainer:          "MALFORMED_CONTAINER",
	ErrTruncated:                   "TRUNCATED",
	ErrUnsupportedContainerVersion: "UNSUPPORTED_CONTAINER_VERSION",
	ErrUnsupportedEncodingVersion:  "UNSUPPORTED_ENCODING_VERSION",
	ErrUnsupportedProtocolVersion:  "UNSUPPORTED_PROTOCOL_VERSION",
	ErrUnsupportedRepresentation:   "UNSUPPORTED_REPRESENTATION",
	ErrUnsupportedTransform:        "UNSUPPORTED_TRANSFORM",
	ErrMissingObject:               "MISSING_OBJECT",
	ErrMissingCanonicalReference:   "MISSING_CANONICAL_REFERENCE",
	ErrDuplicateIdentity:           "DUPLICATE_IDENTITY",
	ErrInvalidRelationship:         "INVALID_RELATIONSHIP",
	ErrInvalidCanonicalState:       "INVALID_CANONICAL_STATE",
	ErrVerificationUnavailable:     "VERIFICATION_UNAVAILABLE",
	ErrVerificationMismatch:        "VERIFICATION_MISMATCH",
	ErrInvalidUTF8:                 "INVALID_UTF8",
	ErrReservedValue:               "RESERVED_VALUE",
	ErrInvalidFieldOrdering:        "INVALID_FIELD_ORDERING",
	ErrInvalidLength:               "INVALID_LENGTH",
	ErrUnknownMandatoryRecord:      "UNKNOWN_MANDATORY_RECORD",
	ErrAccessOrDecryptionFailure:   "ACCESS_OR_DECRYPTION_FAILURE",
}

// Error is the Library error type. It always carries a frozen error identifier;
// the Library never invents an identifier of its own.
type Error struct {
	Code       uint16
	Message    string
	ByteOffset int // diagnostic location only, never identity; -1 when unknown
}

// Error implements the error interface.
func (e *Error) Error() string {
	return e.Name() + ": " + e.Message
}

// Name returns the frozen registry name for the carried identifier.
func (e *Error) Name() string {
	if n, ok := errorNames[e.Code]; ok {
		return n
	}
	return "UNKNOWN"
}

// newError builds a Library error with no byte offset.
func newError(code uint16, msg string) *Error {
	return &Error{Code: code, Message: msg, ByteOffset: -1}
}

// newErrorAt builds a Library error carrying a diagnostic byte offset.
func newErrorAt(code uint16, msg string, off int) *Error {
	return &Error{Code: code, Message: msg, ByteOffset: off}
}

// Physical end-of-data reached mid-unit (GR-47) is reported with the frozen
// TRUNCATED identifier (0x0002), so callers — notably recovery — can always
// distinguish truncation from structurally malformed data (GR-48) by code.

// Magic is the frozen container signature.
var Magic = []byte{0x56, 0x53, 0x4E, 0x2D} // "VSN-"

const (
	// ContainerFormatVersion is the only supported container format version.
	ContainerFormatVersion uint16 = 1
	// EncodingVersion is the only supported encoding version.
	EncodingVersion uint16 = 1
)

// Record types (GR-28).
const (
	RecEndOfRecords      uint16 = 0x0000
	RecFileIdentity      uint16 = 0x0001
	RecRevision          uint16 = 0x0002
	RecRevisionSet       uint16 = 0x0003
	RecFileHead          uint16 = 0x0004
	RecContentObject     uint16 = 0x0005
	RecCommitMarker      uint16 = 0x0006
	RecModeDeclaration   uint16 = 0x0007          // OBSOLETE: kept for reader compatibility only
	RecStoragePolicy     uint16 = 0x0009          // New: authoritative storage classification
	RepRepresentationDescriptor uint16 = 0x0008
	RecExtensionMin     uint16 = 0x8000
	RecExtensionMax     uint16 = 0xFFFE
	RecReserved         uint16 = 0xFFFF
)
// Field IDs (GR-17).
const (
FidRecordsEnd      uint16 = 0x0000
FidFileID          uint16 = 0x0101
FidRevID           uint16 = 0x0201
FidRevFileID       uint16 = 0x0202
FidRevObjectSerial uint16 = 0x0203
FidRevPath         uint16 = 0x0210
FidRevPresence     uint16 = 0x0211
FidRsetId          uint16 = 0x0301
FidRsetMembers     uint16 = 0x0302
FidRsetState       uint16 = 0x0303
FidRsetDigest      uint16 = 0x0310
FidHeadFileID      uint16 = 0x0401
FidHeadRevID       uint16 = 0x0402
FidHeadGeneration  uint16 = 0x0410
FidObjectSerial    uint16 = 0x0501
FidObjectHash      uint16 = 0x0510
FidObjectSize      uint16 = 0x0511
FidCommitGen       uint16 = 0x0601
FidCommitHash      uint16 = 0x0610
FidMode            uint16 = 0x0701
	FidStoragePolicy   uint16 = 0x0901 // StoragePolicy.field_id (new)

FidRepIdentity     uint16 = 0x0801
FidRepVersion      uint16 = 0x0802
FidRepMetadata     uint16 = 0x0810
)

// VSN modes (GR-38) -- OBSOLETE: deprecated, kept for reader compatibility only
const ModeModern uint8 = 0x01 // OBSOLETE: was MODERN wire mode

// Storage Policy values -- authoritative classification (directly on wire)

type StoragePolicy int

const (
	StoragePolicyHighlyVertical   StoragePolicy = 1
	StoragePolicyVertical         StoragePolicy = 2
	StoragePolicyHorizontal       StoragePolicy = 3
	StoragePolicyHighlyHorizontal StoragePolicy = 4
)

func (p StoragePolicy) WireMode() uint8 {
	// OBSOLETE: This mapping is PERMANENTLY CANCELLED (Phase 3).
	// Kept only for backward compatibility. Storage Policy is now direct classification.
	switch p {
	case StoragePolicyHighlyVertical, StoragePolicyVertical:
		return ModeModern
	default:
		return ModeEnterprise
	}
}

const ModeEnterprise uint8 = 0x02


// Representation identities.
const RepDirect1 uint16 = 0x0001

// Presence values (SR-09).
const (
	Present    uint8 = 1
	Deleted    uint8 = 2
	Directory  uint8 = 3
)

// Hash algorithm identifiers.
const HashNone uint8 = 0x00
// Additional representation constants.
const RepVersion1 uint16 = 1
const RepExtents1 uint16 = 0x0002

// Enterprise mode.

// SHA-256 and BLAKE3 hash identifiers.
const HashSHA256 uint8 = 0x01
const HashBlake3 uint8 = 0x02

// Operand kind tags (VR-23).
const (
	OpLiteralBytes uint64 = 0
	OpObjectSource uint64 = 1
	OpNumeric      uint64 = 2
	OpNested       uint64 = 3
)
