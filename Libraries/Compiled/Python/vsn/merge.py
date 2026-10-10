"""VSN-1 three-way merge (Library capability, not canonical state).

Merge is a Library/workflow operation. Merge metadata is temporary
Library state only; no VSN protocol records are invented for merge.
"""
from __future__ import annotations

from dataclasses import dataclass, field as dc_field


@dataclass
class Conflict:
    """A merge conflict where ours and theirs differ."""
    path: str
    base_content: bytes
    ours_content: bytes
    theirs_content: bytes


@dataclass
class MergeResult:
    """Result of a three-way merge."""
    merged_files: dict = dc_field(default_factory=dict)  # path -> content
    conflicts: list = dc_field(default_factory=list)      # list of Conflict
    added: list = dc_field(default_factory=list)
    deleted: list = dc_field(default_factory=list)

    @property
    def has_conflicts(self) -> bool:
        return len(self.conflicts) > 0


def three_way_merge(
    base_store, ours_store, theirs_store,
) -> MergeResult:
    """Three-way merge of file states.

    base: common ancestor
    ours: our changes
    theirs: their changes

    Non-conflicting changes are auto-merged. Conflicts are reported.
    """
    base_files = {p: fid for fid, p in base_store.list_files() if p}
    ours_files = {p: fid for fid, p in ours_store.list_files() if p}
    theirs_files = {p: fid for fid, p in theirs_store.list_files() if p}

    result = MergeResult()
    all_paths = set(base_files) | set(ours_files) | set(theirs_files)

    for path in sorted(all_paths):
        in_base = path in base_files
        in_ours = path in ours_files
        in_theirs = path in theirs_files

        base_c = base_store.read_file(base_files[path]) if in_base else None
        ours_c = ours_store.read_file(ours_files[path]) if in_ours else None
        theirs_c = theirs_store.read_file(theirs_files[path]) if in_theirs else None

        # Both same → no change
        if ours_c == theirs_c:
            if ours_c is not None:
                result.merged_files[path] = ours_c
            continue

        # Only ours changed
        if ours_c == base_c and theirs_c != base_c:
            if theirs_c is not None:
                result.merged_files[path] = theirs_c
            continue

        # Only theirs changed
        if theirs_c == base_c and ours_c != base_c:
            if ours_c is not None:
                result.merged_files[path] = ours_c
            continue

        # Both changed differently → conflict
        result.conflicts.append(Conflict(
            path=path,
            base_content=base_c or b"",
            ours_content=ours_c or b"",
            theirs_content=theirs_c or b"",
        ))

    return result


def resolve_conflict(merge_result: MergeResult, path: str, content: bytes) -> None:
    """Resolve a conflict by providing final content."""
    merge_result.conflicts = [c for c in merge_result.conflicts if c.path != path]
    merge_result.merged_files[path] = content
