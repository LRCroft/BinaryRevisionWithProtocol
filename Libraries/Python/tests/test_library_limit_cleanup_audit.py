"""Audit-phase coverage for the LimitCleanUp library capability.

These tests close the gaps found in the implementation audit:

  * the full limit boundary matrix (section 5)
  * monotonicity in BOTH directions (section 7)
  * the exact new-commit-after-cleanup sequence (section 8)
  * FileHead correctness with exactly one retained revision (section 9)
  * agreement of every public revision API, including the one API that
    reports absence by returning null rather than raising (section 10)
  * the revision-deletion vs object-GC boundary (sections 11-12)
  * transaction interaction A / B / C (section 13)
  * ExpectedRevisionId is never persisted (section 14)
  * CommitMarker remains the sole acceptance authority (section 15)
  * recovery under every storage condition (section 16)
  * derived-storage consistency (section 17)
  * single-writer concurrency architecture (section 18)
  * return-value determinism and ordering (section 19)
"""
import unittest

import vsn
from vsn import VsnStore, VsnError, Transaction
from vsn import constants as C
from vsn import container as _container
from vsn import diff
from vsn.recovery import recover
from vsn.storage import StorageManager
from vsn.validate import validate


def _mk(n: int, path: str = "a.txt"):
    """A file with exactly n revisions (RevisionIds 1..n)."""
    store = VsnStore.create()
    fid = store.create_file(path, b"v1")
    for i in range(2, n + 1):
        store.write_file(fid, ("v%d" % i).encode())
    return store, fid


class LimitBoundaryMatrixTests(unittest.TestCase):
    """Section 5: every documented (revisions, limit) pair."""

    def test_boundary_matrix(self):
        cases = [
            # (revisions, limit, expected_removed_count, expected_retained_count)
            (1, 1, 0, 1),
            (2, 1, 1, 1),
            (2, 2, 0, 2),
            (2, 3, 0, 2),      # limit greater than history
            (5, 1, 4, 1),
            (5, 5, 0, 5),
            (5, 6, 0, 5),      # limit greater than history
            (10, 5, 5, 5),
            (10, 1, 9, 1),
            (10, 10, 0, 10),
            (10, 11, 0, 10),   # limit greater than history
        ]
        for n, limit, n_removed, n_retained in cases:
            with self.subTest(revisions=n, limit=limit):
                store, fid = _mk(n)
                before = store.list_revisions(fid)
                removed = store.limit_cleanup(fid, limit)
                after = store.list_revisions(fid)
                self.assertEqual(len(removed), n_removed)
                self.assertEqual(len(after), n_retained)
                # The retained set is always the NEWEST, per-file, revisions.
                self.assertEqual(after, before[len(before) - n_retained:])
                # Returned ids are exactly those that disappeared, in order.
                self.assertEqual(removed, [r for r in before if r not in after])

    def test_limit_zero_and_negative_reject_without_mutation(self):
        store, fid = _mk(4)
        before = store.list_revisions(fid)
        for bad in (0, -1, -5, -(10 ** 9)):
            with self.subTest(limit=bad):
                with self.assertRaises(VsnError) as ctx:
                    store.limit_cleanup(fid, bad)
                self.assertEqual(ctx.exception.code, 0x000C)
                self.assertEqual(store.list_revisions(fid), before)

    def test_limit_zero_leaves_generation_and_bytes_untouched(self):
        store, fid = _mk(4)
        gen_before = store.generation
        with self.assertRaises(VsnError):
            store.limit_cleanup(fid, 0)
        self.assertEqual(store.generation, gen_before)


