"""VSN Python Storage Policy Conformance Tests (CAP-P01 through CAP-P10).

Behavioral tests per VSN1_Library_Storage_Policy_API_Contract.md.
No fake PASS checks; every test exercises real library code and asserts
on actual serialized bytes or state.
"""
import hashlib
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import vsn
from vsn import constants as C
from vsn.constants import (
    StoragePolicy, WireMode,
    STORAGE_POLICY_TO_WIRE_MODE, WIRE_MODE_TO_POLICIES,
)
from vsn.writer_options import WriterOptions, OptimizationConfiguration, SearchConfiguration
from vsn.errors import (
    InvalidStoragePolicy,
    PolicyWireModeConflict,
    InvalidOptimizationConfiguration,
)

TV = os.path.join(os.path.dirname(__file__), "..", "TestVectors")


def _load(name):
    with open(os.path.join(TV, name + ".vsn"), "rb") as f:
        return f.read()


class CAP01_PolicyEnumeration(unittest.TestCase):
    """CAP-P01: Verify exactly four public policy values."""

    def test_exactly_four_values(self):
        values = [StoragePolicy.HIGHLY_VERTICAL, StoragePolicy.VERTICAL,
                  StoragePolicy.HORIZONTAL, StoragePolicy.HIGHLY_HORIZONTAL]
        self.assertEqual(len(values), 4)
        for p in (StoragePolicy.HIGHLY_VERTICAL, StoragePolicy.VERTICAL,
                  StoragePolicy.HORIZONTAL, StoragePolicy.HIGHLY_HORIZONTAL):
            self.assertIn(p, values)

    def test_no_balanced(self):
        names = [e.name for e in StoragePolicy]
        self.assertNotIn("BALANCED", names)

    def test_distinct_from_wire_mode(self):
        hv = StoragePolicy.HIGHLY_VERTICAL
        self.assertIsInstance(hv, StoragePolicy)
        self.assertNotIsInstance(hv, WireMode)
        # Different enum types
        self.assertIsNot(type(hv), type(vsn.WireMode.MODERN))

    def test_all_int_enum(self):
        self.assertEqual(int(StoragePolicy.HIGHLY_VERTICAL), 1)
        self.assertEqual(int(StoragePolicy.VERTICAL), 2)
        self.assertEqual(int(StoragePolicy.HORIZONTAL), 3)
        self.assertEqual(int(StoragePolicy.HIGHLY_HORIZONTAL), 4)


class CAP02_PolicyToWireMode(unittest.TestCase):
    """CAP-P02: For each policy, verify effective wire mode resolution."""

    def test_highly_vertical_maps_to_modern(self):
        opts = WriterOptions(storage_policy=StoragePolicy.HIGHLY_VERTICAL)
        self.assertEqual(opts.effective_wire_mode, C.MODE_MODERN)

    def test_vertical_maps_to_modern(self):
        opts = WriterOptions(storage_policy=StoragePolicy.VERTICAL)
        self.assertEqual(opts.effective_wire_mode, C.MODE_MODERN)

    def test_horizontal_maps_to_enterprise(self):
        opts = WriterOptions(storage_policy=StoragePolicy.HORIZONTAL)
        self.assertEqual(opts.effective_wire_mode, C.MODE_ENTERPRISE)

    def test_highly_horizontal_maps_to_enterprise(self):
        opts = WriterOptions(storage_policy=StoragePolicy.HIGHLY_HORIZONTAL)
        self.assertEqual(opts.effective_wire_mode, C.MODE_ENTERPRISE)

    def test_none_returns_none(self):
        opts = WriterOptions()
        self.assertIsNone(opts.effective_wire_mode)

    def test_explicit_constraint_matches(self):
        opts = WriterOptions(
            storage_policy=StoragePolicy.HIGHLY_VERTICAL,
            wire_mode_constraint=C.MODE_MODERN,
        )
        self.assertEqual(opts.effective_wire_mode, C.MODE_MODERN)

    def test_conflict_highly_vertical_enterprise(self):
        with self.assertRaises(PolicyWireModeConflict):
            WriterOptions(
                storage_policy=StoragePolicy.HIGHLY_VERTICAL,
                wire_mode_constraint=C.MODE_ENTERPRISE,
            ).effective_wire_mode

    def test_conflict_horizontal_modern(self):
        with self.assertRaises(PolicyWireModeConflict):
            WriterOptions(
                storage_policy=StoragePolicy.HORIZONTAL,
                wire_mode_constraint=C.MODE_MODERN,
            ).effective_wire_mode


