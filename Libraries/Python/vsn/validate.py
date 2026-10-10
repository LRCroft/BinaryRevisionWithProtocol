"""VSN recovery (RC-01..RC-45) and validation layers.

Recovery is marker-based: the accepted state is the canonical data
preceding the highest-Generation structurally complete and semantically
valid CommitMarker. No index, cache, checkpoint, or heuristic substitutes.
"""
from __future__ import annotations

from . import constants as C
from . import container as _container
from .errors import VsnError
from .reader import Truncated


def validate_structural(data: bytes) -> None:
    """Structural validation: magic, versions, framing, lengths, ordering."""
    _container.parse(data)


def validate_semantic(data: bytes) -> None:
    """Semantic validation: identity, references, graph, presence, mode."""
    parsed = _container.parse(data)
    _check_mode(parsed)
    _check_identities(parsed)
    _check_references(parsed)


def _check_mode(parsed):
    # Accept either ModeDeclaration (legacy reader) or REC_STORAGE_POLICY (canonical writer)
    modes = [r for r in parsed.records if r.rtype == C.REC_MODE_DECLARATION]
    sp_records = [r for r in parsed.records if r.rtype == C.REC_STORAGE_POLICY]
    
    if len(sp_records) >= 1:
        # Canonical path: use REC_STORAGE_POLICY to derive mode
        sp_val = None
        for sp_rec in sp_records:
            sp_field = sp_rec.field(C.FID_STORAGE_POLICY)
            if sp_field and len(sp_field.value) == 1:
                sp_val = sp_field.value[0]
                break
        if sp_val is None:
            raise VsnError(0x000C, "REC_STORAGE_POLICY missing storage_policy value")
        # Determine wire mode from storage policy
        if sp_val not in (1, 2, 3, 4):
            raise VsnError(0x0001, "invalid storage policy %d" % sp_val)
        # GR-43: HORIZONTAL policies (3,4) must not use EXTENTS-1 reconstruction
        mode_to_check = C.MODE_ENTERPRISE if sp_val in (3, 4) else C.MODE_MODERN
    elif len(modes) == 1:
        mode_to_check = modes[0].field(C.FID_MODE).value[0] if modes[0].field(C.FID_MODE) and len(modes[0].field(C.FID_MODE).value) == 1 else None
        if mode_to_check is None:
            raise VsnError(0x000C, "ModeDeclaration missing mode value")
    else:
        raise VsnError(0x000C, "expected exactly one ModeDeclaration or REC_STORAGE_POLICY")
    
    if mode_to_check not in (C.MODE_MODERN, C.MODE_ENTERPRISE):
        raise VsnError(0x0001, "reserved mode value 0x%02x" % mode_to_check)
    # GR-43: ENTERPRISE must not use EXTENTS-1 reconstruction
    if mode_to_check == C.MODE_ENTERPRISE:
        for obj in parsed.objects:
            from .representations import parse_object_header
            ident, ver, _ = parse_object_header(obj.descriptor)
            if ident == C.REP_EXTENTS_1:
                raise VsnError(0x000C, "ENTERPRISE mode forbids EXTENTS-1 (GR-43)")


def _check_identities(parsed):
    seen_file = set()
    seen_rev = set()
    seen_obj = set()
    for rec in parsed.records:
        if rec.rtype == C.REC_FILE_IDENTITY:
            f = rec.field(C.FID_FILE_ID)
            fid = f.value if f else None
            if fid in seen_file:
                raise VsnError(0x000A, "duplicate FileIdentity")
            seen_file.add(fid)
        elif rec.rtype == C.REC_REVISION:
            rid = rec.field(C.FID_REV_ID).value_uvarint
            if rid in seen_rev:
                raise VsnError(0x000A, "duplicate RevisionId %d" % rid)
            seen_rev.add(rid)
        elif rec.rtype == C.REC_CONTENT_OBJECT:
            sid = rec.field(C.FID_OBJECT_SERIAL).value_uvarint
            if sid in seen_obj:
                raise VsnError(0x000A, "duplicate ObjectSerial %d" % sid)
            seen_obj.add(sid)


def _check_references(parsed):
    file_ids = {r.field(C.FID_FILE_ID).value for r in parsed.records
                if r.rtype == C.REC_FILE_IDENTITY and r.field(C.FID_FILE_ID)}
    obj_ids = {o.serial for o in parsed.objects}
    rev_ids = {r.field(C.FID_REV_ID).value_uvarint for r in parsed.records
               if r.rtype == C.REC_REVISION and r.field(C.FID_REV_ID)}
    for rec in parsed.records:
        if rec.rtype == C.REC_REVISION:
            f = rec.field(C.FID_REV_FILE_ID)
            if f is None or f.value not in file_ids:
                raise VsnError(0x0009, "Revision references missing FileId")
            obj = rec.field(C.FID_REV_OBJECT_SERIAL)
            if obj is not None and obj.value_uvarint not in obj_ids:
                raise VsnError(0x0008, "Revision references missing ObjectSerial")
        elif rec.rtype == C.REC_FILE_HEAD:
            f = rec.field(C.FID_HEAD_FILE_ID)
            if f is None or f.value not in file_ids:
                raise VsnError(0x0009, "FileHead references missing FileId")
            r = rec.field(C.FID_HEAD_REV_ID)
            if r is None or r.value_uvarint not in rev_ids:
                raise VsnError(0x0009, "FileHead references missing RevisionId")


def validate_content(data: bytes) -> None:
    """Content: dependency validation plus dependency cycle detection.

    Every object must materialize. A dependency cycle, a COPY from a missing
    ObjectSerial, or an unsupported representation identity is detected here.

    This introduces NO new protocol error identifier: materialization already
    raises MISSING_OBJECT (0x0008), INVALID_CANONICAL_STATE (0x000C) for a
    cycle or a bad COPY range, and UNSUPPORTED_REPRESENTATION (0x0006).

    DR-6 additionally requires that when 0x0511 is PRESENT, the materialized
    output length MUST equal it; a mismatch is invalid canonical state (0x000C,
    matching frozen vector EXT-12). Absence of 0x0511 stays fully valid (SR-27).

    Derived storage is never consulted; the check reads canonical VSN state
    only, so it cannot become an authority for anything.
    """
    from .container import parse as _parse
    from .store import VsnStore

    parsed = _parse(data)
    declared = {}
    for rec in parsed.records:
        if rec.rtype == C.REC_CONTENT_OBJECT:
            serial_f = rec.field(C.FID_OBJECT_SERIAL)
            size_f = rec.field(C.FID_OBJECT_SIZE)
            if serial_f is not None and size_f is not None:
                declared[serial_f.value_uvarint] = size_f.value_uvarint

    container = VsnStore.open(data)
    for serial in container.list_objects():
        content = container.materialize(serial)
        if serial in declared and declared[serial] != len(content):
            raise VsnError(
                0x000C,
                "declared size %d does not match materialized length %d for "
                "ObjectSerial %d (DR-6)"
                % (declared[serial], len(content), serial),
            )


def validate(data: bytes, level: str = "Full") -> None:
    """Run validation at a requested depth."""
    levels = {"Structural", "Semantic", "Recovery", "Content", "Full"}
    if level not in levels:
        raise ValueError("unknown validation level %r" % level)
    if level in ("Structural", "Full"):
        validate_structural(data)
    if level in ("Semantic", "Full"):
        validate_semantic(data)
    if level in ("Recovery", "Full"):
        from .recovery import recover
        recover(data)
    if level in ("Content", "Full"):
        validate_content(data)