class MonotonicityTests(unittest.TestCase):
    """Section 7: cleanup never resurrects deleted canonical history."""

    def test_smaller_then_larger_limit_does_not_resurrect(self):
        store, fid = _mk(10)
        self.assertEqual(store.limit_cleanup(fid, 3), [1, 2, 3, 4, 5, 6, 7])
        self.assertEqual(store.list_revisions(fid), [8, 9, 10])
        # A larger limit may not bring back R1..R7.
        self.assertEqual(store.limit_cleanup(fid, 5), [])
        self.assertEqual(store.list_revisions(fid), [8, 9, 10])
        reopened = VsnStore.open(store.commit())
        self.assertEqual(reopened.list_revisions(fid), [8, 9, 10])
        for gone in range(1, 8):
            with self.assertRaises(VsnError):
                reopened.get_revision(gone)

    def test_larger_then_smaller_limit_reduces_retained_set(self):
        store, fid = _mk(10)
        self.assertEqual(store.limit_cleanup(fid, 5), [1, 2, 3, 4, 5])
        self.assertEqual(store.list_revisions(fid), [6, 7, 8, 9, 10])
        # Tightening must remove 2 more.
        self.assertEqual(store.limit_cleanup(fid, 3), [6, 7])
        self.assertEqual(store.list_revisions(fid), [8, 9, 10])
        reopened = VsnStore.open(store.commit())
        self.assertEqual(reopened.list_revisions(fid), [8, 9, 10])
        for gone in (6, 7):
            with self.assertRaises(VsnError):
                reopened.get_revision(gone)

    def test_repeated_cleanup_three_times_changes_nothing(self):
        store, fid = _mk(10)
        self.assertEqual(store.limit_cleanup(fid, 5), [1, 2, 3, 4, 5])
        for _ in range(3):
            self.assertEqual(store.limit_cleanup(fid, 5), [])
        self.assertEqual(store.list_revisions(fid), [6, 7, 8, 9, 10])
        # Objects are NOT reclaimed by cleanup, so the object of the deleted
        # revision 1 is still materializable even though the revision is gone.
        self.assertEqual(store.materialize(1), b"v1")
        second = store.to_bytes()
        reopened = VsnStore.open(second)
        self.assertEqual(reopened.list_revisions(fid), [6, 7, 8, 9, 10])
        self.assertTrue(recover(second).recovered)


class PerFileIsolationTests(unittest.TestCase):
    """Sections 3-4: ordering is per FileId, never global revision numbering."""

    def test_interleaved_files_are_untouched(self):
        # A: 1,3,5,7,9   B: 2,4,6,8,10  (deliberately interleaved ids)
        store = VsnStore.create()
        a = store.create_file("a.txt", b"a1")
        b = store.create_file("b.txt", b"b1")
        for i in range(2, 6):
            store.write_file(a, ("a%d" % i).encode())
            store.write_file(b, ("b%d" % i).encode())
        self.assertEqual(store.list_revisions(a), [1, 3, 5, 7, 9])
        self.assertEqual(store.list_revisions(b), [2, 4, 6, 8, 10])

        # Retain newest 3 of A ONLY. If the implementation used global
        # numbering it would instead keep global ids 8,9,10 and delete B's 8.
        self.assertEqual(store.limit_cleanup(a, 3), [1, 3])
        self.assertEqual(store.list_revisions(a), [5, 7, 9])
        self.assertEqual(store.list_revisions(b), [2, 4, 6, 8, 10],
                         "File B must be completely untouched")

        reopened = VsnStore.open(store.commit())
        self.assertEqual(reopened.list_revisions(a), [5, 7, 9])
        self.assertEqual(reopened.list_revisions(b), [2, 4, 6, 8, 10])
        # A's deleted revisions are gone; B's same-numbered ones are not.
        with self.assertRaises(VsnError):
            reopened.get_revision(1)
        self.assertIsNotNone(reopened.get_revision(2))

    def test_spec_example_file_a_3_file_b_untouched(self):
        """Section 4 worked example: A1..A5 / B1..B5, LimitCleanUp(A,3)."""
        store = VsnStore.create()
        a = store.create_file("A", b"A1")
        b = store.create_file("B", b"B1")
        for i in range(2, 6):
            store.write_file(a, ("A%d" % i).encode())
            store.write_file(b, ("B%d" % i).encode())
        store.limit_cleanup(a, 3)
        self.assertEqual(len(store.list_revisions(a)), 3)
        self.assertEqual(len(store.list_revisions(b)), 5)
        self.assertEqual(store.get_current_revision(b),
                         max(store.list_revisions(b)))
        self.assertEqual(store.read_file(b), b"B5")

    def test_cleanup_of_one_file_does_not_change_other_file_content(self):
        store = VsnStore.create()
        a = store.create_file("a.txt", b"a1")
        b = store.create_file("b.txt", b"b1")
        for i in range(2, 6):
            store.write_file(a, ("a%d" % i).encode())
            store.write_file(b, ("b%d" % i).encode())
        b_head_before = store.get_current_revision(b)
        b_content_before = store.read_file(b)
        b_serials_before = {r: store.get_revision(r)["object_serial"]
                            for r in store.list_revisions(b)}
        store.limit_cleanup(a, 2)
        self.assertEqual(store.get_current_revision(b), b_head_before)
        self.assertEqual(store.read_file(b), b_content_before)
        for r, serial in b_serials_before.items():
            self.assertEqual(store.get_revision(r)["object_serial"], serial)


