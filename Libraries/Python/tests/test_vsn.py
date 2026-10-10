"""VSN Python conformance tests.

Runs against the frozen byte vectors and golden expectations. No vector
byte is generated here; every expected value is asserted against the
authoritative frozen vectors in ../TestVectors.
"""
import hashlib
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import vsn
from vsn.errors import VsnError, ResourceRefusal
from vsn.recovery import recover
from vsn.validate import validate

TV = os.path.join(os.path.dirname(__file__), "..", "..", "TestVectors")


def _load(name):
    with open(os.path.join(TV, name + ".vsn"), "rb") as f:
        return f.read()


class FrozenVectorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(TV, "manifest.json")) as f:
            cls.manifest = json.load(f)

    def test_manifest_hashes(self):
        for m in self.manifest["vectors"]:
            data = _load(m["name"])
            self.assertEqual(hashlib.sha256(data).hexdigest(), m["sha256"])
            self.assertEqual(len(data), m["bytes"])

    def test_direct01_empty(self):
        c = vsn.open(_load("DIRECT-01"))
        self.assertEqual(c.mode, vsn.constants.MODE_MODERN)
        self.assertEqual(recover(_load("DIRECT-01")).accepted_generation, 1)
        validate(_load("DIRECT-01"), "Full")
        self.assertEqual(c.materialize(42), b"")

    def test_direct02_all_bytes(self):
        c = vsn.open(_load("DIRECT-02"))
        out = c.materialize(7)
        self.assertEqual(len(out), 256)
        self.assertEqual(out, bytes(range(256)))

    def test_direct03_embedded_nul(self):
        c = vsn.open(_load("DIRECT-03"))
        self.assertEqual(c.materialize(9), b"\x41\x00\x42\xff")

    def test_ext01_literal(self):
        c = vsn.open(_load("EXT-01"))
        self.assertEqual(c.materialize(20), b"alpha")

    def test_ext02_copy_plus_literal(self):
        c = vsn.open(_load("EXT-02-and-EXT-03"))
        self.assertEqual(c.materialize(10), b"hello vsn\n")
        self.assertEqual(c.materialize(20), b"hello vsn\n!!")

    def test_fileidentity_field_id_is_0x0101(self):
        """Normative field allocation: FileIdentity.FileId = 0x0101 (not 0x0001)."""
        from vsn import constants as C
        self.assertEqual(C.REC_FILE_IDENTITY, 0x0001)
        self.assertEqual(C.FID_FILE_ID, 0x0101)
        # Verify against every frozen vector
        for name in ["DIRECT-01", "DIRECT-02", "DIRECT-03", "EXT-01", "EXT-02-and-EXT-03"]:
            parsed = vsn.container.parse(_load(name))
            for rec in parsed.records:
                if rec.rtype == C.REC_FILE_IDENTITY:
                    f = rec.field(C.FID_FILE_ID)
                    self.assertIsNotNone(f, f"{name}: FileIdentity must have field 0x0101")
                    self.assertEqual(len(f.value), 16)

    def test_0x0001_not_treated_as_fileidentity_fileid(self):
        """FieldId 0x0001 in a FileIdentity record is NOT the canonical FileId field."""
        from vsn import constants as C
        # Build a container where FileIdentity uses field 0x0001 (the old bug)
        data = bytearray(b"VSN-\x00\x01\x00\x01")
        data += b"\x00\x00\x00"  # RecordsEnd header
        data += b"\x00\x07\x04\x07\x01\x01\x01"  # ModeDeclaration MODERN
        # FileIdentity record with WRONG field id 0x0001
        data += b"\x00\x01\x13\x00\x01\x10"  # type 0x0001, len 19, field 0x0001, len 16
        data += b"\x01\x23\x45\x67\x89\xab\xcd\xef\x01\x23\x45\x67\x89\xab\xcd\xef"
        data += b"\x00\x00"  # end-of-records
        data += b"\x00"  # end-of-objects
        data += b"\x00\x01"  # trailer
        parsed = vsn.container.parse(bytes(data))
        # The FileIdentity record should NOT have field 0x0101
        for rec in parsed.records:
            if rec.rtype == C.REC_FILE_IDENTITY:
                f = rec.field(C.FID_FILE_ID)  # looks for 0x0101
                self.assertIsNone(f, "0x0001 must not be silently treated as FileId 0x0101")

    def test_trailer_excludes_mode_declaration(self):
        """Trailer canonical record count excludes ModeDeclaration (GR-13)."""
        from vsn import constants as C
        # DIRECT-01: 7 physical records (Mode + 2×FileIdentity + Revision + ContentObject + FileHead + CommitMarker)
        # Canonical records = 6 (all except ModeDeclaration)
        parsed = vsn.container.parse(_load("DIRECT-01"))
        physical_count = len(parsed.records)
        canonical_count = sum(1 for r in parsed.records if r.rtype != C.REC_MODE_DECLARATION)
        self.assertEqual(physical_count, 7)
        self.assertEqual(canonical_count, 6)
        self.assertEqual(parsed.trailer_record_count, 6)
        self.assertEqual(parsed.trailer_record_count, canonical_count)

        # EXT-01: 8 physical records (adds RepresentationDescriptor)
        parsed = vsn.container.parse(_load("EXT-01"))
        physical_count = len(parsed.records)
        canonical_count = sum(1 for r in parsed.records if r.rtype != C.REC_MODE_DECLARATION)
        self.assertEqual(physical_count, 8)
        self.assertEqual(canonical_count, 7)
        self.assertEqual(parsed.trailer_record_count, 7)

        # EXT-02/03: 9 physical records
        parsed = vsn.container.parse(_load("EXT-02-and-EXT-03"))
        physical_count = len(parsed.records)
        canonical_count = sum(1 for r in parsed.records if r.rtype != C.REC_MODE_DECLARATION)
        self.assertEqual(physical_count, 9)
        self.assertEqual(canonical_count, 8)
        self.assertEqual(parsed.trailer_record_count, 8)


