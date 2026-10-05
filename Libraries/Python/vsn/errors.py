"""VSN-1 frozen error registry (VR-28, VR-29) and exception model.

Identifiers are protocol-assigned and immutable; the Library maps them to
language-idiomatic mechanisms without adding new protocol error IDs.
"""
from __future__ import annotations

# Frozen error identifiers (value -> name)
ERRORS = {
    0x0000: "OK",
    0x0001: "MALFORMED_CONTAINER",
    0x0002: "TRUNCATED",
    0x0003: "UNSUPPORTED_CONTAINER_VERSION",
    0x0004: "UNSUPPORTED_ENCODING_VERSION",
    0x0005: "UNSUPPORTED_PROTOCOL_VERSION",
    0x0006: "UNSUPPORTED_REPRESENTATION",
    0x0007: "UNSUPPORTED_TRANSFORM",
    0x0008: "MISSING_OBJECT",
    0x0009: "MISSING_CANONICAL_REFERENCE",
    0x000A: "DUPLICATE_IDENTITY",
    0x000B: "INVALID_RELATIONSHIP",
    0x000C: "INVALID_CANONICAL_STATE",
    0x000D: "VERIFICATION_UNAVAILABLE",
    0x000E: "VERIFICATION_MISMATCH",
    0x000F: "INVALID_UTF8",
    0x0010: "RESERVED_VALUE",
    0x0011: "INVALID_FIELD_ORDERING",
    0x0012: "INVALID_LENGTH",
    0x0013: "UNKNOWN_MANDATORY_RECORD",
    0x0014: "ACCESS_OR_DECRYPTION_FAILURE",
}

# Resource refusal is NOT a protocol error (RC-29); it is a reader decision.
RESOURCE_REFUSAL = "RESOURCE_REFUSAL"


class VsnError(Exception):
    """Base for all VSN library errors, carrying a frozen error identifier."""

    def __init__(self, code: int, message: str, *, byte_offset: int | None = None):
        super().__init__(message)
        self.code = code
        self.name = ERRORS.get(code, "UNKNOWN")
        self.message = message
        self.byte_offset = byte_offset  # diagnostic location, NOT identity

    def __repr__(self):  # pragma: no cover - debug aid
        return "VsnError(%s: %s)" % (self.name, self.message)


class ResourceRefusal(Exception):
    """A reader-local resource limit was exceeded (not canonical invalidity)."""
