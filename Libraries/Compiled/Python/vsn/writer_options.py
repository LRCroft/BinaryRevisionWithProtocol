"""VSN WriterOptions and OptimizationConfiguration (Library Storage Policy API Contract).

This module provides the optional writer-side configuration model defined by the
frozen VSN1_Library_Storage_Policy_API_Contract.md. All values are writer-local
configuration -- none appear in the serialized container binary.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from .constants import StoragePolicy, WireMode, STORAGE_POLICY_TO_WIRE_MODE
from .errors import (
    InvalidStoragePolicy,
    PolicyWireModeConflict,
    InvalidOptimizationConfiguration,
)


@dataclass(frozen=True)
class OptimizationConfiguration:
    """Resource-budget parameters for StoragePolicy implementation.

    All fields are optional; omitting a field means "use the implementation's
    native default". No numeric defaults are prescribed by the frozen contract --
    they remain implementation-defined so each language can choose sensible
    platform-native values.

    Hard limits (validate=True) vs preferences (validate=False):
      search_budget          -- hard limit  (must be > 0 if present)
      memory_limit           -- hard limit  (must be > 0 if present)
      max_dependency_depth   -- hard limit  (must be >= 1 if present)
      max_extent_count       -- preference  (>= 1, no error on 0/None)
      decode_work_limit      -- hard limit  (> 0 or None means unlimited)
      min_savings_bytes      -- preference  (>= 0, 0 means "any saving")
      candidate_size         -- preference  (>= 1 if present)
    """

    search_budget: Optional[int] = None
    memory_limit: Optional[int] = None
    max_dependency_depth: Optional[int] = None
    max_extent_count: Optional[int] = None
    decode_work_limit: Optional[int] = None
    min_savings_bytes: Optional[int] = None
    candidate_size: Optional[int] = None
    search_configuration: Optional[SearchConfiguration] = None

    def validate(self) -> None:
        if self.search_budget is not None and self.search_budget <= 0:
            raise InvalidOptimizationConfiguration("search_budget", self.search_budget)
        if self.memory_limit is not None and self.memory_limit <= 0:
            raise InvalidOptimizationConfiguration("memory_limit", self.memory_limit)
        if self.max_dependency_depth is not None and self.max_dependency_depth < 1:
            raise InvalidOptimizationConfiguration("max_dependency_depth", self.max_dependency_depth)


@dataclass(frozen=True)
class SearchConfiguration:
    """Optional nested component for deeper candidate search.

    Per the API contract, this is a distinct configuration component rather
    than just another field inside OptimizationConfiguration.
    """

    breadth_first: bool = False
    max_branching_factor: int = 32
    timeout_ms: Optional[int] = None

    def validate(self) -> None:
        if self.max_branching_factor < 1:
            raise InvalidOptimizationConfiguration("max_branching_factor", self.max_branching_factor)


class WriterOptions:
    """Composition model for writer-side options per the Library API Contract.

    Fields are optional; absent fields preserve legacy behaviour:
      - storage_policy is None  ->  no policy preference (legacy default)
      - wire_mode_constraint   ->  uses existing VsnStore(mode) default

    Backward-compatibility guarantee:
        WriterOptions()  ==  WriterOptions(storage_policy=None, wire_mode_constraint=None)
        which preserves the existing unoptimised writer path.
    """

    __slots__ = ("storage_policy", "wire_mode_constraint", "optimization_configuration")

    def __init__(
        self,
        storage_policy: Optional[StoragePolicy] = None,
        wire_mode_constraint: Optional[int] = None,
        optimization_configuration: Optional[OptimizationConfiguration] = None,
    ) -> None:
        self.storage_policy = storage_policy
        self.wire_mode_constraint = wire_mode_constraint
        self.optimization_configuration = optimization_configuration

    @property
    def effective_wire_mode(self) -> Optional[int]:
        """Resolve the effective wire mode from policy + explicit constraint.

        Eight explicitly defined conflict cases (from the API contract):
            1. storage_policy=None,     constraint=None   -> None (unspecified)
            2. storage_policy=HV,       constraint=None   -> MODERN (0x01)
            3. storage_policy=VERT,     constraint=None   -> MODERN (0x01)
            4. storage_policy=HORI,     constraint=None   -> ENTERPRISE (0x02)
            5. storage_policy=HHOR,     constraint=None   -> ENTERPRISE (0x02)
            6. storage_policy=None,     constraint=MODERN -> MODERN (0x01)
            7. storage_policy=None,     constraint=ENTERPRISE -> ENTERPRISE (0x02)
            8a. policy HV/VERT + constraint=ENTERPRISE   -> REJECT (incompatible)
            8b. policy HORIZ/HHOR + constraint=MODERN    -> REJECT (incompatible)
        """
        policy = self.storage_policy
        constraint = self.wire_mode_constraint

        if policy is None and constraint is None:
            return None  # case 1 -- unspecified, caller sets mode directly

        if policy is not None and constraint is not None:
            expected = STORAGE_POLICY_TO_WIRE_MODE[policy]
            if constraint != expected:
                raise PolicyWireModeConflict(policy, constraint)
            return expected  # consistent pair

        if policy is not None:
            return STORAGE_POLICY_TO_WIRE_MODE[policy]  # cases 2-5

        return constraint  # case 6-7

    def resolve_wire_mode(self, default_mode: int) -> int:
        """Return the wire mode to use when constructing a VsnStore."""
        effective = self.effective_wire_mode
        if effective is not None:
            return effective
        return default_mode

    def validate(self) -> None:
        if self.storage_policy is not None and (
            self.storage_policy < StoragePolicy.HIGHLY_VERTICAL
            or self.storage_policy > StoragePolicy.HIGHLY_HORIZONTAL
        ):
            raise InvalidStoragePolicy(self.storage_policy)
        if self.optimization_configuration is not None:
            self.optimization_configuration.validate()