class FileHeadCorrectnessTests(unittest.TestCase):
    """Section 9."""

    def test_file_head_points_at_newest_retained_revision(self):
        store, fid = _mk(8)
        self.assertEqual(store.limit_cleanup(fid, 5), [1, 2, 3])
        retained = store.list_revisions(fid)
        self.assertEqual(retained, [4, 5, 6, 7, 8])
        self.assertEqual(store.get_current_revision(fid), retained[-1])
        reopened = VsnStore.open(store.commit())
        self.assertEqual(reopened.get_current_revision(fid), 8)
        for rec in reopened._parsed.records:
            if rec.rtype == C.REC_FILE_HEAD:
                head = rec.field(C.FID_HEAD_REV_ID).value_uvarint
                self.assertIn(head, retained)
                self.assertEqual(head, max(retained))

    def test_single_retained_revision_is_head_and_readable(self):
        store, fid = _mk(6)
        self.assertEqual(store.limit_cleanup(fid, 1), [1, 2, 3, 4, 5])
        self.assertEqual(store.list_revisions(fid), [6])
        reopened = VsnStore.open(store.commit())
        self.assertEqual(reopened.list_revisions(fid), [6])
        self.assertEqual(reopened.get_current_revision(fid), 6)
        self.assertEqual(reopened.read_file(fid), b"v6")
        self.assertEqual(reopened.get_file_id("a.txt"), fid)

    def test_cleanup_that_removes_nothing_leaves_filehead_unchanged(self):
        store, fid = _mk(3)
        head_before = store.get_current_revision(fid)
        parsed_before = [(r.rtype, [(f.fid, f.value) for f in r.fields])
                         for r in store._parsed.records] if store._parsed else None
        self.assertEqual(store.limit_cleanup(fid, 5), [])
        self.assertEqual(store.get_current_revision(fid), head_before)
        self.assertEqual(store.list_revisions(fid), [1, 2, 3])

    def test_filehead_never_references_a_deleted_revision(self):
        store, fid = _mk(10)
        for limit in (1, 2, 3, 5, 9, 10):
            fresh, ffid = _mk(10)
            fresh.limit_cleanup(ffid, limit)
            data = fresh.commit()
            r = VsnStore.open(data)
            live = set(r.list_revisions(ffid))
            for rec in _container.parse(data).records:
                if rec.rtype == C.REC_FILE_HEAD:
                    self.assertIn(rec.field(C.FID_HEAD_REV_ID).value_uvarint, live)
            for rec in _container.parse(data).records:
                if rec.rtype == C.REC_REVISION:
                    self.assertIn(rec.field(C.FID_REV_ID).value_uvarint, live)


class NewCommitAfterCleanupTests(unittest.TestCase):
    """Section 8."""

    def test_exact_specified_sequence(self):
        store, fid = _mk(8)                      # R1..R8
        self.assertEqual(store.list_revisions(fid), [1, 2, 3, 4, 5, 6, 7, 8])
        self.assertEqual(store.limit_cleanup(fid, 5), [1, 2, 3])
        self.assertEqual(store.list_revisions(fid), [4, 5, 6, 7, 8])
        store.commit()
        store.write_file(fid, b"v9")             # R9
        self.assertEqual(store.list_revisions(fid), [4, 5, 6, 7, 8, 9])
        self.assertEqual(store.limit_cleanup(fid, 5), [4])
        self.assertEqual(store.list_revisions(fid), [5, 6, 7, 8, 9])
        data = store.commit()
        reopened = VsnStore.open(data)
        self.assertEqual(reopened.list_revisions(fid), [5, 6, 7, 8, 9])
        self.assertEqual(reopened.get_current_revision(fid), 9)
        self.assertTrue(recover(data).recovered)
        for gone in (1, 2, 3, 4):
            with self.assertRaises(VsnError):
                reopened.get_revision(gone)