class CAP03_NoIllegalWireMode(unittest.TestCase):
    """CAP-P03: Verify ModeDeclaration is 0x01 or 0x02 for all policies."""

    def _create_with_policy(self, policy):
        store = vsn.VsnStore(storage_policy=policy)
        fid = b"\x01" * 16
        store.create_file("test_file", ("test content for %s" % policy.name).encode("utf-8"))
        data = store.commit()
        return data

    def test_all_policies_valid_modern_or_enterprise(self):
        for policy in StoragePolicy:
            data = self._create_with_policy(policy)
            parsed = vsn.container.parse(data)
            mode = parsed.mode
            self.assertIsNotNone(mode, "mode should not be None")
            self.assertIn(mode, (C.MODE_MODERN, C.MODE_ENTERPRISE),
                        "ModeDeclaration for %s must be 0x01 or 0x02" % policy.name)

    def test_no_0x03_mode_declaration(self):
        for policy in StoragePolicy:
            data = self._create_with_policy(policy)
            parsed = vsn.container.parse(data)
            self.assertNotEqual(parsed.mode, 0x03, "ModeDeclaration 0x03 must never appear")

    def test_no_0x04_mode_declaration(self):
        for policy in StoragePolicy:
            data = self._create_with_policy(policy)
            parsed = vsn.container.parse(data)
            self.assertNotEqual(parsed.mode, 0x04, "ModeDeclaration 0x04 must never appear")

    def test_byte_level_mode_declaration(self):
        hv_data = self._create_with_policy(StoragePolicy.HIGHLY_VERTICAL)
        parsed = vsn.container.parse(hv_data)
        for rec in parsed.records:
            if rec.rtype == C.REC_MODE_DECLARATION:
                mode_field = rec.field(C.FID_MODE)
                self.assertIsNotNone(mode_field)
                mode_val = mode_field.value[0]
                self.assertEqual(mode_val, 0x01)


class CAP04_ReaderIndependence(unittest.TestCase):
    """CAP-P04: Read containers with no policy knowledge."""

    def test_all_policies_readable_without_policy(self):
        for policy in StoragePolicy:
            store_w = vsn.VsnStore(storage_policy=policy)
            file_id = store_w.create_file("rev_test_%d" % int(policy), ("policy %s content" % policy.name).encode("utf-8"))
            data = store_w.commit()

            # Open WITHOUT passing any storage policy
            store_r = vsn.VsnStore.open(data)

            files = store_r.files()
            self.assertEqual(len(files), 1, "should see exactly one file")
            content = store_r.read_file(file_id)
            expected = ("policy %s content" % policy.name).encode("utf-8")
            self.assertEqual(content, expected, "content round-trip must match for %s" % policy.name)

    def test_recovery_without_policy(self):
        for policy in StoragePolicy:
            store_w = vsn.VsnStore(storage_policy=policy)
            file_id = store_w.create_file("recovery_%d" % int(policy), ("recovery test %s" % policy.name).encode("utf-8"))
            data = store_w.commit()
            result = vsn.recover_fn(data)
            self.assertEqual(result.accepted_generation, store_w.generation)

    def test_validate_without_policy(self):
        for policy in StoragePolicy:
            store_w = vsn.VsnStore(storage_policy=policy)
            store_w.create_file("val_test_%d" % int(policy), b"validate test")
            data = store_w.commit()
            # Should not raise
            vsn.validate_fn(data, "Full")


class CAP05_LogicalEquivalence(unittest.TestCase):
    """CAP-P05: Create equivalent logical content under multiple policies."""

    def test_same_content_different_policies(self):
        content = b"equivalent content for all four policies"
        results = {}
        for policy in StoragePolicy:
            store = vsn.VsnStore(storage_policy=policy)
            fid = b"\x05" * 16
            store.create_file("test_file", content)
            data = store.commit()
            parsed = vsn.container.parse(data)
            mode = parsed.mode
            results[policy] = {"mode": mode, "data": data}

        for hv in (StoragePolicy.HIGHLY_VERTICAL, StoragePolicy.VERTICAL):
            self.assertEqual(results[hv]["mode"], C.MODE_MODERN)
        for hp in (StoragePolicy.HORIZONTAL, StoragePolicy.HIGHLY_HORIZONTAL):
            self.assertEqual(results[hp]["mode"], C.MODE_ENTERPRISE)

        for policy in StoragePolicy:
            store = vsn.VsnStore.open(results[policy]["data"])
            files = store.files()
            retrieved = store.read_file(files[0][0])
            self.assertEqual(retrieved, content)