class NegativeTests(unittest.TestCase):
    def test_bad_magic(self):
        with self.assertRaises(VsnError):
            vsn.open(b"XXXX" + b"\x00" * 100)

    def test_bad_container_version(self):
        with self.assertRaises(VsnError):
            vsn.open(b"VSN-\x00\x02\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00")

    def test_non_minimal_uvarint(self):
        from vsn.primitives import PrimitiveError
        from vsn.reader import Cursor
        # 81 00 encodes 1 non-minimally in a length position
        data = b"VSN-\x00\x01\x00\x01"  # magic + versions
        data += b"\x00\x00\x00"  # RecordsEnd header
        data += b"\x00\x01" + b"\x81\x00"  # FileIdentity record, non-minimal length
        with self.assertRaises((PrimitiveError, VsnError)):
            vsn.open(data)

    def test_reserved_mode(self):
        # Mode 0x03 is reserved (VR-16)
        data = bytearray(b"VSN-\x00\x01\x00\x01")
        data += b"\x00\x00\x00"  # RecordsEnd header
        data += b"\x00\x07\x04\x07\x01\x01\x03"  # ModeDeclaration mode=3
        data += b"\x00\x00"  # end-of-records
        data += b"\x00"  # end-of-objects
        data += b"\x00\x00"  # trailer
        with self.assertRaises(VsnError):
            validate(bytes(data), "Semantic")

    def test_truncated_recovery(self):
        data = _load("DIRECT-01")
        rr = recover(data[:-5])
        self.assertEqual(rr.status, "TRUNCATED")


class PrimitiveTests(unittest.TestCase):
    def test_uvarint_roundtrip(self):
        from vsn.primitives import put_uvarint
        from vsn.reader import Cursor
        for v in [0, 1, 127, 128, 16383, 16384, 2**64 - 1]:
            self.assertEqual(Cursor(put_uvarint(v)).read_uvarint(), v)

    def test_uvarint_rejects_nonminimal(self):
        from vsn.reader import Cursor
        from vsn.primitives import PrimitiveError
        with self.assertRaises(PrimitiveError):
            Cursor(b"\x81\x00").read_uvarint()


