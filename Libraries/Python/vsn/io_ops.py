"""VSN binary-safe import/export.

Import: raw bytes → VSN object.
Export: VSN object → raw bytes.
All operations preserve arbitrary binary content including NUL bytes.
"""
from __future__ import annotations

import io
from typing import Iterator

from .errors import VsnError


def import_bytes(store, path: str, content: bytes) -> bytes:
    """Import raw bytes as a new file. Returns FileId."""
    if not isinstance(content, (bytes, bytearray)):
        raise VsnError(0x0001, "content must be bytes")
    return store.create_file(path, content)


def export_bytes(store, file_id: bytes) -> bytes:
    """Export materialized file content as bytes."""
    return store.read_file(file_id)


def import_stream(store, path: str, stream: io.IOBase, chunk_size: int = 65536) -> bytes:
    """Import from a stream without full-memory copy where possible."""
    chunks = []
    while True:
        chunk = stream.read(chunk_size)
        if not chunk:
            break
        chunks.append(chunk)
    return store.create_file(path, b"".join(chunks))


def export_stream(store, file_id: bytes, stream: io.IOBase, chunk_size: int = 65536) -> int:
    """Export file content to a stream. Returns total bytes written."""
    content = store.read_file(file_id)
    total = 0
    for i in range(0, len(content), chunk_size):
        chunk = content[i:i + chunk_size]
        stream.write(chunk)
        total += len(chunk)
    return total


def import_multiple(store, files: dict[str, bytes]) -> dict[str, bytes]:
    """Import multiple files. Returns {path: FileId}."""
    result = {}
    for path, content in files.items():
        result[path] = store.create_file(path, content)
    return result


def export_multiple(store, file_ids: list[bytes]) -> dict[bytes, bytes]:
    """Export multiple files. Returns {FileId: content}."""
    return {fid: store.read_file(fid) for fid in file_ids}

