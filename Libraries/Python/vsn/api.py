"""VSN-1 high-level API: open, materialize, validate, recover.

This is the library-level facade over the parser and representations.
"""
from __future__ import annotations

from . import constants as C
from . import container as _container
from .errors import VsnError, ResourceRefusal
from .model import Container
from .reader import Truncated
from .representations import (
    materialize_direct,
    materialize_extents,
    parse_object_header,
)


class VsnContainer:
    """An opened VSN container with its accepted canonical state."""

    def __init__(self, data: bytes):
        self._data = bytes(data)
        self._parsed: Container = _container.parse(self._data)
        self._object_index = {o.serial: o for o in self._parsed.objects}
        self._content_cache: dict = {}

    @property
    def mode(self) -> int | None:
        return self._parsed.mode

    @property
    def container_format_version(self) -> int:
        return self._parsed.container_format_version

    @property
    def encoding_version(self) -> int:
        return self._parsed.encoding_version

    @property
    def records(self):
        return self._parsed.records

    @property
    def objects(self):
        return self._parsed.objects

    def object_serial(self, serial: int) -> "ObjectEntry":
        from .model import ObjectEntry
        e = self._object_index.get(serial)
        if e is None:
            raise VsnError(0x0008, "missing object %d" % serial)
        return e

    def materialize(self, serial: int, _visited: set | None = None) -> bytes:
        """Materialize the logical content of one object (DIRECT-1/EXTENTS-1)."""
        if _visited is None:
            _visited = set()
        if serial in _visited:
            raise VsnError(0x000C, "dependency cycle at ObjectSerial %d" % serial)
        if serial in self._content_cache:
            return self._content_cache[serial]
        e = self.object_serial(serial)
        ident, ver, rem = parse_object_header(e.descriptor)
        if ident == C.REP_DIRECT_1 and ver == C.REP_VERSION_1:
            out = materialize_direct(rem)
        elif ident == C.REP_EXTENTS_1 and ver == C.REP_VERSION_1:
            out = materialize_extents(rem, lambda s: self.materialize(s, _visited | {serial}))
        else:
            raise VsnError(0x0006, "unsupported representation 0x%04x v%d" % (ident, ver))
        self._content_cache[serial] = out
        return out

    def files(self):
        """Yield (FileId, head_RevisionId) for accepted FileHeads."""
        from .model import FileId, RevisionId
        heads = []
        for rec in self._parsed.records:
            if rec.rtype == C.REC_FILE_HEAD:
                f = rec.field(C.FID_HEAD_FILE_ID)
                r = rec.field(C.FID_HEAD_REV_ID)
                if f is not None and r is not None:
                    heads.append((FileId(f.value), RevisionId(r.value_uvarint)))
        return heads


def open(data: bytes) -> VsnContainer:
    return VsnContainer(data)
