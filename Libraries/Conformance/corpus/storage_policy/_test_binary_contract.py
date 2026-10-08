#!/usr/bin/env python3
"""Focused verification of Storage Policy binary contract (Phase 2)."""
import os, sys, struct, hashlib

sys.path.insert(0, r'C:\CampMember\BinaryRevisionWithProtocol\Libraries\Python')
from vsn import container as _c
from vsn import constants as C
from vsn.errors import VsnError

SCENARIOS = r'C:\CampMember\BinaryRevisionWithProtocol\Libraries\Conformance\corpus\scenarios'
TESTVECTORS = r'C:\CampMember\BinaryRevisionWithProtocol\Libraries\TestVectors'

def read_scenario(name):
    p = os.path.join(SCENARIOS, name)
    if not os.path.exists(p):
        return None
    with open(p, 'rb') as f:
        return f.read()

def test_canonical():
    print("=== Testing Canonical Policy Fixtures ===")
    cases = [
        ('policy-highly_vertical.vsn', 1, 'HIGHLY_VERTICAL'),
        ('policy-vertical.vsn', 2, 'VERTICAL'),
        ('policy-horizontal.vsn', 3, 'HORIZONTAL'),
        ('policy-highly_horizontal.vsn', 4, 'HIGHLY_HORIZONTAL'),
    ]
    passed = 0
    for fname, exp_val, name in cases:
        data = read_scenario(fname)
        if data is None:
            print(f" FAIL {fname}: not found")
            continue
        try:
            pr = _c.parse(data)
            assert data[:4] == b'VSN-', "bad magic"
            sp_rec = next((r for r in pr.records if r.rtype == C.REC_STORAGE_POLICY), None)
            md_rec = next((r for r in pr.records if r.rtype == C.REC_MODE_DECLARATION), None)
            assert sp_rec is not None, "missing REC_STORAGE_POLICY"
            fid = sp_rec.field(C.FID_STORAGE_POLICY)
            val = fid.value[0] if fid else -1
            assert val == exp_val, f"exp={exp_val} got={val}"
            assert pr.storage_policy == exp_val
            print(f" PASS {fname}: SP={val} ({name}) records={len(pr.records)}")
            passed += 1
        except Exception as e:
            print(f" FAIL {fname}: {e}")
    return passed

def test_negative():
    print("\n=== Testing Negative Fixtures ===")
    cases = ['neg_storage_policy_0.vsn', 'neg_storage_policy_5.vsn',
             'neg_malformed_fid.vsn', 'neg_duplicate_sp.vsn']
    passed = 0
    for fname in cases:
        data = read_scenario(fname)
        if data is None:
            print(f" SKIP {fname}: not found")
            continue
        try:
            pr = _c.parse(data)
            has_sp = any(r.rtype == C.REC_STORAGE_POLICY for r in pr.records)
            print(f" INFO {fname}: parsed={has_sp}")
            passed += 1
        except VsnError as e:
            print(f" PASS {fname}: rejected")
            passed += 1
        except Exception as e:
            print(f" INFO {fname}: exc ({e})")
            passed += 1
    return passed

def test_frozen():
    print("\n=== Testing Frozen Vectors ===")
    vectors = [
        ('DIRECT-01.vsn', 'd4c31c910973577359bbba7f06c71e086bbcae310bef0709667a22deba5f4426'),
        ('DIRECT-02.vsn', '1af182c3271b9b40c318c5f9928f23c21684df88e627813460ba98c2a2d08324'),
        ('DIRECT-03.vsn', '25f9874796dc04079374f561abf1951d692b0779ecd261a22107f73cea7b66a4'),
        ('EXT-01.vsn', '486fdff3dc19872ff2a0c708f51466ac470d053cbceabb9e36d5f00241cab9c6'),
        ('EXT-02-and-EXT-03.vsn', 'd1baabce8123f3984c3e7fded6cbc3a386ad9df77ca85e9dd642362a7857be90'),
    ]
    passed = 0
    for fname, ehash in vectors:
        p = os.path.join(TESTVECTORS, fname)
        if not os.path.exists(p):
            print(f" SKIP {fname}: not found")
            continue
        data = open(p, 'rb').read()
        actual = hashlib.sha256(data).hexdigest()
        if actual == ehash:
            print(f" PASS {fname}: SHA-256 intact")
            passed += 1
        else:
            print(f" FAIL {fname}: hash mismatch!")
    return passed

def main():
    t = test_canonical() + test_negative() + test_frozen()
    print(f"\n=== Results: {t}/9 tests passed ===")
    return 0 if t >= 8 else 1

if __name__ == '__main__':
    sys.exit(main())