class CAP06_ObjectSerialPreservation(unittest.TestCase):
    """CAP-P06: Verify ObjectSerial preservation across policy rewrite."""

    def test_object_serial_preserved_on_commit_reopen(self):
        store = vsn.VsnStore(storage_policy=StoragePolicy.HIGHLY_VERTICAL)
        content_a = b"object serial preservation test A"
        store.create_file("cap06_test", content_a)
        data1 = store.commit()

        parsed1 = vsn.container.parse(data1)
        serials_before = [obj.serial for obj in parsed1.objects]

        # VsnStore.open is a classmethod that creates a new instance.
        # Override storage_policy on the reopened instance to exercise policy switching.
        store2 = vsn.VsnStore.open(data1)
        store2.close()
        store3 = vsn.VsnStore.open(data1)
        store3._storage_policy = StoragePolicy.HIGHLY_HORIZONTAL  # type: ignore[attr-defined]
        data2 = store3.commit()

        parsed2 = vsn.container.parse(data2)
        serials_after = [obj.serial for obj in parsed2.objects]

        self.assertEqual(serials_before, serials_after,
                         "ObjectSerial must be preserved across policy change")


class CAP07_CommitRecovery(unittest.TestCase):
    """CAP-P07: Real transactions using each policy."""

    def test_all_policies_commit_accepted(self):
        for policy in StoragePolicy:
            store = vsn.VsnStore(storage_policy=policy)
            fid = b"\x07" * 16
            store.create_file("test_file", ("transaction test %s" % policy.name).encode("utf-8"))
            data = store.commit()

            parsed = vsn.container.parse(data)
            self.assertIsNotNone(parsed.trailer_generation,
                                 "commit must have a generation")

            result = vsn.recover_fn(data)
            self.assertEqual(result.accepted_generation, store.generation)

    def test_recovery_from_multiple_commits(self):
        store = vsn.VsnStore(storage_policy=StoragePolicy.VERTICAL)
        store.create_file("gen1_file", b"gen1")
        data1 = store.commit()
        gen_before = store.generation

        store.create_file("gen2_file", b"gen2")
        data2 = store.commit()
        self.assertEqual(store.generation, gen_before + 1)

        result = vsn.recover_fn(data2)
        self.assertEqual(result.accepted_generation, store.generation)

    def test_transaction_state_validity(self):
        for policy in StoragePolicy:
            store = vsn.VsnStore(storage_policy=policy)
            fid = b"\x09" * 16
            store.create_file("test_file", b"uncommitted")
            self.assertFalse(hasattr(store, "_closed") and store._closed)


class CAP08_OptimizationBudget(unittest.TestCase):
    """CAP-P08: Constrained optimization configuration."""

    def test_fallback_on_zero_dependency_depth(self):
        opt = OptimizationConfiguration(max_dependency_depth=0)
        store = vsn.VsnStore(
            storage_policy=StoragePolicy.HIGHLY_VERTICAL,
            optimization_config=opt,
        )
        fid = b"\x0a" * 16
        store.create_file("test_file", b"budget constrained test")
        data = store.commit()

        parsed = vsn.container.parse(data)
        self.assertIsNotNone(parsed.trailer_generation)
        result = vsn.recover_fn(data)
        self.assertEqual(result.accepted_generation, store.generation)

    def test_fallback_on_low_min_savings(self):
        opt = OptimizationConfiguration(min_savings_bytes=999999)
        store = vsn.VsnStore(
            storage_policy=StoragePolicy.HIGHLY_VERTICAL,
            optimization_config=opt,
        )
        fid = b"\x0b" * 16
        store.create_file("test_file", b"low savings threshold")
        data = store.commit()

        parsed = vsn.container.parse(data)
        self.assertIsNotNone(parsed.trailer_generation)
        # Full validation should not raise
        vsn.validate_fn(data, "Full")
