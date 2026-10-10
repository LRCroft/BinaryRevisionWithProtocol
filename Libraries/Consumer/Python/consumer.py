"""Independent Python consumer: locates the `vsn` package and uses ONLY the public API.

NOTE: the `vsn` package has no pyproject.toml/setup.py, so it is not pip-installable;
this consumer wires it onto sys.path (packaging gap documented in the audit).
"""
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "Python"))
sys.path.insert(0, ROOT)
import vsn  # noqa: E402

fails = 0

def check(cond, msg):
    global fails
    if cond:
        print("ok  - " + msg)
    else:
        print("FAIL: " + msg)
        fails += 1

s = vsn.VsnStore.create()
check(s is not None, "VsnStore.create")
fid = s.create_file("py.txt", b"PY-CONSUMER")
check(s.file_exists(fid), "create_file + file_exists")
check(s.read_file(fid) == b"PY-CONSUMER", "read_file round-trips")
s.write_file(fid, b"PY-CONSUMER-2")
check(len(s.list_revisions(fid)) >= 1, "revision tracked")
data = s.to_bytes()
check(len(data) > 0, "to_bytes produced canonical bytes")
check(vsn.validate_container(data, "Full") == [], "validate_container (Full) clean")
rec = vsn.recover_container(data)
check(rec is not None, "recover_container returns a result")
check(vsn.StoragePolicy.VERTICAL == 2, "StoragePolicy values (1..4)")
check(vsn.VsnStore.create(vsn.constants.MODE_ENTERPRISE) is not None, "create(ENTERPRISE)")

# Storage Policy wire-in: public create-with-policy -> to_bytes -> public parse -> policy read back.
from vsn import container as _container
check(int(vsn.StoragePolicy.HIGHLY_VERTICAL) == 1 and int(vsn.StoragePolicy.VERTICAL) == 2
      and int(vsn.StoragePolicy.HORIZONTAL) == 3 and int(vsn.StoragePolicy.HIGHLY_HORIZONTAL) == 4,
      "4 canonical policy values 1..4")
_ok = True
for pol, exp in ((vsn.StoragePolicy.HIGHLY_VERTICAL, 1), (vsn.StoragePolicy.VERTICAL, 2),
                 (vsn.StoragePolicy.HORIZONTAL, 3), (vsn.StoragePolicy.HIGHLY_HORIZONTAL, 4)):
    st = vsn.VsnStore(storage_policy=pol)
    st.create_file("py.txt", b"POL")
    got = _container.parse(st.to_bytes()).storage_policy
    if got != exp:
        _ok = False
        break
check(_ok, "SP wire-in: all 4 policies round-trip through public parse")
b1 = vsn.VsnStore(storage_policy=vsn.StoragePolicy.HORIZONTAL).to_bytes()
b2 = vsn.VsnStore(storage_policy=vsn.StoragePolicy.HIGHLY_VERTICAL).to_bytes()
check(len(b1) > 0 and len(b2) > 0 and b1 != b2, "distinct policies -> distinct wire bytes")

print("CONSUMER PYTHON PASS" if fails == 0 else "CONSUMER PYTHON FAIL (%d)" % fails)
sys.exit(0 if fails == 0 else 1)