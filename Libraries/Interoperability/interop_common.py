"""Cross-language interoperability support for the VSN Python library.

Provides the four shared interop scenarios (byte-identical with the C# and
TypeScript bindings) plus a language-neutral description of a container's
canonical interpretation.

This module lives OUTSIDE Libraries/Python/ on purpose: it adds no API to the
reference library and changes none of its behaviour.

CLI:
    python interop_common.py write <dir>
    python interop_common.py read  <dir>
"""
from __future__ import annotations

import base64
import json
import sys

from vsn import constants as C
from vsn import container as _container
from vsn import representations as R
from vsn.builder import ContainerBuilder
from vsn.errors import VsnError
from vsn.primitives import put_u16, put_uvarint
from vsn.recovery import recover
from vsn.representations import materialize_direct, materialize_extents, parse_object_header
from vsn.writer import encode, direct1_descriptor

SCENARIOS = ["basic", "extents", "enterprise", "multifile"]


def _fid(byte: int) -> bytes:
    return bytes([byte]) * 16


def _literal_op(content: bytes) -> bytes:
    return (put_uvarint(C.OP_NESTED) + put_uvarint(2)
            + put_uvarint(C.OP_LITERAL_BYTES) + put_uvarint(len(content)) + content
            + put_uvarint(C.OP_NUMERIC) + put_uvarint(0))


def _copy_op(serial: int, offset: int, length: int) -> bytes:
    return (put_uvarint(C.OP_NESTED) + put_uvarint(3)
            + put_uvarint(C.OP_OBJECT_SOURCE) + put_uvarint(serial)
            + put_uvarint(C.OP_NUMERIC) + put_uvarint(offset)
            + put_uvarint(C.OP_NUMERIC) + put_uvarint(length))


def _extents1_descriptor(operations: list[bytes]) -> bytes:
    out = put_u16(C.REP_EXTENTS_1) + put_uvarint(C.REP_VERSION_1)
    out += put_uvarint(len(operations))
    for op in operations:
        out += op
    return out


def add_object_raw(builder: ContainerBuilder, descriptor: bytes, serial: int) -> int:
    """Add a ContentObject record plus an explicit descriptor.

    0x0511 is the LOGICAL content length (SR-29), never representation bytes.
    It is optional (SR-27) and is omitted when the logical length cannot be
    resolved yet (missing dependency, cycle, unsupported representation).
    """
    if serial in builder._object_serials:
        raise ValueError("duplicate ObjectSerial")
    builder._object_serials.add(serial)
    if serial >= builder._next_object_serial:
        builder._next_object_serial = serial + 1
    builder.objects.append((serial, descriptor))
    fields = [(C.FID_OBJECT_SERIAL, put_uvarint(serial))]
    try:
        fields.append((C.FID_OBJECT_SIZE, put_uvarint(len(_logical_content(builder, descriptor)))))
    except VsnError:
        pass  # 0x0511 omitted: fully valid under SR-27
    builder.records.append((C.REC_CONTENT_OBJECT, fields))
    return serial


def _logical_content(builder: ContainerBuilder, descriptor: bytes, visited: set | None = None) -> bytes:
    if visited is None:
        visited = set()
    if descriptor in visited:
        raise VsnError(0x000C, "dependency cycle")
    visited = visited | {descriptor}
    ident, ver, rem = parse_object_header(descriptor)
    if ident == C.REP_DIRECT_1 and ver == C.REP_VERSION_1:
        return materialize_direct(rem)
    if ident == C.REP_EXTENTS_1 and ver == C.REP_VERSION_1:
        def resolve(s: int) -> bytes:
            for serial, desc in builder.objects:
                if serial == s:
                    return _logical_content(builder, desc, visited)
            raise VsnError(0x0008, "missing object %d" % s)
        return materialize_extents(rem, resolve)
    raise VsnError(0x0006, "unsupported representation 0x%04x v%d" % (ident, ver))

def build_scenario(name: str) -> bytes:
    """Build a scenario deterministically; identical bytes across languages."""
    b = ContainerBuilder(C.MODE_MODERN)
    if name == "basic":
        f = _fid(0x01)
        b.add_file(f)
        s = b.add_object(b"hello vsn\n")
        b.add_revision(f, 1, s, "hello.txt")
        b.set_head(f, 1)
        return b.build(1)
    if name == "extents":
        a, c = _fid(0x02), _fid(0x03)
        b.add_file(a)
        b.add_file(c)
        s1 = b.add_object(b"hello vsn\n", 1)
        desc = _extents1_descriptor([_copy_op(1, 0, 10), _literal_op(b"!!")])
        s2 = add_object_raw(b, desc, 2)
        b.add_revision(a, 1, s1, "a.txt")
        b.add_revision(c, 2, s2, "b.txt")
        b.set_head(a, 1)
        b.set_head(c, 2)
        return b.build(2)
    if name == "enterprise":
        f = _fid(0x04)
        e = ContainerBuilder(C.MODE_ENTERPRISE)
        e.add_file(f)
        s = e.add_object(b"enterprise")
        e.add_revision(f, 1, s, "e.txt")
        e.set_head(f, 1)
        return e.build(1)
    # multifile: binary content including NUL and 0xFF
    f1, f2, f3 = _fid(0x05), _fid(0x06), _fid(0x07)
    b.add_file(f1)
    b.add_file(f2)
    b.add_file(f3)
    b.add_object(bytes([0x00, 0x01, 0xFF, 0x00, 0x7F]), 1)
    b.add_object(b"plain text", 2)
    b.add_object(b"", 3)
    b.add_revision(f1, 1, 1, "bin.dat")
    b.add_revision(f2, 2, 2, "text.txt")
    b.add_revision(f3, 3, 3, "empty.txt")
    b.set_head(f1, 1)
    b.set_head(f2, 2)
    b.set_head(f3, 3)
    return b.build(3)


