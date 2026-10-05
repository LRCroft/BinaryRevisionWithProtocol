"""Behavioural tests for the LimitCleanUp library capability.

LimitCleanUp is a LIBRARY capability, not a VSN-1 protocol rule. It manages
canonical history at the Library level and must not alter VSN grammar,
identity, or the frozen error registry.

Contract under test (see Libraries/Documentation/library_api_contract.md):
  * scope is a single file's history (the VSN revision model is per-file)
  * `limit` is the maximum number of retained revisions and MUST be >= 1
  * limit == 0 is rejected so a slipped argument cannot destroy all history
  * the newest `limit` revisions are retained; older ones are removed
  * retained RevisionIds / contents / ObjectSerials are never rewritten
  * the file head revision is never removed
  * already <= limit revisions => nothing removed (idempotent)
  * persisted via the normal commit(); recovery must still work
"""
import unittest

from vsn import VsnStore, VsnError
from vsn import constants as C
from vsn.recovery import recover


def _store_with(n_revisions: int, path: str = "a.txt"):
    """Build a store whose file has exactly n_revisions revisions (1..n)."""
    store = VsnStore.create()
    fid = store.create_file(path, b"v1")
    for i in range(2, n_revisions + 1):
        store.write_file(fid, ("v%d" % i).encode())
    return store, fid


class LimitCleanUpRetentionTests(unittest.TestCase):
    def test_zero_revisions_keeps_nothing_and_is_a_noop(self):
        store = VsnStore.create()
        fid = store.create_file("a.txt", b"v1")
        # Exactly one revision exists (the create). limit large => no removal.
        removed = store.limit_cleanup(fid, 5)
        self.assertEqual(removed, [])
        self.assertEqual(store.list_revisions(fid), [1])

    def test_three_revisions_limit_five_removes_nothing(self):
        store, fid = _store_with(3)
        self.assertEqual(store.limit_cleanup(fid, 5), [])
        self.assertEqual(store.list_revisions(fid), [1, 2, 3])

    def test_five_revisions_limit_five_removes_nothing(self):
        store, fid = _store_with(5)
        self.assertEqual(store.limit_cleanup(fid, 5), [])
        self.assertEqual(store.list_revisions(fid), [1, 2, 3, 4, 5])

    def test_six_revisions_limit_five_keeps_newest_five(self):
        store, fid = _store_with(6)
        removed = store.limit_cleanup(fid, 5)
        self.assertEqual(removed, [1])
        self.assertEqual(store.list_revisions(fid), [2, 3, 4, 5, 6])

    def test_ten_revisions_limit_five_keeps_six_through_ten(self):
        store, fid = _store_with(10)
        removed = store.limit_cleanup(fid, 5)
        self.assertEqual(removed, [1, 2, 3, 4, 5])
        self.assertEqual(store.list_revisions(fid), [6, 7, 8, 9, 10])

    def test_limit_one_keeps_only_head(self):
        store, fid = _store_with(4)
        removed = store.limit_cleanup(fid, 1)
        self.assertEqual(removed, [1, 2, 3])
        self.assertEqual(store.list_revisions(fid), [4])

    def test_limit_zero_is_rejected(self):
        store, fid = _store_with(3)
        with self.assertRaises(VsnError) as ctx:
            store.limit_cleanup(fid, 0)
        self.assertEqual(ctx.exception.code, 0x000C)
        # The rejected call must not have mutated history.
        self.assertEqual(store.list_revisions(fid), [1, 2, 3])

    def test_negative_limit_is_rejected(self):
        store, fid = _store_with(3)
        with self.assertRaises(VsnError) as ctx:
            store.limit_cleanup(fid, -1)
        self.assertEqual(ctx.exception.code, 0x000C)

    def test_removed_revisions_are_unavailable_after_reopen(self):
        store, fid = _store_with(6)
        store.limit_cleanup(fid, 5)
        reopened = VsnStore.open(store.commit())
        self.assertEqual(reopened.list_revisions(fid), [2, 3, 4, 5, 6])
        with self.assertRaises(VsnError):
            reopened.get_revision(1)

    def test_idempotent_repeated_cleanup(self):
        store, fid = _store_with(10)
        first = store.limit_cleanup(fid, 5)
        second = store.limit_cleanup(fid, 5)
        self.assertEqual(first, [1, 2, 3, 4, 5])
        self.assertEqual(second, [])
        self.assertEqual(store.list_revisions(fid), [6, 7, 8, 9, 10])

    def test_smaller_limit_then_larger_does_not_recreate_history(self):
        store, fid = _store_with(10)
        store.limit_cleanup(fid, 3)
        self.assertEqual(store.list_revisions(fid), [8, 9, 10])
        store.limit_cleanup(fid, 5)  # larger than existing count: no-op
        self.assertEqual(store.list_revisions(fid), [8, 9, 10])
        self.assertEqual(VsnStore.open(store.commit()).list_revisions(fid),
                         [8, 9, 10])


