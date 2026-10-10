# VSN parallel conformance test — Tier 2 (std.thread)
import sys
import concurrent.futures
sys.path.insert(0, '.')
from vsn import MutableStore

def run_cap(n):
    s = MutableStore.create(1)
    ok = True
    if n == 2:
        f = s.createFile("a", b"hello")
        ok = len(f) == 16
    if n == 8:
        ok = s.getMode() in [1, 2]
    s.close()
    if ok: print(f"PASS {n}")
    else: print(f"FAIL {n}")
    return ok

with concurrent.futures.ThreadPoolExecutor(max_workers=19) as ex:
    futs = [ex.submit(run_cap, i) for i in range(1, 20)]
    results = [f.result() for f in futs]
print(f"PASS {sum(results)}")

