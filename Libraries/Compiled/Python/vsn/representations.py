"""VSN representation materialization: DIRECT-1 and EXTENTS-1 (DR-0..DR-12).

An object descriptor payload begins with Representation Identity (u16be)
and Representation Version (uvarint); the remainder is the representation
payload. Materialization must not depend on a RepresentationDescriptor.
"""
from __future__ import annotations

from . import constants as C
from .errors import VsnError
from .reader import Cursor, Truncated


def parse_object_header(descriptor: bytes) -> tuple:
    """Return (identity, version, payload_remainder)."""
    c = Cursor(descriptor)
    ident = c.read_u16()
    ver = c.read_uvarint()
    return ident, ver, descriptor[c.pos:]


def materialize_direct(remainder: bytes) -> bytes:
    return remainder


def _read_uvarint(c: Cursor) -> int:
    return c.read_uvarint()


def materialize_extents(remainder: bytes, resolve) -> bytes:
    """Materialize an EXTENTS-1 operation collection.

    resolve(object_serial) -> bytes returns a dependency object's logical
    content. The graph MUST be finite and acyclic; cycle detection is the
    caller's responsibility via the visited set.
    """
    c = Cursor(remainder)
    op_count = c.read_uvarint()
    out = bytearray()
    for _ in range(op_count):
        out += _materialize_operation(c, resolve, set())
    if c.remaining() != 0:
        raise VsnError(0x000C, "trailing bytes after EXTENTS-1 operations")
    return bytes(out)


def _materialize_operation(c: Cursor, resolve, visited) -> bytes:
    # An operation is a NESTED collection of operands (VR-23, DR-3).
    kind = c.read_uvarint()
    if kind != C.OP_NESTED:
        raise VsnError(0x000C, "operation must be NESTED, got kind %d" % kind)
    n = c.read_uvarint()
    operands = []
    for _ in range(n):
        operands.append(_read_operand(c))
    return _apply_operation(operands, resolve, visited)


def _read_operand(c: Cursor):
    kind = c.read_uvarint()
    if kind == C.OP_LITERAL_BYTES:
        ln = c.read_uvarint()
        return ("lit", c.read(ln))
    if kind == C.OP_OBJECT_SOURCE:
        return ("src", c.read_uvarint())
    if kind == C.OP_NUMERIC:
        return ("num", c.read_uvarint())
    if kind == C.OP_NESTED:
        n = c.read_uvarint()
        return ("nested", [_read_operand(c) for _ in range(n)])
    raise VsnError(0x0006, "unknown operand kind %d" % kind)


def _apply_operation(operands, resolve, visited) -> bytes:
    # COPY(source, offset, length) = [src, num, num]
    # LITERAL(bytes) = [lit, num(0)]  (the reserved NUMERIC 0)
    if not operands:
        raise VsnError(0x000C, "empty operation")
    head = operands[0]
    if head[0] == "src":
        if len(operands) != 3 or operands[1][0] != "num" or operands[2][0] != "num":
            raise VsnError(0x000C, "malformed COPY operation")
        source = head[1]
        off = operands[1][1]
        length = operands[2][1]
        if source in visited:
            raise VsnError(0x000C, "dependency cycle at ObjectSerial %d" % source)
        src_bytes = resolve(source)
        if off < 0 or length < 0 or off + length > len(src_bytes):
            raise VsnError(0x000C, "COPY range out of bounds")
        return src_bytes[off:off + length]
    if head[0] == "lit":
        return head[1]
    raise VsnError(0x000C, "unknown operation head kind %s" % head[0])

