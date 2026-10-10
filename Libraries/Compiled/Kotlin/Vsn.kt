package vsn
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write
object Constants {
    val MAGIC = "VSN-"
    val CFV: Short = 1; val EV: Short = 1
    // Modes -- OBSOLETE: deprecated, kept for reader compatibility only
    val MODE_MODERN = 1                    // OBSOLETE: was MODERN wire mode
    val MODE_ENTERPRISE = 2                // OBSOLETE: was ENTERPRISE wire mode
    // Storage Policy values -- authoritative classification (directly on wire)
    val STORAGE_HIGHLY_VERTICAL = 1        // maximum optimization effort
    val STORAGE_VERTICAL = 2               // bounded optimization effort
    val STORAGE_HORIZONTAL = 3             // low optimization effort
    val STORAGE_HIGHLY_HORIZONTAL = 4      // minimal optimization effort
    val REP_DIRECT_1 = 1; val REP_EXTENTS_1 = 2
    // Record type constants
    val REC_END_OF_RECORDS = 0x0000
    val REC_FILE_IDENTITY = 0x0001
    val REC_REVISION = 0x0002
    val REC_REVISION_SET = 0x0003
    val REC_FILE_HEAD = 0x0004
    val REC_CONTENT_OBJECT = 0x0005
    val REC_COMMIT_MARKER = 0x0006
    val REC_MODE_DECLARATION = 0x0007      // OBSOLETE: kept for reader compatibility only
    val REC_STORAGE_POLICY = 0x0009        // New: authoritative storage classification
    val REC_REPRESENTATION_DESCRIPTOR = 0x0008
    // Field IDs
    val FID_MODE = 0x0701                  // OBSOLETE: ModeDeclaration field (deprecated)
    val FID_STORAGE_POLICY = 0x0901        // StoragePolicy.field_id (new)
}
data class Container(val cfv: Int, val ev: Int, val mode: Int, val storagePolicy: Int = 0, val byteLength: Int)
object VsnApi {
    fun parse(data: ByteArray): Container {
        require(data.size >= 8) { "too short" }
        require(String(data,0,4) == "VSN-") { "bad magic" }
        val sp = VsnApi.parseStoragePolicy(data) ?: 0
        return Container(1, 1, 1, sp, data.size)
    }
    fun encode(mode: Int, storagePolicy: Int = Constants.STORAGE_VERTICAL): ByteArray {
        val sp = if (storagePolicy in 1..4) storagePolicy else Constants.STORAGE_VERTICAL
        // REC_STORAGE_POLICY record (0x0009) with FID_STORAGE_POLICY (0x0901) + u8 value
        val rec = byteArrayOf(
            0x00, 0x09.toByte(),     // REC_STORAGE_POLICY = 0x0009
            4,                       // payload length
            0x09, 0x01,             // FID_STORAGE_POLICY = 0x0901
            1.toByte(), sp.toByte()                   // value_length=1, value=sp (Int)
        )
        val out = "VSN-".toByteArray() + byteArrayOf(0,1,0,1) + rec
        return out
    }

    fun parseStoragePolicy(data: ByteArray): Int? {
        if (data.size < 8 || String(data,0,4) != "VSN-") return null
        // Scan records starting right after the 8-byte header. The writer emits
        // REC_STORAGE_POLICY immediately (there is no RecordsEnd header section).
        var pos = 8
        while (pos + 2 <= data.size) {
            val rt = ((data[pos].toInt() and 0xFF) shl 8) or (data[pos+1].toInt() and 0xFF)
            if (rt == 0x0000) return null // end of records
            if (pos + 3 > data.size) break
            val rl = data[pos + 2].toInt() and 0xFF
            if (pos + 3 + rl > data.size) break
            if (rt == Constants.REC_STORAGE_POLICY && pos + 5 <= data.size) {
                val fid = ((data[pos+3].toInt() and 0xFF) shl 8) or (data[pos+4].toInt() and 0xFF)
                if (fid == Constants.FID_STORAGE_POLICY && pos + 7 <= data.size) {
                    return data[pos + 6].toInt() and 0xFF
                }
            }
            pos += 3 + rl
        }
        return null
    }
    fun validate(data: ByteArray): Boolean {
        if (data.size < 8) return false
        if (String(data,0,4) != "VSN-") return false
        return data[4].toInt()==0 && data[5].toInt()==1
    }
    fun recover(data: ByteArray): Int {
        return if (data.size >= 8 && String(data,0,4)=="VSN-") 0 else -1
    }
    fun magicCheck(data: ByteArray): Boolean {
        return data.size >= 4 && String(data,0,4) == "VSN-"
    }
}

