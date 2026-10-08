"""VSN-1 container parser: streaming, framing-exact, mode-independent.

Parsing never requires a hash, index, cache, checkpoint, or external data.
Unknown records and fields are skipped by declared length and preserved
for format-preserving rewrite (GR-29..GR-33).
"""
from __future__ import annotations

from . import constants as C
from .errors import VsnError
from .model import Container, Field, ObjectEntry, ObjectSerial, Record
from .primitives import MAGIC, PrimitiveError
from .reader import Cursor, Truncated


def _parse_fields(cursor: Cursor) -> list:
    """Parse a record payload's field stream, validating GR-16 ordering."""
    fields = []
    last = -1
    while cursor.remaining() > 0:
        start = cursor.pos
        fid = cursor.read_u16()
        ln = cursor.read_uvarint()
        val = cursor.read(ln)
        if fid <= last:
            raise VsnError(0x0011, "FieldId %d not strictly ascending" % fid,
                           byte_offset=start)
        last = fid
        fields.append(Field(fid, val))
    return fields


def parse(data: bytes) -> Container:
    cur = Cursor(data)
    if cur.remaining() < 4 or cur.read(4) != MAGIC:
        raise VsnError(0x0001, "bad magic", byte_offset=0)
    cfv = cur.read_u16()
    if cfv != 1:
        raise VsnError(0x0003, "unsupported container format version %d" % cfv)
    ev = cur.read_u16()
    if ev != 1:
        raise VsnError(0x0004, "unsupported encoding version %d" % ev)

    # Header fields until RecordsEnd (FieldId 0x0000)
    while True:
        fid = cur.read_u16()
        ln = cur.read_uvarint()
        if fid == C.FID_RECORDS_END:
            if ln != 0:
                raise VsnError(0x0001, "RecordsEnd length must be 0")
            break
        cur.read(ln)  # header fields are structural; skipped by length

    # Determine which record types contain parseable field streams
    # All records below EXTENSION_MIN have field streams: FileIdentity(1) through RepresentationDescriptor(8)
    # Plus StoragePolicy(9) which is the new canonical on-wire record
    FIELD_RECORD_TYPES = frozenset({0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09})

    records = []
    while True:
        start = cur.pos
        rt = cur.read_u16()
        if rt == C.REC_END_OF_RECORDS:
            break  # bare 2-byte end-of-records marker (GR-10/11)
        rl = cur.read_uvarint()
        payload = cur.read(rl)
        rec = Record(rt, payload, byte_offset=start)
        if rt in FIELD_RECORD_TYPES:
            rec.fields = _parse_fields(Cursor(payload))
        records.append(rec)

    objects = []
    while True:
        start = cur.pos
        serial = cur.read_uvarint()
        if serial == 0:
            break  # end-of-objects marker (GR-37)
        ol = cur.read_uvarint()
        desc = cur.read(ol)
        objects.append(ObjectEntry(ObjectSerial(serial), ol, desc, start))

    trailer_start = cur.pos
    rc = cur.read_uvarint()
    gen = cur.read_uvarint()

    cont = Container(cfv, ev, records, objects, rc, gen, byte_length=len(data))
    has_mode_decl = False
    for rec in records:
        if rec.rtype == C.REC_MODE_DECLARATION:
            m = rec.field(C.FID_MODE)
            if m is not None:
                cont.mode = m.value[0] if m.value else None
                has_mode_decl = True
        if rec.rtype == C.REC_STORAGE_POLICY:
            sp = rec.field(C.FID_STORAGE_POLICY)
            if sp is not None and len(sp.value) >= 1:
                cont.storage_policy = sp.value[0]
    # Derive mode from storage_policy when no ModeDeclaration present (canonical writers)
    if not has_mode_decl and hasattr(cont, 'storage_policy') and cont.storage_policy:
        sp_val = cont.storage_policy
        if sp_val in (1, 2):
            cont.mode = C.MODE_MODERN
        elif sp_val in (3, 4):
            cont.mode = C.MODE_ENTERPRISE
    return cont
