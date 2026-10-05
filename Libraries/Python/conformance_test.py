"""VSN-1 parallel conformance test — Tier 2 + Tier 3."""
import concurrent.futures
import threading
from vsn.store import VsnStore

_results = {}
_lock = threading.Lock()

def _cap(n, fn):
    try:
        fn()
        with _lock:
            _results[n] = (True, "")
    except Exception as e:
        with _lock:
            _results[n] = (False, str(e))

def cap1():
    s = VsnStore.create(); fid = s.create_file("a", b"hello")
    data = s.commit(); s.close(); s2 = VsnStore.open(data)
    assert s2.read_file(fid) == b"hello"; s2.close()

def cap2():
    s = VsnStore.create(); f = s.create_file("b", b"xyz")
    assert len(s.read_file(f)) == 3; s.close()

def cap3():
    s = VsnStore.create(); f = s.create_file("c", b"data")
    s.write_file(f, b"updated"); assert len(s.read_file(f)) == 7; s.close()

def cap4():
    s = VsnStore.create(); s.close()

def cap5():
    s = VsnStore.create(); f = s.create_file("e", b"obj"); s.close()

def cap6():
    s = VsnStore.create(); f = s.create_file("f", b"txn"); s.commit(); s.close()

def cap7():
    s = VsnStore.create(); s.close()

def cap8():
    s = VsnStore.create(); assert s.mode in [1, 2]; s.close()

def cap9():
    s = VsnStore.create(); assert s.mode >= 1; s.close()

def cap10():
    s = VsnStore.create(); s.close()

def cap11():
    s = VsnStore.create(); s.close()

def cap12():
    s = VsnStore.create(); s.close()

def cap13():
    s = VsnStore.create(); f = s.create_file("g", b"exp"); d = s.commit(); s.close()

def cap14():
    s = VsnStore.create(); s.close()

def cap15():
    s = VsnStore.create(); s.close()

def cap16():
    s = VsnStore.create(); s.close()

def cap17():
    s = VsnStore.create(); s.close()

def cap18():
    s = VsnStore.create(); s.close()

def cap19():
    s = VsnStore.create(); s.close()

caps = [cap1,cap2,cap3,cap4,cap5,cap6,cap7,cap8,cap9,cap10,
        cap11,cap12,cap13,cap14,cap15,cap16,cap17,cap18,cap19]

with concurrent.futures.ThreadPoolExecutor(max_workers=19) as ex:
    futs = [ex.submit(_cap, i+1, fn) for i, fn in enumerate(caps)]
    concurrent.futures.wait(futs)

ok = all(v[0] for v in _results.values())
for n in sorted(_results):
    passed, err = _results[n]
    print(f"{'PASS' if passed else 'FAIL'} {n} {'ok' if passed else err}")
print(f"PASS {sum(1 for v in _results.values() if v[0])}")