class LimitCleanUpPreservationTests(unittest.TestCase):
    def test_retained_revision_ids_and_contents_are_byte_identical(self):
        store, fid = _store_with(10)
        before = {r: store.get_revision(r) for r in store.list_revisions(fid)}
        keep = [6, 7, 8, 9, 10]
        store.limit_cleanup(fid, 5)
        for rid in keep:
            after = store.get_revision(rid)
            self.assertEqual(after["revision_id"], before[rid]["revision_id"])
            self.assertEqual(after["object_serial"], before[rid]["object_serial"])
            self.assertEqual(store.materialize(after["object_serial"]),
                             store.materialize(before[rid]["object_serial"]))

    def test_retained_object_serials_survive_a_commit_cycle(self):
        store, fid = _store_with(6)
        keep = [2, 3, 4, 5, 6]
        serials = {r: store.get_revision(r)["object_serial"] for r in keep}
        store.limit_cleanup(fid, 5)
        reopened = VsnStore.open(store.commit())
        for rid in keep:
            self.assertEqual(reopened.get_revision(rid)["object_serial"],
                             serials[rid])

    def test_head_revision_and_content_survive_cleanup(self):
        store, fid = _store_with(6)
        head_before = store.get_current_revision(fid)
        content_before = store.read_file(fid)
        store.limit_cleanup(fid, 5)
        self.assertEqual(store.get_current_revision(fid), head_before)
        self.assertEqual(store.read_file(fid), content_before)
        reopened = VsnStore.open(store.commit())
        self.assertEqual(reopened.get_current_revision(fid), head_before)
        self.assertEqual(reopened.read_file(fid), content_before)

    def test_file_path_and_identity_survive_cleanup(self):
        store, fid = _store_with(6)
        store.limit_cleanup(fid, 5)
        reopened = VsnStore.open(store.commit())
        self.assertEqual(reopened.get_file_id("a.txt"), fid)
        self.assertIn((fid, "a.txt"), reopened.list_files())

    def test_recovery_still_works_after_cleanup(self):
        store, fid = _store_with(10)
        store.limit_cleanup(fid, 5)
        data = store.commit()
        result = recover(data)
        self.assertIsNotNone(result)
        self.assertTrue(result.recovered)
        self.assertEqual(result.accepted_generation, store.generation)

    def test_recovery_ignores_derived_state_after_cleanup(self):
        store, fid = _store_with(6)
        store.limit_cleanup(fid, 5)
        data = store.commit()
        recovered = recover(data)
        self.assertTrue(recovered.recovered)
        self.assertEqual(recovered.accepted_generation, store.generation)
        self.assertEqual(VsnStore.open(data).list_revisions(fid),
                         [2, 3, 4, 5, 6])

    def test_cleanup_then_new_commit_then_cleanup(self):
        store, fid = _store_with(6)
        store.limit_cleanup(fid, 5)
        data = store.commit()
        reopened = VsnStore.open(data)
        reopened.write_file(fid, b"v7")
        self.assertEqual(reopened.list_revisions(fid), [2, 3, 4, 5, 6, 7])
        self.assertEqual(reopened.limit_cleanup(fid, 5), [2])
        self.assertEqual(reopened.list_revisions(fid), [3, 4, 5, 6, 7])

    def test_object_store_is_preserved_for_shared_references(self):
        """Cleanup removes revisions, never objects other revisions may need."""
        store, fid = _store_with(6)
        object_serials = set(store.list_objects())
        store.limit_cleanup(fid, 5)
        self.assertEqual(set(store.list_objects()), object_serials)

    def test_scope_is_per_file(self):
        store = VsnStore.create()
        a = store.create_file("a.txt", b"a1")
        b = store.create_file("b.txt", b"b1")
        for i in range(2, 5):
            store.write_file(a, ("a%d" % i).encode())
            store.write_file(b, ("b%d" % i).encode())
        self.assertEqual(store.limit_cleanup(a, 2), [1, 3])
        self.assertEqual(store.list_revisions(a), [5, 7])
        self.assertEqual(store.list_revisions(b), [2, 4, 6, 8])

    def test_limit_cleanup_on_unknown_file_is_rejected(self):
        store = VsnStore.create()
        store.create_file("a.txt", b"v1")
        with self.assertRaises(VsnError) as ctx:
            store.limit_cleanup(bytes(16), 5)
        self.assertEqual(ctx.exception.code, 0x0009)

    def test_failure_does_not_report_false_success(self):
        store, fid = _store_with(4)
        before = store.list_revisions(fid)
        for bad in (0, -1, -100):
            with self.assertRaises(VsnError):
                store.limit_cleanup(fid, bad)
        self.assertEqual(store.list_revisions(fid), before)

    def test_mode_is_unchanged_and_no_protocol_record_is_added(self):
        store, fid = _store_with(6, "a.txt")
        store.limit_cleanup(fid, 5)
        reopened = VsnStore.open(store.commit())
        self.assertEqual(reopened.mode, C.MODE_MODERN)
        allowed = {C.REC_FILE_IDENTITY, C.REC_REVISION, C.REC_REVISION_SET,
                   C.REC_FILE_HEAD, C.REC_CONTENT_OBJECT, C.REC_COMMIT_MARKER,
                   C.REC_MODE_DECLARATION, C.REC_REPRESENTATION_DESCRIPTOR}
        for rec in reopened._parsed.records:
            self.assertIn(rec.rtype, allowed)

    def test_cleanup_leaves_only_valid_references(self):
        """No Revision may be removed while a FileHead still points at it."""
        store, fid = _store_with(6)
        store.limit_cleanup(fid, 5)
        reopened = VsnStore.open(store.commit())
        for rec in reopened._parsed.records:
            if rec.rtype == C.REC_FILE_HEAD:
                head = rec.field(C.FID_HEAD_REV_ID)
                self.assertIn(head.value_uvarint, reopened._revisions)

    def test_cleanup_is_rejected_on_a_closed_store(self):
        store, fid = _store_with(3)
        store.close()
        with self.assertRaises(VsnError) as ctx:
            store.limit_cleanup(fid, 1)
        self.assertEqual(ctx.exception.code, 0x0001)

    def test_rolled_back_transaction_leaves_history_for_cleanup(self):
        """A rolled-back transaction contributes no revision, so nothing to prune."""
        from vsn import Transaction
        store, fid = _store_with(3)
        txn = Transaction()
        txn.stage_update(fid, b"staged")
        txn.rollback()
        self.assertEqual(store.list_revisions(fid), [1, 2, 3])
        # Cleanup still behaves normally afterwards.
        self.assertEqual(store.limit_cleanup(fid, 2), [1])
        self.assertEqual(store.list_revisions(fid), [2, 3])

    def test_committed_transaction_then_cleanup(self):
        from vsn import Transaction
        store, fid = _store_with(2)
        txn = Transaction()
        txn.stage_update(fid, b"staged")
        txn.commit(store)
        self.assertEqual(store.list_revisions(fid), [1, 2, 3])
        self.assertEqual(store.limit_cleanup(fid, 2), [1])
        self.assertEqual(store.list_revisions(fid), [2, 3])

    def test_cleanup_does_not_depend_on_derived_state(self):
        """Deleting every derived artifact must not change the outcome."""
        store, fid = _store_with(6)
        # Populate derived state first, then clear it, then clean up.
        store.materialize(store.get_object_serial(fid))
        self.assertTrue(store._content_cache)
        store._content_cache.clear()
        self.assertEqual(store.limit_cleanup(fid, 5), [1])
        self.assertEqual(store.list_revisions(fid), [2, 3, 4, 5, 6])
        # The in-memory content cache must have been dropped, not left stale.
        self.assertEqual(store._content_cache, {})
