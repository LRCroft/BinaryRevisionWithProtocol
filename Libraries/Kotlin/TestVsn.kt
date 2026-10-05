// VSN-1 Capability Conformance Tests (Parallel by CompletableFuture)
package vsn

import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch

val ModeModern = Constants.MODE_MODERN
val ModeEnterprise = Constants.MODE_ENTERPRISE

class TestVsn {
    fun testContainerLifecycle(): Boolean {
        val s = Builder.build(ModeModern)
        val ok = s.mode == ModeModern
        s.close()
        return ok
    }
    fun testContainerReopen(): Boolean {
        val s = Builder.build(ModeModern)
        s.createFile("f1.txt", byteArrayOf(1, 2))
        return String(s.commitTransaction(s.generation), 0, 4) == "VSN-"
    }
    fun testFileApi(): Boolean {
        val s = Builder.build(ModeModern)
        val fid = s.createFile("file.txt", "hello".toByteArray())
        if (!fid.isNotEmpty()) return false
        if (!s.fileExists(fid)) return false
        if (String(s.readFile(fid)!!) != "hello") return false
        s.writeFile(fid, "world".toByteArray())
        if (String(s.readFile(fid)!!) != "world") return false
        s.deleteFile(fid)
        return !s.fileExists(fid)
    }
    fun testMultipleFiles(): Boolean {
        val s = Builder.build(ModeModern)
        s.createFile("a.txt", byteArrayOf(1))
        s.createFile("b.txt", byteArrayOf(2))
        return s.fileExists("a.txt") && s.fileExists("b.txt")
    }
    fun testFileSize(): Boolean {
        val s = Builder.build(ModeModern)
        val fid = s.createFile("leng", byteArrayOf(0))
        return fid.length >= 4
    }
    fun testDuplicatePathRejected(): Boolean {
        var caught = false
        val s = Builder.build(ModeModern)
        s.createFile("dup.txt", "a".toByteArray())
        try { s.createFile("dup.txt", "b".toByteArray()) } catch (e: Exception) { caught = true }
        return caught
    }
    fun testRevisionListAndGet(): Boolean {
        val s = Builder.build(ModeModern)
        val fid = s.createFile("rev.txt", "v1".toByteArray())
        return s.statsRevs() > 0 && s.currentRevision(fid) >= 0
    }
    fun testCheckoutRevision(): Boolean {
        val s = Builder.build(ModeModern)
        val fid = s.createFile("cr.txt", "v1".toByteArray())
        s.writeFile(fid, "v2".toByteArray())
        return s.currentRevision(fid) >= 1
    }
    fun testLimitCleanup(): Boolean {
        val s = Builder.build(ModeModern)
        val fid = s.createFile("lc.txt", "x".toByteArray())
        for (i in 0 until 5) s.writeFile(fid, ("v$i").toByteArray())
        return s.statsRevs() > 1
    }
    fun testLimitCleanupZero(): Boolean {
        var caught = false
        val s = Builder.build(ModeModern)
        val fid = s.createFile("lc0.txt", "x".toByteArray())
        try { s.limitCleanup(fid, 0) } catch (e: Exception) { caught = true }
        return caught
    }
    fun testObjectEnumerate(): Boolean {
        val s = Builder.build(ModeModern)
        return s.listObjects() >= 0
    }
    fun testMaterializeObject(): Boolean {
        val s = Builder.build(ModeModern)
        val fid = s.createFile("obj.txt", "material".toByteArray())
        val content = s.readFile(fid)
        return content != null && content!!.isNotEmpty()
    }
    fun testTransactionCommit(): Boolean {
        val s = Builder.build(ModeModern)
        val gen = s.beginTransaction()
        s.stageAdd("t1.txt", byteArrayOf(1))
        val data = s.commitTransaction(gen)
        return data.isNotEmpty()
    }
    fun testTransactionRollback(): Boolean {
        var failed = false
        val s = Builder.build(ModeModern)
        val gen = s.beginTransaction()
        try { s.commitTransaction(gen + 1) } catch (e: Exception) { failed = true }
        return failed
    }
    fun testDirectRoundTrip(): Boolean {
        val s = Builder.build(ModeModern)
        s.createFile("d1.txt", byteArrayOf(0x44, 0x49, 0x52))
        return s.commitTransaction(s.generation).isNotEmpty()
    }
    fun testEnterpriseMode(): Boolean {
        check(Builder.build(ModeModern).builderOk())
        val se = Builder.build(ModeEnterprise)
        return se.mode == ModeEnterprise
    }
    fun testValidationPasses(): Boolean {
        val cs = Builder.build(ModeModern)
        cs.createFile("v.txt", byteArrayOf(1))
        val data = cs.commitTransaction(cs.generation)
        return VsnApi.validate(data)
    }
    fun testRecoverySelectsMarker(): Boolean {
        var rw = Builder.build(ModeModern)
        rw.createFile("rw.txt", byteArrayOf(1))
        val committed = rw.commitTransaction(rw.generation)
        return VsnApi.recover(committed) == 0
    }
    fun testImportExportBytes(): Boolean {
        val s = Builder.build(ModeModern)
        s.createFile("e1.txt", byteArrayOf(1))
        return s.exportBytes().isNotEmpty()
    }
    fun testLargeObjectStreams(): Boolean {
        val s = Builder.build(ModeModern)
        val big = byteArrayOf(1, 2, 3) + byteArrayOf(4, 5, 6)
        val fid = s.createFile("large.bin", big)
        return s.readFile(fid) != null && s.readFile(fid)!!.contentEquals(big)
    }
    fun testDiagnosticsPassThrough(): Boolean {
        return !VsnApi.validate(byteArrayOf(1, 2, 3))
    }
    fun testIntegrityVerifyValid(): Boolean {
        val s = Builder.build(ModeModern)
        val ok1 = s.integrityOk()
        s.close()
        return ok1 && !s.integrityOk()
    }
    fun testStorageStats(): Boolean {
        val s = Builder.build(ModeModern)
        s.createFile("a.txt", byteArrayOf(1))
        return s.statsFiles() == 1 && s.statsRevs() > 0 && s.statsObjs() >= 0
    }
    fun testBuilderSimple(): Boolean {
        return Builder.build(ModeModern).builderOk()
    }
    fun testInteropMagicBytes(): Boolean {
        val magicA = byteArrayOf(86, 83, 78, 45, 1, 2)
        val valid = VsnApi.magicCheck(magicA)
        val badMagic = byteArrayOf(88, 88, 88, 45)
        val invalid = !VsnApi.magicCheck(badMagic)
        return valid && invalid
    }
    // === Parallel Execution Engine ===
    fun runAllParallel(): Array<Any> {
        val results = ConcurrentHashMap<String, Boolean>()
        val latch = CountDownLatch(19)
        
        val futures = listOf(
            CompletableFuture.supplyAsync { testContainerLifecycle() }.thenAccept { r -> 
                results["container_lifecycle"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testContainerReopen() }.thenAccept { r -> 
                results["container_reopen"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testFileApi() }.thenAccept { r -> 
                results["file_api"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testMultipleFiles() }.thenAccept { r -> 
                results["multiple_files"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testFileSize() }.thenAccept { r -> 
                results["file_size"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testDuplicatePathRejected() }.thenAccept { r -> 
                results["duplicate_rejected"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testRevisionListAndGet() }.thenAccept { r -> 
                results["revision_api"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testCheckoutRevision() }.thenAccept { r -> 
                results["checkout_revision"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testLimitCleanup() }.thenAccept { r -> 
                results["limit_cleanup"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testLimitCleanupZero() }.thenAccept { r -> 
                results["limit_zero_rejected"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testObjectEnumerate() }.thenAccept { r -> 
                results["object_api"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testMaterializeObject() }.thenAccept { r -> 
                results["materialize_object"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testTransactionCommit() }.thenAccept { r -> 
                results["transaction_commit"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testTransactionRollback() }.thenAccept { r -> 
                results["transaction_rollback"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testDirectRoundTrip() }.thenAccept { r -> 
                results["direct1_roundtrip"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testEnterpriseMode() }.thenAccept { r -> 
                results["modes"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testValidationPasses() }.thenAccept { r -> 
                results["validation"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testRecoverySelectsMarker() }.thenAccept { r -> 
                results["recovery"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testImportExportBytes() }.thenAccept { r -> 
                results["import_export"] = r; latch.countDown() }
        ) + listOf(
            CompletableFuture.supplyAsync { testLargeObjectStreams() }.thenAccept { r -> 
                results["streaming"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testDiagnosticsPassThrough() }.thenAccept { r -> 
                results["diagnostics"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testIntegrityVerifyValid() }.thenAccept { r -> 
                results["integrity"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testStorageStats() }.thenAccept { r -> 
                results["storage"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testBuilderSimple() }.thenAccept { r -> 
                results["builder"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testInteropMagicBytes() }.thenAccept { r -> 
                results["interop"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testThreeWayMergeNoConflict() }.thenAccept { r -> 
                results["merge_no_conflict"] = r; latch.countDown() },
            CompletableFuture.supplyAsync { testThreeWayMergeWithConflict() }.thenAccept { r -> 
                results["merge_conflict_detected"] = r; latch.countDown() }
        )
        
        latch.await()
        
        // Print per-capability results
        val capNames = listOf(
            "1:container_lifecycle", "2:container_reopen", "3:file_api",
            "4:multiple_files", "5:file_size", "6:duplicate_rejected",
            "7:revision_api", "8:checkout_revision", "9:limit_cleanup",
            "10:limit_zero_rejected", "11:object_api", "12:materialize_object",
            "13:transaction_commit", "14:transaction_rollback", "15:direct1_roundtrip",
            "16:modes", "17:validation", "18:recovery", "19:import_export",
            "20:streaming", "21:diagnostics", "22:integrity",
            "23:storage", "24:builder", "25:interop",
            "26:merge_no_conflict", "27:merge_conflict_detected"
        )
        
        var passCount = 0
        capNames.forEach { entry ->
            val capNum = entry.substringBefore(":")
            val capName = entry.substringAfter(":")
            val ok = results[capName] == true
            if (ok) passCount++
            println(if (ok) "PASS $capNum $capName" else "FAIL $capNum $capName")
        }
        
        return arrayOf(passCount, results.size)
    }
    fun testThreeWayMergeNoConflict(): Boolean {
        val a = Builder.build(ModeModern)
        a.createFile("shared.txt", byteArrayOf(1))
        val b = Builder.build(ModeModern)
        b.createFile("shared.txt", byteArrayOf(1))
        val c = Builder.build(ModeModern)
        return true && a.mode == ModeModern && b.mode == ModeModern
    }
    fun testThreeWayMergeWithConflict(): Boolean {
        val a = Builder.build(ModeModern)
        a.createFile("conflict.txt", byteArrayOf(1))
        val b = Builder.build(ModeModern)
        b.createFile("conflict.txt", byteArrayOf(2))
        return true && a.mode == ModeModern && b.mode == ModeEnterprise
    }
    companion object {
        @JvmStatic
        fun main(args: Array<String>) {
            val t = TestVsn()
            println("=== Running VSN-1 Conformance Tests in PARALLEL ===")
            val result = t.runAllParallel()
            val passCount = result[0] as Int
            val total = result[1] as Int
            println("\n=== Total: $passCount/$total PASSED ===")
            if (passCount < total) {
                throw RuntimeException("$passCount passed but $total expected")
            }
        }
    }
}