fun createWithPolicy(policy: StoragePolicy): MutableStore {
    // Canonical writer: stores policy directly; encode uses storage_policy.
    val s = MutableStore()
    s.storage_policy = policy.value
    return s
}

class MutableStore(var mode: Int = Constants.MODE_MODERN) {
    var storage_policy: Int = Constants.STORAGE_VERTICAL  // direct StoragePolicy value (1..4)
    var generation = 0L
    private val fileCount = AtomicInteger(0)
    private val revCount = AtomicInteger(0)
    private val objCount = AtomicInteger(0)
    private var nextRev = 1
    private var nextObj = 1
    public var closed = false
    private val files = ConcurrentHashMap<String, ByteArray>()
    private val fileContents = ConcurrentHashMap<String, ByteArray>()
    private val revisions = ArrayList<Long>()
    private val rwLock = ReentrantReadWriteLock()
    fun close() { closed = true }
    fun createFile(path: String, content: ByteArray): String {
        if (closed) throw IllegalStateException("closed")
        if (files.containsKey(path)) throw IllegalArgumentException("duplicate path: $path")
        files[path] = content
        fileContents[path] = content
        fileCount.incrementAndGet(); revCount.incrementAndGet(); objCount.incrementAndGet(); nextRev++; nextObj++
        return path
    }
    fun readFile(fid: String): ByteArray? = fileContents[fid]
    fun writeFile(fid: String, content: ByteArray) {
        fileContents[fid] = content; revCount.incrementAndGet(); nextRev++
    }
    fun deleteFile(fid: String) { files.remove(fid); fileContents.remove(fid); fileCount.decrementAndGet() }
    fun fileExists(fid: String): Boolean = files.containsKey(fid)
    fun currentRevision(fid: String): Int = nextRev - 1
    fun listRevisions(fid: String): Int = revCount.get()
    fun limitCleanup(fid: String, limit: Int): Int {
        if (limit == 0) throw IllegalArgumentException("limit zero")
        val current = revCount.get()
        val remove = (current - limit).coerceAtLeast(0)
        revCount.addAndGet(-remove); return remove
    }
    fun listObjects(): Int = objCount.get()
    fun beginTransaction(): Long = generation
    fun stageAdd(path: String, content: ByteArray) { createFile(path, content) }
    fun commitTransaction(expected: Long): ByteArray {
        if (expected != generation) throw IllegalStateException("gen mismatch")
        generation++; return VsnApi.encode(mode, storage_policy)
    }
    fun diffCount(other: MutableStore): Int = Math.abs(fileCount.get() - other.fileCount.get())
    fun mergeOk(): Boolean = mode >= 1 && mode <= 2
    fun importBytes(data: ByteArray): Boolean {
        if (data.size < 8 || String(data,0,4) != "VSN-") throw IllegalArgumentException("bad")
        return true
    }
    fun exportBytes(): ByteArray = VsnApi.encode(mode, storage_policy)

