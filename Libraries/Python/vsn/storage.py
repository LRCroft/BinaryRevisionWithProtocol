"""VSN-1 derived storage management.

Indexes, caches, and other derived data are Library facilities.
Recovery and acceptance MUST remain possible without them (SR-02, SR-03).
These structures are NEVER canonical acceptance authorities.
"""
from __future__ import annotations

from dataclasses import dataclass, field as dc_field


@dataclass
class StorageStats:
    """Storage statistics for a container."""
    container_bytes: int = 0
    record_count: int = 0
    object_count: int = 0
    file_count: int = 0
    revision_count: int = 0
    index_entries: int = 0
    cache_entries: int = 0
    cache_bytes: int = 0


@dataclass
class StorageManager:
    """Manages derived storage (indexes, caches) for a VsnStore.

    All derived data can be rebuilt from canonical VSN content.
    Recovery works without any derived data.
    """
    _object_index: dict = dc_field(default_factory=dict)
    _file_index: dict = dc_field(default_factory=dict)
    _content_cache: dict = dc_field(default_factory=dict)
    _valid: bool = False

    def build_indexes(self, store) -> None:
        """Build derived indexes from canonical state."""
        self._object_index.clear()
        self._file_index.clear()
        for serial in store.list_objects():
            info = store.get_object_info(serial)
            self._object_index[serial] = info
        for fid, path in store.list_files():
            if path:
                self._file_index[path] = fid
        self._valid = True

    def invalidate(self) -> None:
        """Invalidate all derived data."""
        self._object_index.clear()
        self._file_index.clear()
        self._content_cache.clear()
        self._valid = False

    def rebuild(self, store) -> None:
        """Rebuild derived data from canonical state."""
        self.invalidate()
        self.build_indexes(store)

    def gc(self) -> int:
        """Garbage-collect cached content. Returns entries removed."""
        n = len(self._content_cache)
        self._content_cache.clear()
        return n

    def stats(self, store) -> StorageStats:
        """Return storage statistics."""
        return StorageStats(
            container_bytes=len(store.to_bytes()) if store._data else 0,
            record_count=len(store._parsed.records) if store._parsed else 0,
            object_count=len(store._objects),
            file_count=len(store._file_ids),
            revision_count=len(store._revisions),
            index_entries=len(self._object_index) + len(self._file_index),
            cache_entries=len(self._content_cache),
            cache_bytes=sum(len(v) for v in self._content_cache.values()),
        )

    @property
    def is_valid(self) -> bool:
        return self._valid
