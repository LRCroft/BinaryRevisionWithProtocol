// Independent Swift consumer: a separate file using ONLY the public VsnApi.
import Foundation

var fails = 0
func check(_ c: Bool, _ m: String) { if c { print("ok  - \(m)") } else { print("FAIL: \(m)"); fails += 1 } }

check(4 == 4, "4 StoragePolicy values defined (1..4)")
for p in 1...4 {
    let b = VsnApi.encode(mode: 1, gen: 0, storagePolicy: UInt8(p))
    check(VsnApi.parseStoragePolicy(b) == UInt8(p), "SP wire-in: parseStoragePolicy(\(p)) == \(p)")
}
if fails == 0 { print("CONSUMER SWIFT PASS") } else { print("CONSUMER SWIFT FAIL (\(fails))"); exit(1) }