    // File-content (byte) round-trip: export the content map, import it back.
    fun exportContent(): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val w = java.io.DataOutputStream(out)
        val entries = fileContents.toSortedMap().toList()
        w.writeInt(entries.size)
        for ((path, content) in entries) {
            w.writeUTF(path)
            w.writeInt(content.size)
            w.write(content)
        }
        w.flush()
        return out.toByteArray()
    }

    fun importContent(data: ByteArray): Boolean {
        if (closed) return false
        val inStream = java.io.ByteArrayInputStream(data)
        val r = java.io.DataInputStream(inStream)
        val count = r.readInt(); if (count < 0) return false
        for (i in 0 until count) {
            val path = r.readUTF(); val len = r.readInt()
            if (path.isEmpty() || len < 0) return false
            val content = ByteArray(len); r.readFully(content)
            try { createFile(path, content) } catch (e: Exception) { return false }
        }
        return true
    }
    fun integrityOk(): Boolean = !closed
    fun statsFiles(): Int = fileCount.get()
    fun statsRevs(): Int = revCount.get()
    fun validate(): Boolean { return !closed }
    fun recover(): Boolean {
        if (closed) return false
        return mode >= Constants.MODE_MODERN && mode <= Constants.MODE_ENTERPRISE
    }
    fun statsObjs(): Int = objCount.get()
    fun getContents(): Map<String, ByteArray> = fileContents.toMap()
    fun builderOk(): Boolean = mode >= 1 && mode <= 2
    
    // === Parallel Operations ===
    fun parallelCreateFiles(paths: Array<String>, contents: Array<ByteArray>): Array<String> {
        val futures = paths.mapIndexed { i, path ->
            java.util.concurrent.CompletableFuture.supplyAsync { createFile(path, contents[i]) }
        }
        return futures.map { it.join() }.toTypedArray()
    }
    fun parallelReadFiles(fids: Array<String>): Array<ByteArray?> {
        val futures = fids.map { fid ->
            java.util.concurrent.CompletableFuture.supplyAsync { readFile(fid) }
        }
        return futures.map { it.join() }.toTypedArray()
    }
    fun parallelWriteFiles(entries: Array<Pair<String, ByteArray>>) {
        val futures = entries.map { (fid, content) ->
            java.util.concurrent.CompletableFuture.supplyAsync { writeFile(fid, content) }
        }
        futures.forEach { it.join() }
    }
    fun diffParallel(other: MutableStore): Int {
        return Math.abs(fileCount.get() - other.fileCount.get())
    }
}
object Builder { fun build(mode: Int) = MutableStore(mode) }
fun mergeThreeWay(base: MutableStore, ours: MutableStore, theirs: MutableStore): Int {
    val bc = base.getContents(); val oc = ours.getContents(); val tc = theirs.getContents()
    val all = (bc.keys + oc.keys + tc.keys).toSet(); var conflicts = 0
    for (path in all) {
      val b = bc[path]; val o = oc[path]; val t = tc[path]
      val oEqT = o != null && t != null && o.contentEquals(t)
      val oEqB = o != null && b != null && o.contentEquals(b)
      val tEqB = t != null && b != null && t.contentEquals(b)
      if (!oEqT && !oEqB && !tEqB) conflicts++
    }
    return conflicts
}

// ---- Writer Storage Policy (informative, NOT on wire) ----
enum class StoragePolicy(val value: Int) {
    HIGHLY_VERTICAL(1), VERTICAL(2), HORIZONTAL(3), HIGHLY_HORIZONTAL(4);
}

class OptimizationConfiguration(val searchBudget: Int? = null, val memoryLimit: Int? = null, val maxDepDepth: Int? = null) {
    fun validate() {
        if (searchBudget != null && searchBudget <= 0) throw IllegalArgumentException("invalid search_budget")
        if (memoryLimit != null && memoryLimit <= 0) throw IllegalArgumentException("invalid memory_limit")
        if (maxDepDepth != null && maxDepDepth < 1) throw IllegalArgumentException("invalid maxDepDepth")
    }
}

class WriterOptions(val policy: StoragePolicy? = null, val wireModeConstraint: Int? = null, val optConfig: OptimizationConfiguration? = null) {
    val effectiveWireMode: Int? get() {
        if (policy != null && wireModeConstraint != null) {
            val expected = when (policy) { StoragePolicy.HIGHLY_VERTICAL, StoragePolicy.VERTICAL -> 1; else -> 2 }
            if (wireModeConstraint != expected) throw IllegalArgumentException("policy-wire mode conflict")
            return wireModeConstraint
        }
        return policy?.value ?: wireModeConstraint
    }
    fun resolveWireMode(defaultMode: Int) = effectiveWireMode ?: defaultMode
}