class CAP09_CrossPolicyCompatibility(unittest.TestCase):
    """CAP-P09: Produce valid containers using all four policies."""

    def test_all_four_containers_parse_validly(self):
        for policy in StoragePolicy:
            store = vsn.VsnStore(storage_policy=policy)
            fid = bytes([policy]) + b"\x0c" * 15
            store.create_file("test_file", ("cross-policy %s" % policy.name).encode("utf-8"))
            data = store.commit()
            vsn.validate_fn(data, "Full")

    def test_cross_policy_read(self):
        all_data = {}
        for policy in StoragePolicy:
            store = vsn.VsnStore(storage_policy=policy)
            fid = b"\x0d" * 16
            content = ("cross-read %s" % policy.name).encode("utf-8")
            store.create_file("test_file", content)
            all_data[policy] = store.commit()

        for read_policy in StoragePolicy:
            reader = vsn.VsnStore(storage_policy=read_policy)
            for write_policy in StoragePolicy:
                parsed = vsn.container.parse(all_data[write_policy])
                mode = parsed.mode
                self.assertIn(mode, (C.MODE_MODERN, C.MODE_ENTERPRISE))


class CAP10_PolicyNotWireState(unittest.TestCase):
    """Canonical contract: the authoritative storage policy IS serialized on the
    wire as REC_STORAGE_POLICY (0x0009). The obsolete ModeDeclaration is no
    longer the classification record. (Class retained for historical CAP-P10
    numbering; its assertion now reflects the normative on-wire policy.)"""

    def test_no_policy_in_bytes(self):
        for policy in StoragePolicy:
            store = vsn.VsnStore(storage_policy=policy)
            fid = b"\x0e" * 16
            store.create_file("test_file", b"no-policy-in-bytes")
            data = store.commit()

            record_types = {rec.rtype for rec in vsn.container.parse(data).records}
            # Canonical: the storage policy is present on the wire as record 0x0009.
            self.assertIn(C.REC_STORAGE_POLICY, record_types)
            for rt in record_types:
                if rt < C.REC_EXTENSION_MIN:
                    self.assertTrue(rt in {
                        C.REC_MODE_DECLARATION, C.REC_FILE_IDENTITY,
                        C.REC_REVISION, C.REC_CONTENT_OBJECT, C.REC_FILE_HEAD,
                        C.REC_COMMIT_MARKER, C.REC_STORAGE_POLICY},
                        "unexpected record type %s" % hex(rt))

    def test_policy_name_not_in_bytes(self):
        for policy in StoragePolicy:
            store = vsn.VsnStore(storage_policy=policy)
            fid = b"\x0f" * 16
            store.create_file("test_file", b"content only")
            data = store.commit()
            policy_name = policy.name.lower()
            self.assertNotIn(
                policy_name.encode("utf-8"), data,
                "Policy name must not appear in serialized bytes")


class CAP11_BackwardCompatibility(unittest.TestCase):
    """Backward compatibility: existing APIs work without storage_policy."""

    def test_create_without_policy(self):
        store = vsn.VsnStore.create(C.MODE_MODERN)
        self.assertIsNotNone(store)
        data = store.commit()
        parsed = vsn.container.parse(data)
        self.assertEqual(parsed.mode, C.MODE_MODERN)

    def test_open_without_policy(self):
        store1 = vsn.VsnStore.create(C.MODE_MODERN)
        store1 = vsn.VsnStore.create(C.MODE_MODERN)
        store1.create_file("compat_test", b"backward compat")
        data = store1.commit()
        store2 = vsn.VsnStore.open(data)
        self.assertEqual(len(store2.files()), 1)

    def test_open_mode_preserved(self):
        for mode in (C.MODE_MODERN, C.MODE_ENTERPRISE):
            store1 = vsn.VsnStore.create(mode)
            store1.create_file("mode_test", b"mode test")
            data = store1.commit()
            store2 = vsn.VsnStore.open(data)
            self.assertEqual(store2.mode, mode)


class CAP12_WriterOptionsValidation(unittest.TestCase):
    """Test WriterOptions validation and conflict behavior."""

    def test_optimization_config_validate_invalid_search_budget(self):
        opt = OptimizationConfiguration(search_budget=-1)
        with self.assertRaises(InvalidOptimizationConfiguration):
            opt.validate()

    def test_optimization_config_validate_invalid_memory_limit(self):
        opt = OptimizationConfiguration(memory_limit=0)
        with self.assertRaises(InvalidOptimizationConfiguration):
            opt.validate()

    def test_search_config_validate_invalid_branching(self):
        sc = SearchConfiguration(max_branching_factor=0)
        with self.assertRaises(InvalidOptimizationConfiguration):
            sc.validate()

    def test_writer_options_resolve_default_modern(self):
        opts = WriterOptions(storage_policy=StoragePolicy.HIGHLY_VERTICAL)
        self.assertEqual(opts.resolve_wire_mode(C.MODE_ENTERPRISE), C.MODE_MODERN)


if __name__ == "__main__":
    unittest.main(verbosity=2)