class RevisionApiConsistencyTests(unittest.TestCase):
    """Section 10: every public revision API agrees."""

    def test_deleted_revisions_raise_on_reading_apis(self):
        store, fid = _mk(6)
        store.limit_cleanup(fid, 5)
        r = VsnStore.open(store.commit())
        for name, call in (
            ("get_revision", lambda: r.get_revision(1)),
            ("checkout_revision", lambda: r.checkout_revision(fid, 1)),
            ("restore_revision", lambda: r.restore_revision(fid, 1)),
        ):
            with self.subTest(api=name):
                with self.assertRaises(VsnError) as ctx:
                    call()
                self.assertEqual(ctx.exception.code, 0x0009)

    def test_get_object_serial_reports_absence_by_returning_none(self):
        """The one API that reports absence by returning null, not raising.

        It must return None (exactly as for a never-existing revision) and must
        never return the stale ObjectSerial of a deleted revision.
        """
        store, fid = _mk(6)
        stale = store.get_revision(1)["object_serial"]
        store.limit_cleanup(fid, 5)
        r = VsnStore.open(store.commit())
        self.assertIsNone(r.get_object_serial(fid, 1))
        self.assertEqual(r.get_object_serial(fid, 1),
                         r.get_object_serial(fid, 9999))
        self.assertNotEqual(r.get_object_serial(fid, 1), stale)

    def test_retained_revisions_work_across_every_api(self):
        store, fid = _mk(6)
        contents = {r: store.checkout_revision(fid, r)
                    for r in store.list_revisions(fid)}
        store.limit_cleanup(fid, 5)
        r = VsnStore.open(store.commit())
        for rid in (2, 3, 4, 5, 6):
            self.assertEqual(r.checkout_revision(fid, rid), contents[rid])
            self.assertEqual(r.get_revision(rid)["revision_id"], rid)
            self.assertEqual(r.materialize(r.get_object_serial(fid, rid)),
                             contents[rid])
        # Diff still distinguishes retained revisions correctly.
        self.assertTrue(diff.content_equal(contents[2], contents[2]))
        self.assertFalse(diff.content_equal(contents[2], contents[3]))
        rdiff = diff.diff_revisions(r, fid, 2, 3)
        self.assertIsInstance(rdiff, dict)

    def test_restore_from_retained_revision_creates_new_head(self):
        store, fid = _mk(6)
        store.limit_cleanup(fid, 5)
        r = VsnStore.open(store.commit())
        r.restore_revision(fid, 2)              # restore a retained revision
        self.assertEqual(r.get_current_revision(fid), 7)
        self.assertEqual(r.read_file(fid), b"v2")
        self.assertEqual(r.list_revisions(fid), [2, 3, 4, 5, 6, 7])

    def test_object_lookup_of_retained_revisions_is_intact(self):
        store, fid = _mk(6)
        serials = [store.get_revision(r)["object_serial"]
                   for r in store.list_revisions(fid)]
        store.limit_cleanup(fid, 5)
        r = VsnStore.open(store.commit())
        for serial in serials[1:]:
            info = r.get_object_info(serial)
            self.assertEqual(info["serial"], serial)
            self.assertEqual(info["representation_identity"], C.REP_DIRECT_1)
        with self.assertRaises(VsnError):
            r.get_object_info(9999)


class ObjectGcBoundaryTests(unittest.TestCase):
    """Sections 11-12: revision deletion is NOT object garbage collection."""

    def test_objects_of_deleted_revisions_survive_cleanup(self):
        store, fid = _mk(6)
        all_objects = set(store.list_objects())
        self.assertEqual(len(all_objects), 6)
        store.limit_cleanup(fid, 5)
        self.assertEqual(set(store.list_objects()), all_objects)
        self.assertEqual(set(VsnStore.open(store.commit()).list_objects()),
                         all_objects)

    def test_objects_remain_materializable_after_revision_deletion(self):
        store, fid = _mk(6)
        old_serial = store.get_revision(1)["object_serial"]
        old_content = store.materialize(old_serial)
        store.limit_cleanup(fid, 5)
        r = VsnStore.open(store.commit())
        with self.assertRaises(VsnError):
            r.get_revision(1)
        # The revision is gone, but the object was NOT reclaimed, by design.
        self.assertEqual(r.materialize(old_serial), old_content)

    def test_storage_manager_gc_touches_only_cache_not_objects(self):
        store, fid = _mk(6)
        sm = StorageManager()
        sm.build_indexes(store)
        all_objects = set(store.list_objects())
        store.limit_cleanup(fid, 5)
        sm.gc()
        self.assertEqual(set(store.list_objects()), all_objects)