def describe(data: bytes) -> dict:
    """Describe a container's canonical interpretation (language-neutral)."""
    from vsn.api import VsnContainer

    parsed = _container.parse(data)
    c = VsnContainer(data)

    path_by_file: dict[str, str | None] = {}
    rev_by_file: dict[str, int] = {}
    serial_by_rev: dict[int, int | None] = {}

    for rec in parsed.records:
        if rec.rtype == C.REC_REVISION:
            rid_f = rec.field(C.FID_REV_ID)
            fid_f = rec.field(C.FID_REV_FILE_ID)
            if not rid_f or not fid_f:
                continue
            key = fid_f.value.hex()
            p = rec.field(C.FID_REV_PATH)
            if p:
                path_by_file[key] = p.value.decode("utf-8")
            os = rec.field(C.FID_REV_OBJECT_SERIAL)
            serial_by_rev[rid_f.value_uvarint] = os.value_uvarint if os else None
        elif rec.rtype == C.REC_FILE_HEAD:
            fid_f = rec.field(C.FID_HEAD_FILE_ID)
            rid_f = rec.field(C.FID_HEAD_REV_ID)
            if fid_f and rid_f:
                rev_by_file[fid_f.value.hex()] = rid_f.value_uvarint

    files = []
    for rec in parsed.records:
        if rec.rtype != C.REC_FILE_IDENTITY:
            continue
        key = rec.field(C.FID_FILE_ID).value.hex()
        head = rev_by_file.get(key)
        serial = serial_by_rev.get(head) if head is not None else None
        content = b""
        rep_identity = None
        rep_version = None
        if serial is not None:
            entry = next(o for o in parsed.objects if o.serial == serial)
            rep_identity = (entry.descriptor[0] << 8) | entry.descriptor[1]
            _, rep_version, _ = parse_object_header(entry.descriptor)
            content = c.materialize(serial)
        files.append({
            "fileId": key,
            "path": path_by_file.get(key),
            "headRevision": head,
            "objectSerial": serial,
            "repIdentity": rep_identity,
            "repVersion": rep_version,
            "contentBase64": base64.b64encode(content).decode("ascii"),
        })
    files.sort(key=lambda f: f["fileId"])

    rr = recover(data)
    return {
        "mode": parsed.mode,
        "generation": parsed.trailer_generation,
        "recoveryStatus": rr.status,
        "acceptedGeneration": rr.accepted_generation,
        "files": files,
    }


def write_all(root: str) -> list[str]:
    """Write every scenario into {root}/python/."""
    import os
    out = os.path.join(root, "python")
    os.makedirs(out, exist_ok=True)
    for name in SCENARIOS:
        with open(os.path.join(out, name + ".vsn"), "wb") as fh:
            fh.write(build_scenario(name))
    return SCENARIOS


def main(argv: list[str]) -> int:
    """CLI used by the cross-language driver: write <dir> | read <dir>."""
    if len(argv) != 2 or argv[0] not in ("write", "read"):
        print("usage: interop_common.py <write|read> <dir>", file=sys.stderr)
        return 2
    cmd, root = argv
    if cmd == "write":
        write_all(root)
        print(json.dumps({"lang": "python", "wrote": SCENARIOS}))
        return 0

    import os
    results: dict[str, dict] = {}
    for peer in ("python", "csharp", "typescript"):
        for name in SCENARIOS:
            path = os.path.join(root, peer, name + ".vsn")
            if not os.path.exists(path):
                continue
            try:
                expected = json.dumps(describe(build_scenario(name)))
                actual = json.dumps(describe(open(path, "rb").read()))
                results[f"{peer}/{name}"] = {
                    "ok": actual == expected,
                    "status": describe(open(path, "rb").read())["recoveryStatus"],
                }
            except Exception as exc:  # noqa: BLE001 - report, never crash the driver
                results[f"{peer}/{name}"] = {"ok": False, "error": str(exc)}
    print(json.dumps({"lang": "python", "results": results}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

