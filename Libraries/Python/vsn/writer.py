"""VSN-1 canonical writer (encoder).

Produces canonical VSN-1 bytes. Only frozen record types, field IDs, and
representations are emitted. Identity is never derived from hash or offset.
"""
from __future__ import annotations

from . import constants as C
from .primitives import MAGIC, put_u16, put_uvarint


def _field(fid: int, value: bytes) -> bytes:
    return put_u16(fid) + put_uvarint(len(value)) + value


def _record(rtype: int, fields: list) -> bytes:
    payload = b"".join(_field(f, v) for f, v in fields)
    return put_u16(rtype) + put_uvarint(len(payload)) + payload


def encode(mode: int, records: list, objects: list, generation: int) -> bytes:
    """Encode a canonical container.

    records: list of (record_type, [(field_id, value_bytes), ...])
    objects: list of (object_serial, descriptor_bytes)
    """
    out = bytearray(MAGIC)
    out += put_u16(1)          # ContainerFormatVersion
    out += put_u16(1)          # EncodingVersion
    out += _field(C.FID_RECORDS_END, b"")  # RecordsEnd header marker

    for rtype, fields in records:
        out += _record(rtype, fields)
    out += put_u16(C.REC_END_OF_RECORDS)   # end-of-records marker

    for serial, descriptor in objects:
        out += put_uvarint(serial)
        out += put_uvarint(len(descriptor))
        out += descriptor
    out += put_uvarint(0)      # end-of-objects marker

    # GR-13: canonical record count includes all non-end-of-records records
    canonical_count = len(records)
    out += put_uvarint(canonical_count)
    out += put_uvarint(generation)     # accepting generation
    return bytes(out)


def direct1_descriptor(content: bytes) -> bytes:
    """DR-0 header (DIRECT-1 v1) + raw logical content."""
    return put_u16(C.REP_DIRECT_1) + put_uvarint(C.REP_VERSION_1) + content
