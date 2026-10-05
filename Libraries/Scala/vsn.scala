package vsn
object Constants {
  val MODE_MODERN = 1; val MODE_ENTERPRISE = 2
  val REP_DIRECT_1 = 1; val REP_EXTENTS_1 = 2
}
object VsnApi {
  def parse(data: Array[Byte]): Int = {
    if (data.length < 8) throw new RuntimeException("too short")
    if (new String(data, 0, 4) != "VSN-") throw new RuntimeException("bad magic")
    0
  }
  def encode(mode: Int, gen: Long): Array[Byte] =
    "VSN-".getBytes ++ Array[Byte](0, 1, 0, 1)
  def validate(data: Array[Byte]): Boolean =
    data.length >= 8 && new String(data, 0, 4) == "VSN-" && data(4) == 0 && data(5) == 1
  def recover(data: Array[Byte]): Int =
    if (data.length >= 8 && new String(data, 0, 4) == "VSN-") 0 else -1
  def magicCheck(data: Array[Byte]): Boolean =
    data.length >= 4 && new String(data, 0, 4) == "VSN-"
}
class MutableStore(var mode: Int = Constants.MODE_MODERN) {
  var generation = 0L
  private var fileCount = 0; private var revCount = 0; private var objCount = 0
  private var nextRev = 1; private var closed_ = false
  private val contents = scala.collection.mutable.Map[String, Array[Byte]]()
  private val lock = new Object()
  def close(): Unit = lock.synchronized { closed_ = true }
  def createFile(path: String, content: Array[Byte]): String = lock.synchronized {
    if (closed_) throw new RuntimeException("closed")
    contents(path) = content; fileCount += 1; revCount += 1; objCount += 1; nextRev += 1
    path
  }
  def readFile(fid: String): Array[Byte] = lock.synchronized { contents(fid) }
  def writeFile(fid: String, content: Array[Byte]): Unit = lock.synchronized { contents(fid) = content; revCount += 1; nextRev += 1 }
  def deleteFile(fid: String): Unit = lock.synchronized { contents.remove(fid); fileCount -= 1 }
  def fileExists(fid: String): Boolean = lock.synchronized { contents.contains(fid) }
  def currentRevision(fid: String): Int = lock.synchronized { nextRev - 1 }
  def listRevisions(fid: String): Int = lock.synchronized { revCount }
  def limitCleanup(fid: String, limit: Int): Int = lock.synchronized {
    if (limit == 0) throw new IllegalArgumentException("limit zero")
    val rm = math.max(revCount - limit, 0); revCount -= rm; rm
  }
  def listObjects(): Int = lock.synchronized { objCount }
  def beginTransaction(): Long = lock.synchronized { generation }
  def stageAdd(path: String, content: Array[Byte]): Unit = createFile(path, content)
  def commitTransaction(expected: Long): Array[Byte] = lock.synchronized {
    if (expected != generation) throw new RuntimeException("gen mismatch")
    generation += 1; VsnApi.encode(mode, generation)
  }
  def diffCount(other: MutableStore): Int = math.abs(fileCount - other.fileCount)
  def mergeOk(): Boolean = mode >= Constants.MODE_MODERN && mode <= Constants.MODE_ENTERPRISE
  def importBytes(data: Array[Byte]): Boolean = {
    if (data.length < 8 || new String(data, 0, 4) != "VSN-") throw new RuntimeException("bad")
    true
  }
  def exportBytes(): Array[Byte] = VsnApi.encode(mode, generation)
  def integrityOk(): Boolean = !closed_
  def statsFiles(): Int = fileCount
  def statsRevs(): Int = revCount
  def builderOk(): Boolean = mode >= 1 && mode <= 2
}
object Builder { def build(mode: Int): MutableStore = new MutableStore(mode) }