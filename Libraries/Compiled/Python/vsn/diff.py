"""VSN library-level diff (derived, never canonical).

Compares logical content between containers/revisions/files.
Diff output is derived data and is never a canonical recovery dependency.
"""
from __future__ import annotations

from dataclasses import dataclass, field as dc_field


@dataclass(frozen=True)
class ObjectDiff:
    shared: tuple
    added: tuple
    removed: tuple


@dataclass
class FileDiff:
    """Diff between two file states."""
    added: list = dc_field(default_factory=list)      # paths only in right
    deleted: list = dc_field(default_factory=list)     # paths only in left
    modified: list = dc_field(default_factory=list)    # paths in both, content differs
    unchanged: list = dc_field(default_factory=list)   # paths in both, content same
    renamed: list = dc_field(default_factory=list)     # (old_path, new_path) pairs


def diff_objects(left_serials: set, right_serials: set) -> ObjectDiff:
    return ObjectDiff(
        shared=tuple(sorted(left_serials & right_serials)),
        added=tuple(sorted(right_serials - left_serials)),
        removed=tuple(sorted(left_serials - right_serials)),
    )


def diff_files(left_store, right_store) -> FileDiff:
    """Diff files between two VsnStores by path and content."""
    left_files = {path: fid for fid, path in left_store.list_files() if path}
    right_files = {path: fid for fid, path in right_store.list_files() if path}
    result = FileDiff()
    all_paths = set(left_files.keys()) | set(right_files.keys())
    for path in sorted(all_paths):
        in_left = path in left_files
        in_right = path in right_files
        if in_left and not in_right:
            result.deleted.append(path)
        elif in_right and not in_left:
            result.added.append(path)
        else:
            left_content = left_store.read_file(left_files[path])
            right_content = right_store.read_file(right_files[path])
            if left_content == right_content:
                result.unchanged.append(path)
            else:
                result.modified.append(path)
    return result


def diff_revisions(store, file_id: bytes, rev_a: int, rev_b: int) -> dict:
    """Diff content between two revisions of the same file."""
    content_a = store.checkout_revision(file_id, rev_a)
    content_b = store.checkout_revision(file_id, rev_b)
    return {
        "revision_a": rev_a,
        "revision_b": rev_b,
        "content_a": content_a,
        "content_b": content_b,
        "changed": content_a != content_b,
        "added_bytes": len(content_b) - len(content_a) if content_a != content_b else 0,
    }


def content_equal(a: bytes, b: bytes) -> bool:
    return a == b


