"""VSN crash recovery (marker-based, RC-01..RC-45).

Sequential scan is normative; only marker-covered canonical data is
accepted. Incomplete tails are tolerated; malformed later data is not.
"""
from __future__ import annotations

from dataclasses import dataclass

from . import constants as C
from . import container as _container
from .errors import VsnError
from .reader import Cursor, Truncated


@dataclass
class RecoveryResult:
    accepted_generation: int
    recovered: bool
    tail_present: bool
    status: str
    message: str = ""


def recover(data: bytes) -> RecoveryResult:
    """Locate the effective CommitMarker and return the accepted generation.

    The effective marker is the highest-Generation structurally complete,
    semantically valid CommitMarker. A truncated/incomplete tail after the
    marker is tolerated (RC-13); malformed trailing bytes are not (GR-48).
    """
    try:
        parsed = _container.parse(data)
    except Truncated:
        return RecoveryResult(0, False, True, "TRUNCATED",
                              "physical end reached mid-unit")
    except VsnError as e:
        return RecoveryResult(0, False, False, "MALFORMED", str(e))

    markers = []
    for rec in parsed.records:
        if rec.rtype == C.REC_COMMIT_MARKER:
            g = rec.field(C.FID_COMMIT_GENERATION)
            if g is not None:
                markers.append(g.value_uvarint)

    if not markers:
        return RecoveryResult(0, False, False, "NO_MARKER",
                              "no CommitMarker present")

    gen = max(markers)
    tail = parsed.trailer_generation != gen if parsed.trailer_generation else False
    return RecoveryResult(gen, True, tail, "RECOVERED",
                          "accepted generation %d" % gen)

