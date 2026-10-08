"""VSN-1 mutable container store: full library API.

VsnStore is the primary public API for working with VSN containers.
It supports creating, opening, modifying, and committing containers
with complete file, revision, and object management.
"""
from __future__ import annotations

import threading
import uuid
from typing import Optional

from . import constants as C
from . import container as _container
from .errors import VsnError
from .model import FileId, RevisionId
from .primitives import put_uvarint
from .representations import (
    materialize_direct,
    materialize_extents,
    parse_object_header,
)
from .writer import encode, direct1_descriptor
from .constants import StoragePolicy, STORAGE_POLICY_TO_WIRE_MODE
from .writer_options import WriterOptions


class VsnStore:
    """Mutable VSN container with full library API."""

    def __init__(self, data: bytes | None = None, mode: int = C.MODE_MODERN, *,
                 storage_policy: StoragePolicy | None = None,
                 optimization_config=None):  # type: ignore[no-untyped-def] -- Optional[OptimizationConfiguration] would self-import
        if data is not None:
            self._data = bytes(data)
            self._parsed = _container.parse(self._data)
            self._mode = self._parsed.mode or mode
        else:
            # Determine wire mode from storage policy when no explicit mode given.
            if storage_policy is not None:
                self._mode = C.MODE_MODERN  # default wire mode for canonical writers
            else:
                self._mode = mode
            self._data = b""
            self._parsed = None
        self._storage_policy: StoragePolicy | None = storage_policy
        self._optimization_config = optimization_config
        self._closed = False
        self._lock = threading.Lock()
        self._build_state()

    def _build_state(self):
        """Build internal indexes from parsed container."""
        self._file_ids: dict[bytes, dict] = {}
        self._revisions: dict[int, dict] = {}
        self._objects: dict[int, bytes] = {}
        self._content_cache: dict[int, bytes] = {}
        self._next_object_serial = 1
        self._next_revision_id = 1
        self._generation = 0
        if self._parsed is None:
            return
        for rec in self._parsed.records:
            if rec.rtype == C.REC_FILE_IDENTITY:
                f = rec.field(C.FID_FILE_ID)
                if f:
                    self._file_ids[f.value] = {"path": None, "head_rev": None}
            elif rec.rtype == C.REC_REVISION:
                rid_f = rec.field(C.FID_REV_ID)
                fid_f = rec.field(C.FID_REV_FILE_ID)
                obj_f = rec.field(C.FID_REV_OBJECT_SERIAL)
                path_f = rec.field(C.FID_REV_PATH)
                pres_f = rec.field(C.FID_REV_PRESENCE)
                if rid_f and fid_f:
                    rid = rid_f.value_uvarint
                    fid = fid_f.value
                    self._revisions[rid] = {
                        "file_id": fid,
                        "object_serial": obj_f.value_uvarint if obj_f else None,
                        "path": path_f.value.decode("utf-8") if path_f else None,
                        "presence": pres_f.value[0] if pres_f else C.PRESENT,
                    }
                    if rid >= self._next_revision_id:
                        self._next_revision_id = rid + 1
                    if fid in self._file_ids and path_f:
                        self._file_ids[fid]["path"] = path_f.value.decode("utf-8")
            elif rec.rtype == C.REC_FILE_HEAD:
                fid_f = rec.field(C.FID_HEAD_FILE_ID)
                rid_f = rec.field(C.FID_HEAD_REV_ID)
                if fid_f and rid_f:
                    fid = fid_f.value
                    rid = rid_f.value_uvarint
                    if fid in self._file_ids:
                        self._file_ids[fid]["head_rev"] = rid
            elif rec.rtype == C.REC_COMMIT_MARKER:
                gen_f = rec.field(C.FID_COMMIT_GENERATION)
                if gen_f:
                    self._generation = gen_f.value_uvarint
        for obj in self._parsed.objects:
            self._objects[obj.serial] = obj.descriptor
            if obj.serial >= self._next_object_serial:
                self._next_object_serial = obj.serial + 1

    def preferred_rep(self) -> int:
        """Determine preferred representation from storage policy.

        HIGHLY_VERTICAL / VERTICAL  (MODERN): prefer EXTENTS-1 when beneficial.
        HORIZONTAL                  (ENTERPRISE): DIRECT-1 baseline.
        HIGHLY_HORIZONTAL           (ENTERPRISE): DIRECT-1 required only.
        None (legacy): always DIRECT-1.
        """
        if self._storage_policy is None:
            return C.REP_DIRECT_1
        policy = self._storage_policy
        if policy == StoragePolicy.HIGHLY_HORIZONTAL:
            return C.REP_DIRECT_1
        if policy == StoragePolicy.HORIZONTAL:
            return C.REP_DIRECT_1
        return C.REP_EXTENTS_1

    def _content_saves_over_extents(self, content: bytes) -> bool:
        """Heuristic: would EXTENTS-1 save space vs DIRECT-1?"""
        opt = self._optimization_config
        min_savings = None
        if opt is not None:
            min_savings = getattr(opt, "min_savings_bytes", None)
        if min_savings is not None and min_savings > 0:
            overhead_extents = 4 + 1 + 3
            return len(content) - overhead_extents >= min_savings
        return len(content) >= 64

    def _resolve_optimization(self, content: bytes) -> int:
        """Choose representation with fallback (per contract Section 11)."""
        preferred = self.preferred_rep()
        if preferred == C.REP_DIRECT_1:
            return C.REP_DIRECT_1
        if not self._content_saves_over_extents(content):
            return C.REP_DIRECT_1
        if self._optimization_config is not None:
            md = getattr(self._optimization_config, "max_dependency_depth", None)
            if md is not None and md < 1:
                return C.REP_DIRECT_1
        return preferred

    def _to_inspection_dict(self) -> dict:
        """Return a dict of container-level metadata (for test capabilities)."""
        if self._parsed is None or not self._parsed.records:
            return {"file_count": 0, "object_count": 0, "generation": 0}
        file_count = sum(1 for r in self._parsed.records if hasattr(r, 'rtype') and r.rtype == C.REC_FILE_IDENTITY)
        obj_count = len(self._parsed.objects)
        gen = 0
        for r in self._parsed.records:
            f = r.field(C.FID_COMMIT_GENERATION) if hasattr(r, 'field') else None
            if f is not None and hasattr(f, 'value_uvarint'):
                gen = f.value_uvarint
        return {"file_count": file_count, "object_count": obj_count, "generation": gen}

    @classmethod
    def create(cls, mode: int = C.MODE_MODERN) -> "VsnStore":
        return cls(data=None, mode=mode)

    @classmethod
    def open(cls, data: bytes) -> "VsnStore":
        return cls(data=data)

    def close(self):
        with self._lock:
            self._closed = True
            self._content_cache.clear()

    def _check_open(self):
        if self._closed:
            raise VsnError(0x0001, "container is closed")

    @property
    def mode(self) -> int:
        return self._mode

    @property
    def generation(self) -> int:
        return self._generation

    # --- File API ---

    def create_file(self, path: str, content: bytes = b"") -> bytes:
        """Create a new file. Returns FileId (16 bytes)."""
        with self._lock:
            self._check_open()
            for fid, info in self._file_ids.items():
                if info.get("path") == path:
                    raise VsnError(0x000A, "duplicate path %r" % path)
            file_id = bytes(uuid.uuid4().bytes)
            self._file_ids[file_id] = {"path": path, "head_rev": None}
            serial = self._add_object(content)
            rid = self._next_revision_id
            self._next_revision_id += 1
            self._revisions[rid] = {
                "file_id": file_id, "object_serial": serial,
                "path": path, "presence": C.PRESENT,
            }
            self._file_ids[file_id]["head_rev"] = rid
            return file_id

    def read_file(self, file_id: bytes) -> bytes:
        """Read logical content at accepted revision."""
        self._check_open()
        info = self._file_ids.get(file_id)
        if info is None:
            raise VsnError(0x0009, "unknown FileId")
        rid = info.get("head_rev")
        if rid is None:
            raise VsnError(0x0009, "no accepted revision")
        rev = self._revisions[rid]
        if rev["presence"] == C.DELETED:
            raise VsnError(0x0009, "file is deleted")
        serial = rev.get("object_serial")
        if serial is None:
            return b""
        return self.materialize(serial)

    def write_file(self, file_id: bytes, content: bytes) -> None:
        """Replace file content (new revision)."""
        with self._lock:
            self._check_open()
            info = self._file_ids.get(file_id)
            if info is None:
                raise VsnError(0x0009, "unknown FileId")
            serial = self._add_object(content)
            rid = self._next_revision_id
            self._next_revision_id += 1
            self._revisions[rid] = {
                "file_id": file_id, "object_serial": serial,
                "path": info.get("path"), "presence": C.PRESENT,
            }
            info["head_rev"] = rid

    def delete_file(self, file_id: bytes) -> None:
        """Mark file as deleted."""
        self._check_open()
        info = self._file_ids.get(file_id)
        if info is None:
            raise VsnError(0x0009, "unknown FileId")
        rid = self._next_revision_id
        self._next_revision_id += 1
        self._revisions[rid] = {
            "file_id": file_id, "object_serial": None,
            "path": info.get("path"), "presence": C.DELETED,
        }
        info["head_rev"] = rid

    def rename_file(self, file_id: bytes, new_path: str) -> None:
        """Rename a file (new revision)."""
        self._check_open()
        info = self._file_ids.get(file_id)
        if info is None:
            raise VsnError(0x0009, "unknown FileId")
        for fid, inf in self._file_ids.items():
            if fid != file_id and inf.get("path") == new_path:
                raise VsnError(0x000A, "duplicate path %r" % new_path)
        rid = info.get("head_rev")
        old_rev = self._revisions.get(rid, {})
        new_rid = self._next_revision_id
        self._next_revision_id += 1
        self._revisions[new_rid] = {
            "file_id": file_id,
            "object_serial": old_rev.get("object_serial"),
            "path": new_path,
            "presence": old_rev.get("presence", C.PRESENT),
        }
        info["head_rev"] = new_rid
        info["path"] = new_path

    def list_files(self) -> list[tuple[bytes, str | None]]:
        """List all files as (FileId, path)."""
        self._check_open()
        return [(fid, info.get("path")) for fid, info in self._file_ids.items()]


    def files(self):
        return self.list_files()
    def file_exists(self, file_id: bytes) -> bool:
        self._check_open()
        info = self._file_ids.get(file_id)
        if info is None:
            return False
        rid = info.get("head_rev")
        if rid is None:
            return False
        return self._revisions[rid]["presence"] != C.DELETED

    def get_file_id(self, path: str) -> bytes | None:
        """Lookup FileId by path."""
        self._check_open()
        for fid, info in self._file_ids.items():
            if info.get("path") == path:
                return fid
        return None

    # --- Revision API ---

    def list_revisions(self, file_id: bytes | None = None) -> list[int]:
        self._check_open()
        if file_id is None:
            return sorted(self._revisions.keys())
        return sorted(rid for rid, rev in self._revisions.items()
                      if rev["file_id"] == file_id)

    def get_revision(self, revision_id: int) -> dict:
        self._check_open()
        rev = self._revisions.get(revision_id)
        if rev is None:
            raise VsnError(0x0009, "unknown RevisionId %d" % revision_id)
        return dict(rev, revision_id=revision_id)

    def get_current_revision(self, file_id: bytes) -> int | None:
        self._check_open()
        info = self._file_ids.get(file_id)
        if info is None:
            return None
        return info.get("head_rev")

    def checkout_revision(self, file_id: bytes, revision_id: int) -> bytes:
        self._check_open()
        rev = self._revisions.get(revision_id)
        if rev is None:
            raise VsnError(0x0009, "unknown RevisionId %d" % revision_id)
        if rev["file_id"] != file_id:
            raise VsnError(0x000B, "RevisionId does not belong to FileId")
        serial = rev.get("object_serial")
        if serial is None:
            return b""
        return self.materialize(serial)

    def restore_revision(self, file_id: bytes, revision_id: int) -> None:
        self._check_open()
        rev = self._revisions.get(revision_id)
        if rev is None:
            raise VsnError(0x0009, "unknown RevisionId %d" % revision_id)
        if rev["file_id"] != file_id:
            raise VsnError(0x000B, "RevisionId does not belong to FileId")
        old_serial = rev.get("object_serial")
        content = self.materialize(old_serial) if old_serial else b""
        self.write_file(file_id, content)

    # --- History retention (Library capability, NOT a VSN protocol rule) ---

    def limit_cleanup(self, file_id: bytes, limit: int) -> list[int]:
        """LimitCleanUp: retain only the newest `limit` revisions of a file.

        Scope is a single file's history, matching the VSN revision model in
        which every Revision names one FileId and each file has its own head.

        `limit` is the maximum number of revisions retained. It MUST be >= 1;
        limit == 0 is rejected (0x000C) so that a slipped argument cannot
        silently destroy an entire history. If the file already has <= limit
        revisions nothing is removed.

        The newest `limit` revisions are retained and every older revision is
        removed from the store's canonical state. Retained revisions are never
        rewritten: their RevisionId, contents and ObjectSerial are untouched,
        so the next `commit()` re-emits them byte-identically.

        The file's head revision is always the newest, so it is always retained
        and the FileHead record can never be left dangling.

        Objects are deliberately NOT removed. The object section is a shared
        content store: a retained revision elsewhere, or an EXTENTS-1 COPY
        operand, may still reference them. Reclaiming objects is a separate
        operation, not part of history retention.

        Returns the removed RevisionIds in ascending order, and is idempotent:
        a second call with the same limit removes nothing and changes nothing.
        The change is applied atomically to in-memory state; persist it with the
        normal `commit()`.
        """
        self._check_open()
        if limit < 1:
            raise VsnError(0x000C, "LimitCleanUp limit must be >= 1, got %d" % limit)
        if file_id not in self._file_ids:
            raise VsnError(0x0009, "unknown FileId")

        # Canonical revision ordering is ascending RevisionId.
        rids = [r for r in sorted(self._revisions)
                if self._revisions[r]["file_id"] == file_id]
        if len(rids) <= limit:
            return []                      # nothing to do; no state is touched
        keep = set(rids[len(rids) - limit:])
        removed = [r for r in rids if r not in keep]

        head = self._file_ids[file_id].get("head_rev")
        if head is not None and head in removed:
            # Defensive: the head is the newest revision, so this cannot happen
            # while limit >= 1. Refuse rather than emit a dangling FileHead.
            raise VsnError(0x000C,
                           "LimitCleanUp would remove head revision %d" % head)

        # Apply atomically: snapshot, mutate, and roll back on any failure so a
        # failed cleanup never leaves partially pruned history behind.
        snapshot = dict(self._revisions)
        cache_snapshot = dict(self._content_cache)
        try:
            for rid in removed:
                del self._revisions[rid]
            self._content_cache.clear()
        except Exception:
            self._revisions = snapshot
            self._content_cache = cache_snapshot
            raise
        return removed

    # --- Object API ---

    def _add_object(self, content: bytes) -> int:
        serial = self._next_object_serial
        self._next_object_serial += 1
        self._objects[serial] = direct1_descriptor(content)
        return serial

    def get_object_serial(self, file_id: bytes,
                          revision_id: int | None = None) -> int | None:
        """Resolve the ObjectSerial a file's revision names.

        Mirrors the C# / TypeScript semantics: with no explicit revision the
        file's accepted head revision is used; a deleted revision resolves to
        None. This is part of the required Object API ("retrieve ObjectSerial").
        """
        self._check_open()
        if file_id not in self._file_ids:
            raise VsnError(0x0009, "unknown FileId")
        rid = revision_id if revision_id is not None \
            else self._file_ids[file_id].get("head_rev")
        if rid is None:
            return None
        rev = self._revisions.get(rid)
        if rev is None:
            return None
        return rev.get("object_serial")

    def list_objects(self) -> list[int]:
        self._check_open()
        return sorted(self._objects.keys())

    def get_object_info(self, serial: int) -> dict:
        self._check_open()
        desc = self._objects.get(serial)
        if desc is None:
            raise VsnError(0x0008, "missing object %d" % serial)
        ident, ver, rem = parse_object_header(desc)
        return {
            "serial": serial, "length": len(rem),
            "representation_identity": ident,
            "representation_version": ver,
        }

    def materialize(self, serial: int, _visited: set | None = None) -> bytes:
        self._check_open()
        if _visited is None:
            _visited = set()
        if serial in _visited:
            raise VsnError(0x000C, "cycle at ObjectSerial %d" % serial)
        if serial in self._content_cache:
            return self._content_cache[serial]
        desc = self._objects.get(serial)
        if desc is None:
            raise VsnError(0x0008, "missing object %d" % serial)
        ident, ver, rem = parse_object_header(desc)
        if ident == C.REP_DIRECT_1 and ver == C.REP_VERSION_1:
            out = materialize_direct(rem)
        elif ident == C.REP_EXTENTS_1 and ver == C.REP_VERSION_1:
            out = materialize_extents(rem, lambda s: self.materialize(s, _visited | {serial}))
        else:
            raise VsnError(0x0006, "unsupported rep 0x%04x v%d" % (ident, ver))
        self._content_cache[serial] = out
        return out


    # --- Container lifecycle ---

    def to_bytes(self) -> bytes:
        """Produce canonical VSN-1 bytes from current state."""
        self._check_open()
        self._generation += 1
        records = []
        # Canonical: always emit REC_STORAGE_POLICY. NEVER fall back to ModeDeclaration.
        if self._storage_policy is not None:
            policy_val = self._storage_policy.value
        elif self._mode == C.MODE_ENTERPRISE:
            # Derive HORIZONTAL from wire mode so round-trip recovers ENTERPRISE
            policy_val = C.STORAGE_HORIZONTAL
        else:
            # Default to HIGHLY_VERTICAL for MODERN mode
            policy_val = C.STORAGE_HIGHLY_VERTICAL
        records.append((C.REC_STORAGE_POLICY, [(C.FID_STORAGE_POLICY, bytes([policy_val]))]))
        for fid in self._file_ids:
            records.append((C.REC_FILE_IDENTITY, [(C.FID_FILE_ID, fid)]))
        for rid in sorted(self._revisions.keys()):
            rev = self._revisions[rid]
            fields = [
                (C.FID_REV_ID, put_uvarint(rid)),
                (C.FID_REV_FILE_ID, rev["file_id"]),
            ]
            if rev.get("object_serial") is not None:
                fields.append((C.FID_REV_OBJECT_SERIAL, put_uvarint(rev["object_serial"])))
            if rev.get("path") is not None:
                fields.append((C.FID_REV_PATH, rev["path"].encode("utf-8")))
            fields.append((C.FID_REV_PRESENCE, bytes([rev["presence"]])))
            records.append((C.REC_REVISION, fields))
        for serial in sorted(self._objects.keys()):
            desc = self._objects[serial]
            _, _, rem = parse_object_header(desc)
            fields = [(C.FID_OBJECT_SERIAL, put_uvarint(serial))]
            # 0x0511 declared size is the LOGICAL content length (SR-27, DR-6),
            # never the representation payload length. For EXTENTS-1 the payload
            # remainder is an operation collection whose length differs from the
            # materialized output, so the two must never be conflated.
            # Frozen vector EXT-02/EXT-03 is authoritative: serial 20 has a
            # 17-byte remainder but declares size 12 (its materialized length).
            # The field is OPTIONAL (SR-27), so it is omitted when the logical
            # length cannot be resolved (missing dependency, cycle, or an
            # unsupported representation, which is not an invalid state).
            try:
                logical_length = len(self.materialize(serial))
            except VsnError:
                logical_length = None
            if logical_length is not None:
                fields.append((C.FID_OBJECT_SIZE, put_uvarint(logical_length)))
            records.append((C.REC_CONTENT_OBJECT, fields))
        for fid, info in self._file_ids.items():
            rid = info.get("head_rev")
            if rid is not None:
                fields = [
                    (C.FID_HEAD_FILE_ID, fid),
                    (C.FID_HEAD_REV_ID, put_uvarint(rid)),
                ]
                records.append((C.REC_FILE_HEAD, fields))
        records.append((C.REC_COMMIT_MARKER, [(C.FID_COMMIT_GENERATION, put_uvarint(self._generation))]))
        objects = [(s, self._objects[s]) for s in sorted(self._objects.keys())]
        return encode(self._mode, records, objects, self._generation)

    def commit(self) -> bytes:
        """Commit current state and return canonical bytes."""
        with self._lock:
            self._check_open()
            data = self.to_bytes()
            self._data = data
            self._parsed = _container.parse(data)
            self._content_cache.clear()
            return data

    def reopen(self, data: bytes | None = None) -> None:
        """Reopen from bytes (or from last committed state)."""
        self._check_open()
        if data is None:
            data = self._data
        self._data = bytes(data)
        self._parsed = _container.parse(self._data)
        self._content_cache.clear()
        self._build_state()

        return self._generation
