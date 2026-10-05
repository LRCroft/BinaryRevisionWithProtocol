"""Tests for diagnostics, diff, merge, storage."""
import unittest
import vsn
from vsn import VsnStore, VsnError
from vsn.diagnostics import validate_with_diagnostics, Severity, Category
from vsn.diff import diff_files, diff_revisions
from vsn.merge import three_way_merge, resolve_conflict
from vsn.storage import StorageManager


class DiagnosticsTests(unittest.TestCase):
    def test_validate_clean(self):
        store = VsnStore.create()
        store.create_file("ok.txt", b"ok")
        data = store.commit()
        diags = validate_with_diagnostics(data, "Full")
        self.assertEqual(len(diags), 0)
        store.close()

    def test_validate_bad_magic(self):
        diags = validate_with_diagnostics(b"XXXX" + b"\x00" * 100, "Structural")
        self.assertGreater(len(diags), 0)
        self.assertEqual(diags[0].category, Category.PROTOCOL)

    def test_diagnostic_from_error(self):
        e = VsnError(0x0001, "test error", byte_offset=42)
        d = vsn.diagnostics.Diagnostic.from_vsn_error(e, operation="test")
        self.assertEqual(d.code, 0x0001)
        self.assertEqual(d.byte_offset, 42)
        self.assertEqual(d.severity, Severity.ERROR)


class DiffTests(unittest.TestCase):
    def test_diff_no_changes(self):
        s1 = VsnStore.create()
        s1.create_file("a.txt", b"a")
        s1.commit()
        s2 = VsnStore.open(s1._data)
        d = diff_files(s1, s2)
        self.assertEqual(len(d.modified), 0)
        self.assertEqual(len(d.added), 0)
        s1.close()
        s2.close()

    def test_diff_added(self):
        s1 = VsnStore.create()
        s1.commit()
        s2 = VsnStore.create()
        s2.create_file("new.txt", b"new")
        s2.commit()
        d = diff_files(s1, s2)
        self.assertIn("new.txt", d.added)
        s1.close()
        s2.close()

    def test_diff_modified(self):
        s1 = VsnStore.create()
        fid = s1.create_file("f.txt", b"old")
        s1.commit()
        s2 = VsnStore.open(s1._data)
        s2.write_file(fid, b"new")
        s2.commit()
        d = diff_files(s1, s2)
        self.assertIn("f.txt", d.modified)
        s1.close()
        s2.close()

    def test_diff_revisions(self):
        store = VsnStore.create()
        fid = store.create_file("f.txt", b"v1")
        rid1 = store.get_current_revision(fid)
        store.write_file(fid, b"v2")
        rid2 = store.get_current_revision(fid)
        d = diff_revisions(store, fid, rid1, rid2)
        self.assertTrue(d["changed"])
        store.close()


class MergeTests(unittest.TestCase):
    def test_no_conflict(self):
        base = VsnStore.create()
        base.create_file("a.txt", b"base")
        base.commit()
        ours = VsnStore.open(base._data)
        ours.create_file("b.txt", b"ours only")
        ours.commit()
        theirs = VsnStore.open(base._data)
        theirs.commit()
        result = three_way_merge(base, ours, theirs)
        self.assertFalse(result.has_conflicts)
        base.close()
        ours.close()
        theirs.close()

    def test_conflict_detection(self):
        base = VsnStore.create()
        fid = base.create_file("f.txt", b"base")
        base.commit()
        ours = VsnStore.open(base._data)
        ours.write_file(fid, b"ours")
        ours.commit()
        theirs = VsnStore.open(base._data)
        theirs.write_file(fid, b"theirs")
        theirs.commit()
        result = three_way_merge(base, ours, theirs)
        self.assertTrue(result.has_conflicts)
        self.assertEqual(result.conflicts[0].path, "f.txt")
        base.close()
        ours.close()
        theirs.close()

    def test_resolve_conflict(self):
        base = VsnStore.create()
        fid = base.create_file("f.txt", b"base")
        base.commit()
        ours = VsnStore.open(base._data)
        ours.write_file(fid, b"ours")
        ours.commit()
        theirs = VsnStore.open(base._data)
        theirs.write_file(fid, b"theirs")
        theirs.commit()
        result = three_way_merge(base, ours, theirs)
        resolve_conflict(result, "f.txt", b"resolved")
        self.assertFalse(result.has_conflicts)
        self.assertEqual(result.merged_files["f.txt"], b"resolved")
        base.close()
        ours.close()
        theirs.close()


class StorageTests(unittest.TestCase):
    def test_build_and_invalidate(self):
        store = VsnStore.create()
        store.create_file("a.txt", b"a")
        store.commit()
        mgr = StorageManager()
        mgr.build_indexes(store)
        self.assertTrue(mgr.is_valid)
        mgr.invalidate()
        self.assertFalse(mgr.is_valid)
        store.close()

    def test_recovery_without_derived(self):
        store = VsnStore.create()
        fid = store.create_file("test.txt", b"data")
        data = store.commit()
        store.close()
        from vsn.recovery import recover
        rr = recover(data)
        self.assertEqual(rr.status, "RECOVERED")
        store2 = VsnStore.open(data)
        self.assertEqual(store2.read_file(fid), b"data")
        store2.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
