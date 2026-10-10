"""VSN-1 structured diagnostics.

Diagnostics carry error identity, severity, category, and context.
Protocol diagnostics map to the frozen VSN error registry.
Library-only diagnostics are explicitly distinguished.
"""
from __future__ import annotations

from dataclasses import dataclass, field as dc_field
from enum import Enum
from typing import Optional

from .errors import ERRORS, VsnError


class Severity(Enum):
    ERROR = "error"
    WARNING = "warning"
    INFO = "info"


class Category(Enum):
    PROTOCOL = "protocol"       # frozen VSN error
    LIBRARY = "library"         # library-only diagnostic
    DERIVED = "derived"         # derived-data diagnostic


@dataclass
class Diagnostic:
    """Structured diagnostic carrying full context."""
    code: int
    name: str
    severity: Severity
    category: Category
    message: str
    byte_offset: Optional[int] = None
    record_type: Optional[int] = None
    field_id: Optional[int] = None
    object_serial: Optional[int] = None
    file_id: Optional[bytes] = None
    revision_id: Optional[int] = None
    rep_identity: Optional[int] = None
    rep_version: Optional[int] = None
    operation: Optional[str] = None
    cause: Optional[Exception] = None

    @classmethod
    def from_vsn_error(cls, e: VsnError, operation: str | None = None) -> "Diagnostic":
        return cls(
            code=e.code,
            name=e.name,
            severity=Severity.ERROR,
            category=Category.PROTOCOL,
            message=e.message,
            byte_offset=e.byte_offset,
            operation=operation,
            cause=e,
        )

    @classmethod
    def library_warning(cls, name: str, message: str, **kw) -> "Diagnostic":
        return cls(
            code=-1, name=name, severity=Severity.WARNING,
            category=Category.LIBRARY, message=message, **kw,
        )


def validate_with_diagnostics(data: bytes, level: str = "Full") -> list[Diagnostic]:
    """Run validation and return diagnostics instead of raising."""
    from . import validate as _validate
    diags = []
    for lvl in _validation_levels(level):
        try:
            if lvl == "Structural":
                _validate.validate_structural(data)
            elif lvl == "Semantic":
                _validate.validate_semantic(data)
            elif lvl == "Recovery":
                from .recovery import recover
                recover(data)
            elif lvl == "Content":
                from .validate import validate_content
                validate_content(data)
        except VsnError as e:
            diags.append(Diagnostic.from_vsn_error(e, operation=lvl))
            break
        except Exception as e:
            diags.append(Diagnostic(
                code=-1, name="LIBRARY_ERROR", severity=Severity.ERROR,
                category=Category.LIBRARY, message=str(e),
                operation=lvl, cause=e,
            ))
            break
    return diags


def _validation_levels(level: str) -> list[str]:
    if level == "Structural":
        return ["Structural"]
    if level == "Semantic":
        return ["Structural", "Semantic"]
    if level == "Recovery":
        return ["Structural", "Semantic", "Recovery"]
    if level == "Content":
        return ["Structural", "Semantic", "Content"]
    if level == "Full":
        return ["Structural", "Semantic", "Recovery", "Content"]
    raise ValueError("unknown validation level %r" % level)
