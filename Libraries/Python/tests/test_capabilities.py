"""Capability-surface probes: one functional check per Library-Complete capability.

The conformance runner reports Library-Complete only when EVERY capability
probe passes. Each probe exercises the capability end-to-end; an API stub
alone never counts as a capability.
"""
import io
import unittest

import vsn
from vsn import constants as C
from vsn import io_ops
from vsn.store import VsnStore
from vsn.transactions import Transaction


class ContainerLifecycleTests(unittest.TestCase):
    def test_container_lifecycle_capability(self):
        s = VsnStore.create()
        fid = s.create_file("a.txt", b"hello")
        data = s.commit()
        s.close()
        with self.assertRaises(vsn.VsnError):
            s.list_files()
        s2 = VsnStore.open(data)
        self.assertEqual(s2.read_file(fid), b"hello")
        s2.reopen()
        self.assertEqual(s2.read_file(fid), b"hello")
        info = vsn.inspect_container(s2)
        self.assertEqual(info["file_count"], 1)
        self.assertEqual(info["object_count"], 1)
        self.assertEqual(vsn.validate_container(data, "Full"), [])
        self.assertEqual(vsn.recover_container(data).status, "RECOVERED")
        s2.close()


class FileApiTests(unittest.TestCase):
    def test_file_api_capability(self):
        s = VsnStore.create()
        fid = s.create_file("a.txt", b"one")
        self.assertEqual(s.read_file(fid), b"one")
        s.write_file(fid, b"two")
        self.assertEqual(s.read_file(fid), b"two")
        s.rename_file(fid, "b.txt")
        self.assertEqual(s.get_file_id("b.txt"), fid)
        self.assertEqual(len(s.list_files()), 1)
        self.assertTrue(s.file_exists(fid))
        s.delete_file(fid)
        self.assertFalse(s.file_exists(fid))
        with self.assertRaises(vsn.VsnError):
            s.create_file("b.txt", b"dup")
        s.close()


class RevisionApiTests(unittest.TestCase):
    def test_revision_api_capability(self):
        s = VsnStore.create()
        fid = s.create_file("a.txt", b"v1")
        s.write_file(fid, b"v2")
        s.write_file(fid, b"v3")
        self.assertEqual(s.list_revisions(fid), [1, 2, 3])
        self.assertEqual(s.get_revision(1)["object_serial"], 1)
        self.assertEqual(s.checkout_revision(fid, 1), b"v1")
        s.restore_revision(fid, 1)
        self.assertEqual(s.read_file(fid), b"v1")
        # Revision metadata carries the owning FileId and presence.
        meta = s.get_revision(3)
        self.assertEqual(meta["file_id"], fid)
        self.assertEqual(meta["presence"], C.PRESENT)
        self.assertEqual(s.get_current_revision(fid), 4)
        s.close()
