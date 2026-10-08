"""VSN-1 semantic model: parsed records, fields, and materialized state.

Identity objects are plain immutable tuples/dataclasses. No identity is
derived from a hash or an offset.
"""
from __future__ import annotations

from dataclasses import dataclass, field as dc_field
from typing import Optional


class FileId(bytes):
    """16-byte logical file identity (UUID)."""


class RevisionId(int):
    """Immutable revision identity (uvarint)."""


class ObjectSerial(int):
    """Container-scoped canonical content-object identity (uvarint)."""


@dataclass(frozen=True)
class Field:
    fid: int
    value: bytes

    @property
    def value_uvarint(self) -> int:
        from .reader import Cursor
        c = Cursor(self.value)
        v = c.read_uvarint()
        return v


@dataclass
class Record:
    rtype: int
    payload: bytes
    fields: list = dc_field(default_factory=list)
    byte_offset: int = 0
    # preserved unknown-field bytes for format-preserving rewrite (GR-32/33)
    unknown_fields: list = dc_field(default_factory=list)

    def field(self, fid: int) -> Optional[Field]:
        for f in self.fields:
            if f.fid == fid:
                return f
        return None


@dataclass
class ObjectEntry:
    serial: ObjectSerial
    length: int
    descriptor: bytes
    byte_offset: int = 0


@dataclass
class Container:
    container_format_version: int
    encoding_version: int
    records: list
    objects: list
    trailer_record_count: int
    trailer_generation: int
    mode: Optional[int] = None
    storage_policy: Optional[int] = None  # NEW: direct StoragePolicy value (1..4)
    byte_length: int = 0
