"""VSN transaction staging and commit.

CommitMarker is the sole acceptance authority (RC-01). ExpectedRevisionId
is a precondition only and is NEVER persisted as canonical state.
"""
from __future__ import annotations

from dataclasses import dataclass, field as dc_field
from typing import Optional, Callable

from .errors import VsnError


@dataclass
class StagedChange:
    """A single staged change within a transaction."""
    operation: str  # "create", "update", "delete", "rename"
    file_id: Optional[bytes] = None
    path: Optional[str] = None
    content: Optional[bytes] = None
    new_path: Optional[str] = None


@dataclass
class Transaction:
    """Transaction with staging, precondition, and commit.

    ExpectedRevisionId is a precondition that is NEVER persisted.
    """
    expected_revision_id: Optional[int] = None
    staged: list[StagedChange] = dc_field(default_factory=list)
    _committed: bool = False
    _store: object = None  # back-reference to VsnStore

    def stage_create(self, path: str, content: bytes = b"") -> None:
        self.staged.append(StagedChange("create", path=path, content=content))

    def stage_update(self, file_id: bytes, content: bytes) -> None:
        self.staged.append(StagedChange("update", file_id=file_id, content=content))

    def stage_delete(self, file_id: bytes) -> None:
        self.staged.append(StagedChange("delete", file_id=file_id))

    def stage_rename(self, file_id: bytes, new_path: str) -> None:
        self.staged.append(StagedChange("rename", file_id=file_id, new_path=new_path))

    def inspect(self) -> list[dict]:
        return [{"op": c.operation, "file_id": c.file_id,
                 "path": c.path, "new_path": c.new_path}
                for c in self.staged]

    def rollback(self) -> None:
        self.staged.clear()

    def commit(self, store) -> bytes:
        """Apply staged changes and commit. Returns canonical bytes."""
        if self._committed:
            raise VsnError(0x000C, "transaction already committed")
        # Check precondition
        if self.expected_revision_id is not None:
            # ExpectedRevisionId is a precondition only, never persisted
            # Check against the first file being modified (if any)
            for change in self.staged:
                if change.file_id is not None:
                    current_rev = store.get_current_revision(change.file_id)
                    if current_rev != self.expected_revision_id:
                        raise VsnError(
                            0x000D,
                            f"ExpectedRevisionId mismatch: expected {self.expected_revision_id}, got {current_rev}"
                        )
                    break
        # Apply staged changes
        for change in self.staged:
            if change.operation == "create":
                store.create_file(change.path, change.content or b"")
            elif change.operation == "update":
                store.write_file(change.file_id, change.content)
            elif change.operation == "delete":
                store.delete_file(change.file_id)
            elif change.operation == "rename":
                store.rename_file(change.file_id, change.new_path)
        self._committed = True
        return store.commit()


