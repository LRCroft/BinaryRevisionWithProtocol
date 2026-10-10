"""VSN-1 frozen error registry (VR-28, VR-29) and exception model.

Identifiers are protocol-assigned and immutable; the Library maps them to
language-idiomatic mechanisms without adding new protocol error IDs.
"""
from __future__ import annotations

from .constants import StoragePolicy, STORAGE_POLICY_TO_WIRE_MODE

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


# ---- Writer Storage Policy semantic errors ----
# These map to frozen protocol error identifiers where equivalent ones exist.
# No new protocol error IDs are invented.


class InvalidStoragePolicy(VsnError):
    """Raised when a StoragePolicy value is outside {HIGHLY_VERTICAL, VERTICAL, HORIZONTAL, HIGHLY_HORIZONTAL}.

    Maps to 0x0010 (RESERVED_VALUE).
    """
    def __init__(self, policy):
        super().__init__(0x0010, "INVALID_STORAGE_POLICY: %r" % (policy,), byte_offset=None)


class PolicyWireModeConflict(VsnError):
    """Raised when writer_options specifies both storage_policy and wire_mode that conflict.

    Maps to 0x0005 (UNSUPPORTED_PROTOCOL_VERSION).
    """
    def __init__(self, policy, mode):
        super().__init__(0x0005, "POLICY_WIRE_MODE_CONFLICT: %r not allowed in wire mode 0x%02X" % (policy.value, mode), byte_offset=None)


class InvalidOptimizationConfiguration(VsnError):
    """Raised when OptimizationConfiguration contains invalid values.

    Maps to 0x0010 (RESERVED_VALUE).
    """
    def __init__(self, field, value):
        super().__init__(0x0010, "INVALID_OPTIMIZATION_CONFIGURATION: %s = %r" % (field, value), byte_offset=None)


class OptimizationBudgetExceeded(VsnError):
    """Raised when optimization effort exceeds budget but fallback may still succeed.

    Maps to 0x000D (VERIFICATION_UNAVAILABLE).
    """
    def __init__(self, detail):
        super().__init__(0x000D, "OPTIMIZATION_BUDGET_EXCEEDED: %s" % detail, byte_offset=None)


class UnsupportedRepresentation(VsnError):
    """Raised when a representation is not allowed (e.g., EXTENTS-1 in ENTERPRISE).

    Maps to 0x0006 (UNSUPPORTED_REPRESENTATION -- frozen protocol ID).
    """
    def __init__(self, rep_id):
        super().__init__(0x0006, "UNSUPPORTED_REPRESENTATION: %s" % (rep_id,), byte_offset=None)
