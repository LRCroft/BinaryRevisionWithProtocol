"""VSN-1 canonical binary primitives (GR-08, GR-21..GR-26).

All multi-byte integers are big-endian. The uvarint is minimal LEB128,
1..10 bytes, 7 payload bits per byte, 10th byte contributes 7 bits.
Non-minimal encodings and overflow are rejected (GR-21, GR-24, GR-25).
"""
from __future__ import annotations

MAGIC = b"VSN-"


class PrimitiveError(ValueError):
    """A primitive encoding violation (malformed container)."""


def _reject(msg: str):
    raise PrimitiveError(msg)


def put_u16(v: int) -> bytes:
    if not 0 <= v <= 0xFFFF:
        _reject("u16 out of range")
    return v.to_bytes(2, "big")


def put_u32(v: int) -> bytes:
    if not 0 <= v <= 0xFFFFFFFF:
        _reject("u32 out of range")
    return v.to_bytes(4, "big")


def put_u64(v: int) -> bytes:
    if not 0 <= v <= 0xFFFFFFFFFFFFFFFF:
        _reject("u64 out of range")
    return v.to_bytes(8, "big")


def put_uvarint(v: int) -> bytes:
    if v < 0:
        _reject("uvarint negative")
    out = bytearray()
    while v >= 0x80:
        out.append((v & 0x7F) | 0x80)
        v >>= 7
    out.append(v)
    if len(out) > 10:
        _reject("uvarint exceeds 10 bytes")
    return bytes(out)


def put_bool(v: bool) -> bytes:
    return b"\x01" if v else b"\x00"


def put_utf8(s: str) -> bytes:
    if "\x00" in s:
        _reject("string contains NUL")
    return s.encode("utf-8")
