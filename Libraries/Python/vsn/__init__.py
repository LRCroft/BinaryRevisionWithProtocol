"""VSN-1 Library -- Python implementation."""

from vsn.store import VsnStore
from vsn.transactions import Transaction, StagedChange
from vsn.errors import VsnError, ResourceRefusal
from vsn import constants
from vsn.recovery import recover as recover_fn
from vsn.validate import validate as validate_fn, validate_structural, validate_semantic, validate_content
from vsn.diagnostics import Severity, Category, Diagnostic, validate_with_diagnostics

# Module-level convenience function to open a store from serialized bytes
def open(data):
    return VsnStore.open(data)

__all__ = [
    "VsnStore", "Transaction", "StagedChange", "VsnError",
    "ResourceRefusal", "constants", "open",
    "recover_fn", "validate_fn", "validate_structural", "validate_semantic",
    "validate_content", "validate_with_diagnostics",
    "Severity", "Category", "Diagnostic",
]
