"""Tests for VSN-1 Library capabilities: container lifecycle, file API, revision API."""
import unittest
import vsn
from vsn import VsnStore, Transaction, VsnError
from vsn import constants as C


class StoreObjectApiTests(unittest.TestCase):
    """Store-level Object API: enumerate, inspect, serial, materialize, metadata.

    These exercise VsnStore's object surface directly rather than through
    VsnContainer, so the Object API is covered at the library layer.
    """

    def test_list_objects_enumerates_every_object(self):
        store = VsnStore.create()
        store.create_file("a.txt", b"first")
        store.create_file("b.txt", b"second")
        data = store.commit()
        reopened = VsnStore.open(data)
        serials = reopened.list_objects()
        self.assertEqual(serials, sorted(serials), "serials are ordered")
        self.assertEqual(len(serials), 2, "one object per distinct content")

    def test_get_object_info_reports_metadata(self):
        store = VsnStore.create()
        fid = store.create_file("a.txt", b"payload")
        data = store.commit()
        reopened = VsnStore.open(data)
        serial = reopened.get_object_serial(fid)
        self.assertIsNotNone(serial)
        info = reopened.get_object_info(serial)
        self.assertEqual(info["serial"], serial)
        self.assertEqual(info["length"], len(b"payload"))
        self.assertEqual(info["representation_identity"], C.REP_DIRECT_1)
        self.assertEqual(info["representation_version"], C.REP_VERSION_1)

    def test_get_object_serial_resolves_current_and_named_revision(self):
        store = VsnStore.create()
        fid = store.create_file("a.txt", b"one")
        store.write_file(fid, b"two")
        reopened = VsnStore.open(store.commit())
        head = reopened.get_current_revision(fid)
        self.assertEqual(reopened.get_object_serial(fid), reopened.get_object_serial(fid, head))
        self.assertIsNone(reopened.get_object_serial(fid, 9999))

    def test_materialize_returns_logical_content(self):
        store = VsnStore.create()
        fid = store.create_file("a.bin", b"binary\x00\xff\x01data")
        reopened = VsnStore.open(store.commit())
        serial = reopened.get_object_serial(fid)
        self.assertEqual(reopened.materialize(serial), b"binary\x00\xff\x01data")

    def test_materialize_missing_object_is_rejected(self):
        store = VsnStore.create()
        store.create_file("a.txt", b"x")
        reopened = VsnStore.open(store.commit())
        with self.assertRaises(VsnError):
            reopened.materialize(4242)


class ContainerLifecycleTests(unittest.TestCase):
    def test_create_empty(self):
        store = VsnStore.create()
        self.assertEqual(store.mode, C.MODE_MODERN)
        self.assertEqual(store.generation, 0)
        store.close()

    def test_create_and_commit(self):
        store = VsnStore.create()
        fid = store.create_file("test.txt", b"hello")
        data = store.commit()
        self.assertIsInstance(data, bytes)
        self.assertGreater(len(data), 0)
        store.close()

    def test_open_committed(self):
        store = VsnStore.create()
        fid = store.create_file("test.txt", b"hello")
        data = store.commit()
        store.close()
        store2 = VsnStore.open(data)
        self.assertEqual(store2.read_file(fid), b"hello")
        store2.close()

    def test_reopen_after_commit(self):
        store = VsnStore.create()
        fid = store.create_file("a.txt", b"aaa")
        store.commit()
        store.write_file(fid, b"bbb")
        store.reopen()
        self.assertEqual(store.read_file(fid), b"aaa")

    def test_deterministic_serialization(self):
        store = VsnStore.create()
        store.create_file("x.txt", b"xxx")
        d1 = store.to_bytes()
        store.reopen(d1)
        d2 = store.to_bytes()
        self.assertEqual(len(d1), len(d2))


class FileApiTests(unittest.TestCase):
    def setUp(self):
        self.store = VsnStore.create()

    def tearDown(self):
        self.store.close()

    def test_create_file(self):
        fid = self.store.create_file("hello.txt", b"hello world")
        self.assertEqual(len(fid), 16)
        self.assertTrue(self.store.file_exists(fid))

    def test_read_file(self):
        fid = self.store.create_file("test.txt", b"content")
        self.assertEqual(self.store.read_file(fid), b"content")

    def test_write_file(self):
        fid = self.store.create_file("test.txt", b"old")
        self.store.write_file(fid, b"new")
        self.assertEqual(self.store.read_file(fid), b"new")

    def test_delete_file(self):
        fid = self.store.create_file("test.txt", b"content")
        self.store.delete_file(fid)
        self.assertFalse(self.store.file_exists(fid))

    def test_rename_file(self):
        fid = self.store.create_file("old.txt", b"data")
        self.store.rename_file(fid, "new.txt")
        self.assertEqual(self.store.get_file_id("new.txt"), fid)
        self.assertIsNone(self.store.get_file_id("old.txt"))

    def test_list_files(self):
        self.store.create_file("a.txt", b"a")
        self.store.create_file("b.txt", b"b")
        paths = {p for _, p in self.store.list_files()}
        self.assertEqual(paths, {"a.txt", "b.txt"})

    def test_duplicate_path_rejected(self):
        self.store.create_file("dup.txt", b"a")
        with self.assertRaises(VsnError):
            self.store.create_file("dup.txt", b"b")


class RevisionApiTests(unittest.TestCase):
    def setUp(self):
        self.store = VsnStore.create()
        self.fid = self.store.create_file("test.txt", b"v1")

    def tearDown(self):
        self.store.close()

    def test_list_revisions(self):
        revs = self.store.list_revisions(self.fid)
        self.assertEqual(len(revs), 1)

    def test_checkout_revision(self):
        rid1 = self.store.get_current_revision(self.fid)
        self.store.write_file(self.fid, b"v2")
        rid2 = self.store.get_current_revision(self.fid)
        self.assertEqual(self.store.checkout_revision(self.fid, rid1), b"v1")
        self.assertEqual(self.store.checkout_revision(self.fid, rid2), b"v2")

    def test_restore_revision(self):
        rid1 = self.store.get_current_revision(self.fid)
        self.store.write_file(self.fid, b"v2")
        self.store.restore_revision(self.fid, rid1)
        self.assertEqual(self.store.read_file(self.fid), b"v1")

    def test_multiple_revisions(self):
        self.store.write_file(self.fid, b"v2")
        self.store.write_file(self.fid, b"v3")
        revs = self.store.list_revisions(self.fid)
        self.assertEqual(len(revs), 3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
