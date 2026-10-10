"""VSN-1 Library -- Python implementation."""

from vsn.store import VsnStore
from vsn.transactions import Transaction, StagedChange
from vsn.errors import VsnError, ResourceRefusal
from vsn.writer_options import WriterOptions, OptimizationConfiguration, SearchConfiguration
from vsn.constants import (
    StoragePolicy, WireMode,
    STORAGE_POLICY_TO_WIRE_MODE, WIRE_MODE_TO_POLICIES,
)
from vsn import constants
from vsn.recovery import recover as recover_fn
from vsn.validate import validate as validate_fn, validate_structural, validate_semantic, validate_content
from vsn.diagnostics import Severity, Category, Diagnostic, validate_with_diagnostics

# Module-level convenience function to open a store from serialized bytes
def open(data):
    return VsnStore.open(data)


# Container inspection helper for tests
def inspect_container(store):  # type: ignore[no-untyped-def]
    """Inspect container metadata from a store (test capability)."""
    return store._to_inspection_dict()


# Backwards-compatible aliases for the conformance runner test suite
def validate_container(data, level=None):  # type: ignore[no-untyped-def]
    """Validate and return empty list on success (test alias for validate_fn which raises)."""
    try:
        validate_fn(data, level)
        return []
    except VsnError as e:
        return [str(e)]
def recover_container(data):
    """Alias for recover_fn returning RecoveryResult with .status."""
    from vsn.recovery import RecoveryResult
    r = recover_fn(data)
    return RecoveryResult(
        accepted_generation=r.accepted_generation,
        recovered=r.recovered,
        tail_present=r.tail_present,
        status=r.status,
        message=r.message,
    )

__all__ = [
    "VsnStore", "Transaction", "StagedChange", "VsnError",
    "ResourceRefusal", "WriterOptions", "OptimizationConfiguration", "SearchConfiguration",
    "StoragePolicy", "WireMode",
    "STORAGE_POLICY_TO_WIRE_MODE", "WIRE_MODE_TO_POLICIES",
    "constants", "open", "inspect_container",
    "recover_fn", "validate_fn", "validate_structural", "validate_semantic",
    "validate_content", "validate_with_diagnostics",
    "recover_container",
    "Severity", "Category", "Diagnostic",
]