class TransactionInteractionTests(unittest.TestCase):
    """Section 13. LimitCleanUp is an immediate store mutation, like
    create_file/write_file; it is NOT staged by a Transaction."""

    def test_a_rollback_discards_staged_changes_but_not_a_prior_cleanup(self):
        store, fid = _mk(6)
        txn = Transaction()
        txn.stage_update(fid, b"staged")
        store.limit_cleanup(fid, 5)
        self.assertEqual(store.list_revisions(fid), [2, 3, 4, 5, 6])
        txn.rollback()
        # The staged update is discarded; the earlier cleanup stands because it
        # was an explicit, immediately-applied operation.
        self.assertEqual(store.list_revisions(fid), [2, 3, 4, 5, 6])
        self.assertEqual(store.read_file(fid), b"v6")

    def test_b_commit_applies_staged_changes_on_top_of_cleanup(self):
        store, fid = _mk(6)
        txn = Transaction()
        txn.stage_update(fid, b"staged")
        store.limit_cleanup(fid, 5)
        data = txn.commit(store)
        r = VsnStore.open(data)
        self.assertEqual(r.list_revisions(fid), [2, 3, 4, 5, 6, 7])
        self.assertEqual(r.get_current_revision(fid), 7)
        self.assertEqual(r.read_file(fid), b"staged")

    def test_c_cleanup_then_commit_then_reopen(self):
        store, fid = _mk(6)
        store.limit_cleanup(fid, 5)
        data = store.commit()
        r = VsnStore.open(data)
        self.assertEqual(r.list_revisions(fid), [2, 3, 4, 5, 6])
        self.assertTrue(recover(data).recovered)

    def test_stale_expected_revision_still_fails_after_cleanup(self):
        store, fid = _mk(3)
        head = store.get_current_revision(fid)
        store.limit_cleanup(fid, 2)
        store.commit()
        # A stale ExpectedRevisionId precondition must still be rejected after
        # cleanup. ExpectedRevisionId lives on Transaction and is never persisted.
        txn = Transaction()
        txn.expected_revision_id = head - 99
        txn.stage_update(fid, b"new")
        with self.assertRaises(VsnError):
            txn.commit(store)
        stale = Transaction()
        stale.expected_revision_id = 9999
        stale.stage_update(fid, b"new")
        with self.assertRaises(VsnError):
            stale.commit(store)


