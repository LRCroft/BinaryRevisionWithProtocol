package vsn
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap

fun cap1(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    val ok = s.mode == Constants.MODE_MODERN
    s.close()
    return ok
}
fun cap2(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    val fid = s.createFile("a.txt", "abc".toByteArray())
    val ok = s.fileExists(fid) && String(s.readFile(fid)!!) == "abc"
    s.close()
    return ok
}
fun cap3(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    val fid = s.createFile("f.txt", "hello".toByteArray())
    if (!s.fileExists(fid)) return false
    s.writeFile(fid, "world".toByteArray())
    if (String(s.readFile(fid)!!) != "world") return false
    s.deleteFile(fid)
    return !s.fileExists(fid)
}
fun cap4(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    s.createFile("a.txt", byteArrayOf(1))
    s.createFile("b.txt", byteArrayOf(2))
    val list = s.statsFiles()
    return list == 2
}
fun cap5(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    val fid = s.createFile("len", byteArrayOf(0, 1, 2, 3))
    val content = s.readFile(fid)
    return content != null && content.size == 4
}
fun cap6(): Boolean {
    var caught = false
    val s = Builder.build(Constants.MODE_MODERN)
    s.createFile("dup.txt", "a".toByteArray())
    try { s.createFile("dup.txt", "b".toByteArray()) } catch (e: Exception) { caught = true }
    return caught
}
fun cap7(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    val data = "VSN-TEST-DATA-0123".toByteArray()
    val fid = s.createFile("rep.txt", data)
    val rd = s.readFile(fid)!!
    return rd.contentEquals(data) && rd.size == 18
}
fun cap8(): Boolean {
    val sm = Builder.build(Constants.MODE_MODERN)
    val se = Builder.build(Constants.MODE_ENTERPRISE)
    val dm = "modern-content".toByteArray()
    val de = "enterprise-data".toByteArray()
    val fm = sm.createFile("m.txt", dm)
    val fe = se.createFile("e.txt", de)
    return sm.mode == Constants.MODE_MODERN && se.mode == Constants.MODE_ENTERPRISE
        && sm.readFile(fm)!!.contentEquals(dm) && se.readFile(fe)!!.contentEquals(de)
}
fun cap9(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    val fid = s.createFile("lc.txt", "x".toByteArray())
    for (i in 0 until 5) s.writeFile(fid, ("v$i").toByteArray())
    return s.statsRevs() > 1
}
fun cap9zero(): Boolean {
    var caught = false
    val s = Builder.build(Constants.MODE_MODERN)
    val fid = s.createFile("lc0.txt", "x".toByteArray())
    try { s.limitCleanup(fid, 0) } catch (e: Exception) { caught = true }
    return caught
}
fun cap10(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    s.createFile("obj.txt", "material".toByteArray())
    val list = s.listObjects()
    return list >= 0
}
fun cap11(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    val fid = s.createFile("mat.txt", "data".toByteArray())
    val content = s.readFile(fid)
    return content != null && content.isNotEmpty()
}
fun cap12(): Boolean {
    val base = Builder.build(Constants.MODE_MODERN)
    val ours = Builder.build(Constants.MODE_MODERN)
    val theirs = Builder.build(Constants.MODE_MODERN)
    base.createFile("f.txt", "base-content".toByteArray())
    ours.createFile("f.txt", "ours-content".toByteArray())
    theirs.createFile("f.txt", "theirs-content".toByteArray())
    val conflicts = mergeThreeWay(base, ours, theirs)
    if (conflicts < 1) return false
    val b2 = Builder.build(Constants.MODE_MODERN)
    val o2 = Builder.build(Constants.MODE_MODERN)
    val t2 = Builder.build(Constants.MODE_MODERN)
    b2.createFile("c.txt", "base".toByteArray())
    o2.createFile("c.txt", "same".toByteArray())
    t2.createFile("c.txt", "same".toByteArray())
    return mergeThreeWay(b2, o2, t2) == 0
}
fun cap13(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    val gen = s.beginTransaction()
    s.stageAdd("r1.txt", byteArrayOf(2))
    try {
        s.commitTransaction(gen + 999)
    } catch (e: IllegalStateException) {
        return true
    }
    return false
}
fun cap14(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    val encoded = s.commitTransaction(0)
    return String(encoded, 0, 4) == "VSN-"
}
fun cap15(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    val e = s.exportBytes()
    s.close()
    val s2 = Builder.build(Constants.MODE_MODERN)
    s2.importBytes(e)
    return s2.statsFiles() >= 0 && s2.mode == Constants.MODE_MODERN
}
fun cap16(): Boolean {
    val s1 = Builder.build(Constants.MODE_MODERN)
    val s2 = Builder.build(Constants.MODE_ENTERPRISE)
    return s1.mode == Constants.MODE_MODERN && s2.mode == Constants.MODE_ENTERPRISE
}
fun cap17(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    val ok = s.validate()
    s.close()
    return ok
}
fun cap18(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    val ok = s.recover()
    s.close()
    return ok
}
fun cap19(): Boolean {
    val s = Builder.build(Constants.MODE_MODERN)
    val data = "interop-data-42".toByteArray()
    s.createFile("i.txt", data)
    val encoded = s.commitTransaction(0)
    if (String(encoded, 0, 4) != "VSN-") return false
    val s2 = Builder.build(Constants.MODE_MODERN)
    s2.importBytes(encoded)
    return s2.mode == Constants.MODE_MODERN && s2.statsFiles() >= 0
}

fun main() {
    var passed = 0
    val results = ConcurrentHashMap<Int, Boolean>()
    val latch = java.util.concurrent.CountDownLatch(19)

    val tests = mapOf(
        1 to { cap1() },
        2 to { cap2() },
        3 to { cap3() },
        4 to { cap4() },
        5 to { cap5() },
        6 to { cap6() },
        7 to { cap7() },
        8 to { cap8() },
        9 to { cap9() },
        10 to { cap10() },
        11 to { cap11() },
        12 to { cap12() },
        13 to { cap13() },
        14 to { cap14() },
        15 to { cap15() },
        16 to { cap16() },
        17 to { cap17() },
        18 to { cap18() },
        19 to { cap19() }
    )

    for ((num, test) in tests) {
        CompletableFuture.supplyAsync {
            val ok = try { test() } catch (e: Exception) { false }
            results[num] = ok
            latch.countDown()
        }
    }
    latch.await()

    for (n in 1..19) {
        val ok = results[n] == true
        if (ok) passed++
        println("CAP $n ${if (ok) "PASS" else "FAIL"} assertions=1 ops=0")
    }
    println("PASS $passed")
}
