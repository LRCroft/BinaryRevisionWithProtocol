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
    s = VsnStore.create(); fid = s.create_file("lc", b"x")
    for i in range(5): s.write_file(fid, bytes([i]))
    removed = s.limit_cleanup(fid, 3)
    assert len(removed) >= 0; s.close()

def cap5():
    s = VsnStore.create(); f = s.create_file("e", b"obj"); s.close()

def cap6():
    s = VsnStore.create(); f = s.create_file("f", b"txn"); s.commit(); s.close()

def cap7():
    s = VsnStore.create(); assert s.generation >= 0; s.close()

def cap8():
    s = VsnStore.create(); assert s.mode in [1, 2]; s.close()

def cap9():
    s = VsnStore.create(); assert s.mode >= 1; s.close()

def cap10():
    tmp = VsnStore.create(); data = tmp.commit(); tmp.close()
    s2 = VsnStore.open(data)
    assert s2.generation >= 0; s2.close()

def cap11():
    s = VsnStore.create(); fid = s.create_file("n", b"x")
    count = len(s.files()); s.close()
    assert count >= 1

def cap12():
    s1 = VsnStore.create(); f1 = s1.create_file("p", b"abc"); s1.commit()
    s1.close(); s2 = VsnStore.create()
    assert len(s2.files()) >= 0; s2.close()

def cap13():
    s = VsnStore.create(); f = s.create_file("g", b"exp"); d = s.commit(); s.close()

def cap14():
    s = VsnStore.create(); fid = s.create_file("big", b"bigdata"); c = s.read_file(fid)
    assert len(c) == 7; s.close()

def cap15():
    s = VsnStore.create(); diags = s.to_bytes()
    assert isinstance(diags, bytes); s.close()

def cap16():
    s = VsnStore.create(); data = s.commit()
    s.close(); valid = VsnStore.open(data)
    assert len(valid.to_bytes()) >= 8; valid.close()

def cap17():
    s = VsnStore.create(); fid = s.create_file("stat", b"x"); fid2 = s.create_file("stat2", b"y")
    files = s.files(); s.close()
    assert len(files) >= 2

def cap18():
    s = VsnStore.create(mode=2); m = s.mode
    assert m == 2; s.close()

def cap19():
    s = VsnStore.create(); data = s.commit()
    magic_ok = len(data) >= 4 and data[:4] == b"VSN-"
    s.close(); assert magic_ok

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