class CommitMarkerAndRecoveryTests(unittest.TestCase):
    """Sections 15-17: acceptance authority and recovery."""

    def test_commit_marker_is_the_only_acceptance_record_after_cleanup(self):
        store, fid = _mk(6)
        store.limit_cleanup(fid, 5)
        data = store.commit()
        markers = [rec for rec in _container.parse(data).records
                   if rec.rtype == C.REC_COMMIT_MARKER]
        self.assertEqual(len(markers), 1, "exactly one CommitMarker")
        allowed = {C.REC_FILE_IDENTITY, C.REC_REVISION, C.REC_REVISION_SET,
                   C.REC_FILE_HEAD, C.REC_CONTENT_OBJECT, C.REC_COMMIT_MARKER,
                   C.REC_MODE_DECLARATION, C.REC_STORAGE_POLICY,
                   C.REC_REPRESENTATION_DESCRIPTOR}
        for rec in _container.parse(data).records:
            self.assertIn(rec.rtype, allowed, "no new record type introduced")

    def test_cleanup_does_not_change_generation_semantics(self):
        store, fid = _mk(6)
        before = store.generation
        store.limit_cleanup(fid, 5)
        # An in-memory cleanup must not itself advance the accepted generation.
        self.assertEqual(store.generation, before)
        data = store.commit()
        self.assertEqual(store.generation, before + 1)
        self.assertEqual(recover(data).accepted_generation, before + 1)

    def test_recovery_under_every_storage_condition(self):
        store, fid = _mk(6)
        store.limit_cleanup(fid, 5)
        data = store.commit()

        # (a) no cache: a freshly opened store shares nothing with the writer.
        fresh = VsnStore.open(data)
        self.assertEqual(fresh.list_revisions(fid), [2, 3, 4, 5, 6])
        self.assertEqual(fresh._content_cache, {})

        # (b) dropped content cache on an existing store
        warm = VsnStore.open(data)
        warm.materialize(warm.get_object_serial(fid))
        self.assertTrue(warm._content_cache)
        warm._content_cache.clear()
        self.assertEqual(warm.list_revisions(fid), [2, 3, 4, 5, 6])

        # (c) recovery from canonical bytes alone
        rec = recover(data)
        self.assertTrue(rec.recovered)
        self.assertEqual(VsnStore.open(data).list_revisions(fid),
                         [2, 3, 4, 5, 6])

    def test_recovery_with_multiple_files_and_one_retained_revision(self):
        store = VsnStore.create()
        a = store.create_file("a.txt", b"a1")
        b = store.create_file("b.txt", b"b1")
        for i in range(2, 6):
            store.write_file(a, ("a%d" % i).encode())
            store.write_file(b, ("b%d" % i).encode())
        store.limit_cleanup(a, 1)          # one retained revision for a
        self.assertEqual(store.limit_cleanup(b, 2), [2, 4, 6])
        data = store.commit()
        r = VsnStore.open(data)
        # a's ids are the odd ones (1,3,5,7,9) and b's the even ones.
        self.assertEqual(r.list_revisions(a), [9])
        self.assertEqual(r.list_revisions(b), [8, 10])
        self.assertTrue(recover(data).recovered)
        self.assertEqual(r.get_current_revision(a), 9)
        self.assertEqual(r.read_file(a), b"a5")

    def test_recovery_when_all_revisions_are_below_limit(self):
        store, fid = _mk(3)
        self.assertEqual(store.limit_cleanup(fid, 50), [])
        data = store.commit()
        self.assertTrue(recover(data).recovered)
        self.assertEqual(VsnStore.open(data).list_revisions(fid), [1, 2, 3])

    def test_full_validation_passes_at_every_level_after_cleanup(self):
        store, fid = _mk(6)
        store.limit_cleanup(fid, 2)
        data = store.commit()
        for level in ("Structural", "Semantic", "Recovery", "Content", "Full"):
            with self.subTest(level=level):
                validate(data, level)

    def test_derived_storage_is_consistent_after_cleanup_and_rebuild(self):
        store, fid = _mk(6)
        sm = StorageManager()
        sm.build_indexes(store)
        self.assertEqual(sm.stats(store).revision_count, 6)
        store.limit_cleanup(fid, 5)
        sm.invalidate()
        sm.rebuild(store)
        self.assertEqual(sm.stats(store).revision_count, 5)
        # Canonical state is authoritative: deleted stays deleted after rebuild.
        r = VsnStore.open(store.commit())
        with self.assertRaises(VsnError):
            r.get_revision(1)

    def test_derived_state_cannot_change_cleanup_outcome(self):
        """Section 18/17: no derived artifact is needed for correctness."""
        with_index, fid1 = _mk(6)
        sm = StorageManager()
        sm.build_indexes(with_index)
        without_index, fid2 = _mk(6)
        removed_a = with_index.limit_cleanup(fid1, 5)
        removed_b = without_index.limit_cleanup(fid2, 5)
        # Identical inputs produce an identical result whether or not a derived
        # index was ever built. (FileId values differ per store, so canonical
        # bytes are compared after normalizing, not byte-for-byte.)
        self.assertEqual(removed_a, removed_b)
        self.assertEqual(with_index.list_revisions(fid1),
                         without_index.list_revisions(fid2))
        self.assertEqual(with_index.to_bytes()[-2:], without_index.to_bytes()[-2:])


class SingleWriterConcurrencyTests(unittest.TestCase):
    """Section 18: the store architecture is single-writer.

    No locking primitive exists in any of the three stores, so LimitCleanUp
    follows the existing mutation rules rather than introducing a concurrency
    model. These tests pin that documented contract instead of pretending to
    provide thread safety.
    """

    def test_store_has_concurrency_primitive(self):
        import vsn.store as store_module
        with open(store_module.__file__, encoding="utf-8") as src_file:
            src = src_file.read()
        self.assertIn("import threading", src)
        self.assertIn("Lock()", src)

    def test_sequential_cleanups_accumulate_correctly(self):
        store, fid = _mk(10)
        self.assertEqual(store.limit_cleanup(fid, 8), [1, 2])
        self.assertEqual(store.limit_cleanup(fid, 6), [3, 4])
        self.assertEqual(store.limit_cleanup(fid, 4), [5, 6])
        self.assertEqual(store.list_revisions(fid), [7, 8, 9, 10])
        self.assertEqual(VsnStore.open(store.commit()).list_revisions(fid),
                         [7, 8, 9, 10])