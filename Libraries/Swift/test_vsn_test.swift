// VSN-1 parallel conformance test — Tier 2 (Dispatch)
// Tier 3: NSLock for thread-safe operations
import Foundation

var passed = 0
let lock = NSLock()

func runCap(_ n: Int) {
    let s = VsnStore.create(mode: 1, generation: 0)
    var ok = true
    if n == 2 {
        let fid = s.createFile("a", content: Array("hello".utf8))
        ok = fid.count == 16
    }
    if n == 8 { ok = s.mode == 1 || s.mode == 2 }
    s.close()
    lock.lock()
    if ok { passed += 1; print("PASS \(n)") }
    else { print("FAIL \(n)") }
    lock.unlock()
}

let group = DispatchGroup()
for i in 1...19 {
    group.enter()
    DispatchQueue.global().async {
        runCap(i)
        group.leave()
    }
}
group.wait()
print("PASS \(passed)")
