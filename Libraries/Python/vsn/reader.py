"""VSN reader: streaming decode of primitives and framing.

A Cursor tracks a byte position so all reads are bounds-checked and
distinguish truncation (physical end reached) from malformed data.
"""
from __future__ import annotations

from .primitives import PrimitiveError


class Truncated(Exception):
    """Physical end-of-data reached mid-unit (GR-47)."""


class Cursor:
    __slots__ = ("data", "pos")

    def __init__(self, data: bytes | bytearray | memoryview, pos: int = 0):
        self.data = data
        self.pos = pos

    def remaining(self) -> int:
        return len(self.data) - self.pos

    def _need(self, n: int):
        if self.remaining() < n:
            raise Truncated("need %d bytes, %d remain" % (n, self.remaining()))

    def read(self, n: int) -> bytes:
        self._need(n)
        out = bytes(self.data[self.pos:self.pos + n])
        self.pos += n
        return out

    def read_u16(self) -> int:
        return int.from_bytes(self.read(2), "big")

    def read_u32(self) -> int:
        return int.from_bytes(self.read(4), "big")

    def read_u64(self) -> int:
        return int.from_bytes(self.read(8), "big")

    def read_uvarint(self) -> int:
        value = 0
        shift = 0
        for idx in range(10):
            b = self.read(1)[0]
            if idx == 9:
                # 10th byte: high bit MUST be clear and, for a minimal
                # 10-byte encoding, its single value bit MUST be set (0x01);
                # 0x00 would be non-minimal and >0x01 overflows (GR-21).
                if b == 0x01:
                    return value | (1 << 63)
                raise PrimitiveError("uvarint 10th byte invalid")
            value |= (b & 0x7F) << shift
            if not (b & 0x80):
                self._check_minimal(b, shift)
                return value
            shift += 7
        raise PrimitiveError("uvarint exceeds 10 bytes")

    def _check_minimal(self, last_byte: int, shift: int):
        # GR-24: the most significant group MUST be non-zero; a trailing
        # zero group means a shorter canonical encoding exists.
        if last_byte == 0 and shift > 0:
            raise PrimitiveError("non-minimal uvarint")

