"""Tests for transactions, ENTERPRISE mode, import/export."""
import io
import unittest
import vsn
from vsn import VsnStore, Transaction, VsnError
from vsn import constants as C
from vsn import io_ops


class TransactionTests(unittest.TestCase):
    def test_transaction_commit(self):
        store = VsnStore.create()
        tx = Transaction()
        tx.stage_create("file.txt", b"content")
        data = tx.commit(store)
        self.assertIsInstance(data, bytes)
        fid = store.get_file_id("file.txt")
        self.assertEqual(store.read_file(fid), b"content")
        store.close()

    def test_transaction_rollback(self):
        tx = Transaction()
        tx.stage_create("file.txt", b"content")
        tx.rollback()
        self.assertEqual(len(tx.staged), 0)

    def test_transaction_update_delete(self):
        store = VsnStore.create()
        fid = store.create_file("test.txt", b"old")
        store.commit()
        tx = Transaction()
        tx.stage_update(fid, b"new")
        tx.commit(store)
        self.assertEqual(store.read_file(fid), b"new")
        tx2 = Transaction()
        tx2.stage_delete(fid)
        tx2.commit(store)
        self.assertFalse(store.file_exists(fid))
        store.close()

    def test_commit_reopen_recover(self):
        store = VsnStore.create()
        fid = store.create_file("test.txt", b"hello")
        data = store.commit()
        store.close()
        store2 = VsnStore.open(data)
        from vsn.recovery import recover
        rr = recover(data)
        self.assertEqual(rr.status, "RECOVERED")
        self.assertEqual(store2.read_file(fid), b"hello")
        store2.close()

    def test_expected_revision_id_not_persisted(self):
        store = VsnStore.create()
        tx = Transaction(expected_revision_id=999)
        tx.stage_create("f.txt", b"x")
        tx.commit(store)
        data = store._data
        parsed = vsn.container.parse(data)
        for rec in parsed.records:
            for f in rec.fields:
                self.assertNotEqual(f.fid, 0x9999)
        store.close()

    def test_expected_revision_id_success(self):
        """ExpectedRevisionId precondition succeeds when revision matches."""
        store = VsnStore.create()
        fid = store.create_file("test.txt", b"v1")
        store.commit()
        current_rev = store.get_current_revision(fid)
        tx = Transaction(expected_revision_id=current_rev)
        tx.stage_update(fid, b"v2")
        tx.commit(store)
        self.assertEqual(store.read_file(fid), b"v2")
        store.close()

    def test_expected_revision_id_failure(self):
        """ExpectedRevisionId precondition fails when revision mismatches."""
        store = VsnStore.create()
        fid = store.create_file("test.txt", b"v1")
        store.commit()
        tx = Transaction(expected_revision_id=9999)  # Wrong revision
        tx.stage_update(fid, b"v2")
        with self.assertRaises(VsnError) as cm:
            tx.commit(store)
        self.assertEqual(cm.exception.code, 0x000D)
        self.assertIn("ExpectedRevisionId mismatch", str(cm.exception))
        store.close()


class EnterpriseModeTests(unittest.TestCase):
    def test_enterprise_direct1(self):
        store = VsnStore.create(mode=C.MODE_ENTERPRISE)
        fid = store.create_file("test.txt", b"enterprise content")
        data = store.commit()
        store2 = VsnStore.open(data)
        self.assertEqual(store2.mode, C.MODE_ENTERPRISE)
        self.assertEqual(store2.read_file(fid), b"enterprise content")
        store.close()
        store2.close()

    def test_enterprise_arbitrary_binary(self):
        store = VsnStore.create(mode=C.MODE_ENTERPRISE)
        content = bytes(range(256))
        fid = store.create_file("bin.dat", content)
        data = store.commit()
        store2 = VsnStore.open(data)
        self.assertEqual(store2.read_file(fid), content)
        store.close()
        store2.close()

    def test_enterprise_empty_and_nul(self):
        store = VsnStore.create(mode=C.MODE_ENTERPRISE)
        fid1 = store.create_file("empty.txt", b"")
        fid2 = store.create_file("nul.bin", b"\x00\x01\x00\x02\x00")
        data = store.commit()
        store2 = VsnStore.open(data)
        self.assertEqual(store2.read_file(fid1), b"")
        self.assertEqual(store2.read_file(fid2), b"\x00\x01\x00\x02\x00")
        store.close()
        store2.close()

    def test_enterprise_roundtrip(self):
        store = VsnStore.create(mode=C.MODE_ENTERPRISE)
        fid = store.create_file("rt.txt", b"round trip")
        d1 = store.commit()
        store2 = VsnStore.open(d1)
        d2 = store2.to_bytes()
        store3 = VsnStore.open(d2)
        self.assertEqual(store3.read_file(fid), b"round trip")
        store.close()
        store2.close()
        store3.close()


class ImportExportTests(unittest.TestCase):
    def test_import_export_bytes(self):
        store = VsnStore.create()
        fid = io_ops.import_bytes(store, "imp.txt", b"imported")
        self.assertEqual(io_ops.export_bytes(store, fid), b"imported")
        store.close()

    def test_import_export_stream(self):
        store = VsnStore.create()
        stream = io.BytesIO(b"stream content")
        fid = io_ops.import_stream(store, "stream.txt", stream)
        out = io.BytesIO()
        n = io_ops.export_stream(store, fid, out)
        self.assertEqual(n, 14)
        self.assertEqual(out.getvalue(), b"stream content")
        store.close()

    def test_binary_preservation(self):
        store = VsnStore.create()
        content = bytes(range(256))
        fid = io_ops.import_bytes(store, "bin.dat", content)
        self.assertEqual(io_ops.export_bytes(store, fid), content)
        store.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