class WriterTests(unittest.TestCase):
    def test_writer_trailer_excludes_mode(self):
        """Writer emits canonical record count excluding ModeDeclaration (GR-13)."""
        from vsn.builder import ContainerBuilder
        from vsn import constants as C
        b = ContainerBuilder(mode=C.MODE_MODERN)
        fid = b"\x01" * 16
        b.add_file(fid)
        serial = b.add_object(b"hello")
        b.add_revision(fid, 1, serial, "test.txt")
        b.set_head(fid, 1)
        data = b.build(generation=1)
        parsed = vsn.container.parse(data)
        # 5 physical records: Mode + FileIdentity + Revision + ContentObject + FileHead + CommitMarker = 6
        # Wait, let me count: Mode(1) + FileIdentity(1) + Revision(1) + ContentObject(1) + FileHead(1) + CommitMarker(1) = 6
        # Canonical = 6 - 1 (Mode) = 5
        self.assertEqual(len(parsed.records), 6)
        self.assertEqual(parsed.trailer_record_count, 5)

    def test_writer_roundtrip(self):
        """Writer output can be parsed and materialized."""
        from vsn.builder import ContainerBuilder
        from vsn import constants as C
        b = ContainerBuilder(mode=C.MODE_MODERN)
        fid = b"\x01\x23\x45\x67\x89\xab\xcd\xef\x01\x23\x45\x67\x89\xab\xcd\xef"
        b.add_file(fid)
        content = b"test content"
        serial = b.add_object(content)
        b.add_revision(fid, 100, serial, "file.txt")
        b.set_head(fid, 100)
        data = b.build(generation=1)
        # Parse and verify
        c = vsn.open(data)
        self.assertEqual(c.mode, C.MODE_MODERN)
        self.assertEqual(c.materialize(serial), content)
        files = c.files()
        self.assertEqual(len(files), 1)
        self.assertEqual(files[0][0], vsn.model.FileId(fid))

    def test_builder_multiple_files(self):
        """Builder supports multiple files."""
        from vsn.builder import ContainerBuilder
        fid_a = b"\x01" * 16
        fid_b = b"\x02" * 16
        b = ContainerBuilder()
        b.add_file(fid_a).add_file(fid_b)
        serial_a = b.add_object(b"file a")
        serial_b = b.add_object(b"file b")
        b.add_revision(fid_a, 1, serial_a, "a.txt")
        b.add_revision(fid_b, 2, serial_b, "b.txt")
        b.set_head(fid_a, 1).set_head(fid_b, 2)
        data = b.build()
        c = vsn.open(data)
        self.assertEqual(c.materialize(serial_a), b"file a")
        self.assertEqual(c.materialize(serial_b), b"file b")
        self.assertEqual(len(c.files()), 2)


class EnterpriseModeTests(unittest.TestCase):
    def test_enterprise_forbids_extents(self):
        """ENTERPRISE mode validation rejects EXTENTS-1 objects (GR-43)."""
        from vsn import constants as C
        from vsn.writer import encode
        from vsn.primitives import put_u16, put_uvarint
        # Build a container with ENTERPRISE mode but EXTENTS-1 object
        mode_rec = (C.REC_MODE_DECLARATION, [(C.FID_MODE, bytes([C.MODE_ENTERPRISE]))])
        fid = b"\x01" * 16
        file_rec = (C.REC_FILE_IDENTITY, [(C.FID_FILE_ID, fid)])
        # EXTENTS-1 descriptor
        extents_desc = put_u16(C.REP_EXTENTS_1) + put_uvarint(1) + b"\x00"  # minimal
        obj_rec = (C.REC_CONTENT_OBJECT, [(C.FID_OBJECT_SERIAL, put_uvarint(1))])
        rev_rec = (C.REC_REVISION, [
            (C.FID_REV_ID, put_uvarint(1)),
            (C.FID_REV_FILE_ID, fid),
            (C.FID_REV_OBJECT_SERIAL, put_uvarint(1)),
            (C.FID_REV_PRESENCE, bytes([C.PRESENT])),
        ])
        head_rec = (C.REC_FILE_HEAD, [
            (C.FID_HEAD_FILE_ID, fid),
            (C.FID_HEAD_REV_ID, put_uvarint(1)),
        ])
        commit_rec = (C.REC_COMMIT_MARKER, [(C.FID_COMMIT_GENERATION, put_uvarint(1))])
        records = [mode_rec, file_rec, rev_rec, obj_rec, head_rec, commit_rec]
        objects = [(1, extents_desc)]
        data = encode(C.MODE_ENTERPRISE, records, objects, 1)
        with self.assertRaises(VsnError):
            vsn.validate.validate(data, "Semantic")


if __name__ == "__main__":
    unittest.main(verbosity=2)

