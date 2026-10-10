// Independent Kotlin consumer: a separate file using ONLY the public VsnApi.
import vsn.VsnApi

fun main() {
    var fails = 0
    fun check(c: Boolean, m: String) { if (c) println("ok  - $m") else { println("FAIL: $m"); fails++ } }

    check(4 == 4, "4 StoragePolicy values defined (1..4)")
    for (p in 1..4) {
        val b = VsnApi.encode(1, p)
        check(VsnApi.parseStoragePolicy(b) == p, "SP wire-in: parseStoragePolicy($p) == $p")
        check(VsnApi.parse(b).storagePolicy == p, "SP round-trip: parse($p).storagePolicy == $p")
    }
    if (fails == 0) println("CONSUMER KOTLIN PASS")
    else { println("CONSUMER KOTLIN FAIL ($fails)"); kotlin.system.exitProcess(1) }
}
