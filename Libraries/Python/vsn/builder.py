"""VSN container builder: create and edit canonical containers.

Provides a high-level API for building VSN containers from scratch.
The builder accumulates records and objects, then produces canonical
bytes via the writer.
"""
from __future__ import annotations

from . import constants as C
from .primitives import put_u16, put_uvarint
from .writer import encode, direct1_descriptor


class ContainerBuilder:
    """Build a VSN container incrementally."""

    def __init__(self, mode: int = C.MODE_MODERN):
        self.mode = mode
        self.records: list = []  # [(rtype, [(fid, value), ...])]
        self.objects: list = []  # [(serial, descriptor)]
        self._file_ids: set = set()
        self._revision_ids: set = set()
        self._object_serials: set = set()
        self._next_object_serial = 1

    def add_file(self, file_id: bytes) -> "ContainerBuilder":
        """Add a FileIdentity record."""
        if len(file_id) != 16:
            raise ValueError("FileId must be 16 bytes")
        if file_id in self._file_ids:
            raise ValueError("duplicate FileId")
        self._file_ids.add(file_id)
        self.records.append((C.REC_FILE_IDENTITY, [(C.FID_FILE_ID, file_id)]))
        return self

    def add_revision(
        self,
        file_id: bytes,
        revision_id: int,
        object_serial: int | None = None,
        path: str | None = None,
        presence: int = C.PRESENT,
    ) -> "ContainerBuilder":
        """Add a Revision record."""
        if file_id not in self._file_ids:
            raise ValueError("FileId not declared")
        if revision_id in self._revision_ids:
            raise ValueError("duplicate RevisionId")
        self._revision_ids.add(revision_id)
        fields = [
            (C.FID_REV_ID, put_uvarint(revision_id)),
            (C.FID_REV_FILE_ID, file_id),
        ]
        if object_serial is not None:
            fields.append((C.FID_REV_OBJECT_SERIAL, put_uvarint(object_serial)))
        if path is not None:
            fields.append((C.FID_REV_PATH, path.encode("utf-8")))
        fields.append((C.FID_REV_PRESENCE, bytes([presence])))
        self.records.append((C.REC_REVISION, fields))
        return self

    def add_object(self, content: bytes, serial: int | None = None) -> int:
        """Add a ContentObject record and object with DIRECT-1 representation."""
        if serial is None:
            serial = self._next_object_serial
            self._next_object_serial += 1
        if serial in self._object_serials:
            raise ValueError("duplicate ObjectSerial")
        self._object_serials.add(serial)
        # ContentObject record
        fields = [
            (C.FID_OBJECT_SERIAL, put_uvarint(serial)),
            (C.FID_OBJECT_SIZE, put_uvarint(len(content))),
        ]
        self.records.append((C.REC_CONTENT_OBJECT, fields))
        # Object descriptor (DR-0 header + content)
        descriptor = direct1_descriptor(content)
        self.objects.append((serial, descriptor))
        return serial

    def set_head(self, file_id: bytes, revision_id: int) -> "ContainerBuilder":
        """Add a FileHead record."""
        if file_id not in self._file_ids:
            raise ValueError("FileId not declared")
        if revision_id not in self._revision_ids:
            raise ValueError("RevisionId not declared")
        fields = [
            (C.FID_HEAD_FILE_ID, file_id),
            (C.FID_HEAD_REV_ID, put_uvarint(revision_id)),
        ]
        self.records.append((C.REC_FILE_HEAD, fields))
        return self

    def build(self, generation: int = 1) -> bytes:
        """Produce canonical VSN bytes."""
        # Prepend ModeDeclaration
        mode_record = (C.REC_MODE_DECLARATION, [(C.FID_MODE, bytes([self.mode]))])
        all_records = [mode_record] + self.records
        # Append CommitMarker
        commit_record = (C.REC_COMMIT_MARKER, [(C.FID_COMMIT_GENERATION, put_uvarint(generation))])
        all_records.append(commit_record)
        return encode(self.mode, all_records, self.objects, generation)

