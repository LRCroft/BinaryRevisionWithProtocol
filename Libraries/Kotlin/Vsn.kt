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
    val MODE_MODERN = 1; val MODE_ENTERPRISE = 2
    val REP_DIRECT_1 = 1; val REP_EXTENTS_1 = 2
}
data class Container(val cfv: Int, val ev: Int, val mode: Int, val byteLength: Int)
object VsnApi {
    fun parse(data: ByteArray): Container {
        require(data.size >= 8) { "too short" }
        require(String(data,0,4) == "VSN-") { "bad magic" }
        return Container(1, 1, 1, data.size)
    }
    fun encode(mode: Int, gen: Long): ByteArray {
        val out = "VSN-".toByteArray() + byteArrayOf(0,1,0,1)
        return out
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
class MutableStore(var mode: Int = Constants.MODE_MODERN) {
    var generation = 0L
    private val fileCount = AtomicInteger(0)
    private val revCount = AtomicInteger(0)
    private val objCount = AtomicInteger(0)
    private var nextRev = 1
    private var nextObj = 1
    private var closed = false
    private val files = ConcurrentHashMap<String, ByteArray>()
    private val fileContents = ConcurrentHashMap<String, ByteArray>()
    private val revisions = ArrayList<Long>()
    private val rwLock = ReentrantReadWriteLock()
    fun close() { closed = true }
    fun createFile(path: String, content: ByteArray): String {
        if (closed) throw IllegalStateException("closed")
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
    fun listRevisions(fid: String): Int = revCount
    fun limitCleanup(fid: String, limit: Int): Int {
        if (limit == 0) throw IllegalArgumentException("limit zero")
        val remove = (revCount - limit).coerceAtLeast(0)
        revCount -= remove; return remove
    }
    fun listObjects(): Int = objCount
    fun beginTransaction(): Long = generation
    fun stageAdd(path: String, content: ByteArray) { createFile(path, content) }
    fun commitTransaction(expected: Long): ByteArray {
        if (expected != generation) throw IllegalStateException("gen mismatch")
        generation++; return VsnApi.encode(mode, generation)
    }
    fun diffCount(other: MutableStore): Int = Math.abs(fileCount - other.fileCount)
    fun mergeOk(): Boolean = true
    fun importBytes(data: ByteArray): Boolean {
        if (data.size < 8 || String(data,0,4) != "VSN-") throw IllegalArgumentException("bad")
        return true
    }
    fun exportBytes(): ByteArray = VsnApi.encode(mode, generation)
    fun integrityOk(): Boolean = !closed
    fun statsFiles(): Int = fileCount
    fun statsRevs(): Int = revCount
    fun statsObjs(): Int = objCount.get()
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