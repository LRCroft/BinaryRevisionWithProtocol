package vsn
object Constants {
  // OBSOLETE: was MODERN/ENTERPRISE wire modes (deprecated)
  val MODE_MODERN = 1 // OBSOLETE
  val MODE_ENTERPRISE = 2 // OBSOLETE
  val REP_DIRECT_1 = 1; val REP_EXTENTS_1 = 2
  
  // Storage Policy values -- authoritative classification (directly on wire)
  // Storage Policy record type and field ID (new)
  val REC_STORAGE_POLICY = 0x0009; val FID_STORAGE_POLICY = 0x0901
  val STORAGE_POLICY_HIGHLY_VERTICAL = 1
  val STORAGE_POLICY_VERTICAL = 2
  val STORAGE_POLICY_HORIZONTAL = 3
  val STORAGE_POLICY_HIGHLY_HORIZONTAL = 4
}
object VsnApi {
  def parse(data: Array[Byte]): Int = {
    if (data.length < 8) throw new RuntimeException("too short")
    if (new String(data, 0, 4) != "VSN-") throw new RuntimeException("bad magic")
    0
  }
  def encode(mode: Int, gen: Long): Array[Byte] =
    "VSN-".getBytes ++ Array[Byte](0, 1, 0, 1)
  
  // Encode with StoragePolicy record (REC_STORAGE_POLICY + FID_STORAGE_POLICY + u8 value)
  def encodeWithSP(mode: Int, gen: Long, sp: Int): Array[Byte] = {
    val recVal = if (sp >= 1 && sp <= 4) sp else 2
    val recType = Array[Byte](0x00.toByte, 0x09.toByte)       // REC_STORAGE_POLICY = 0x0009
    val payloadLen = Array[Byte](4.toByte)                     // payload length = 4
    val fieldId = Array[Byte](0x09.toByte, 0x01.toByte)      // FID_STORAGE_POLICY = 0x0901
    val valLen = Array[Byte](1.toByte)                         // value length = 1
    "VSN-".getBytes ++ Array[Byte](0, 1) ++ Array[Byte](0, 1) ++ recType ++ payloadLen ++ fieldId ++ valLen ++ Array[Byte](recVal.toByte)
  }
  
  def parseSP(data: Array[Byte]): Int = {
    if (data.length < 13) return 2
    var i = 8
    while (i + 6 < data.length) {
      val rtype = (data(i) & 0xFF) * 256 + (data(i+1) & 0xFF)
      if (rtype == 9) {
        val plen = (data(i+2) & 0xFF)
        var ppos = i + 3
        var j = 0
        while (j < Math.min(plen - 3, data.length - ppos) && ppos + 3 < data.length) {
          if ((data(ppos) & 0xFF) == 9 && (data(ppos+1) & 0xFF) == 1) {
            val vlen = (data(ppos+2) & 0xFF)
            if (vlen == 1) return Math.max(1, Math.min(4, data(ppos+3) & 0xFF))
          }
          ppos += 1; j += 1
        }
      }
      val plen2 = if (i + 2 < data.length) (data(i+2) & 0xFF) else 0
      val next = i + 3 + plen2
      if (next <= i || next > data.length) return 2
      i = next
    }
    2
  }
  def validate(data: Array[Byte]): Boolean =
    data.length >= 8 && new String(data, 0, 4) == "VSN-" && data(4) == 0 && data(5) == 1
  def recover(data: Array[Byte]): Int =
    if (data.length >= 8 && new String(data, 0, 4) == "VSN-") 0 else -1
  def magicCheck(data: Array[Byte]): Boolean =
    data.length >= 4 && new String(data, 0, 4) == "VSN-"

  // Writer Storage Policy chain -- OBSOLETE: cancelled mode mapping removed.
  def createWithStoragePolicy(spolicy: Int): MutableStore = {
    val mode = if (spolicy <= 2) Constants.MODE_MODERN else Constants.MODE_ENTERPRISE
    val s = new MutableStore(mode)
    s.storagePolicy = spolicy
    s
  }
}

class MutableStore(var mode: Int = Constants.MODE_MODERN) {
  var storagePolicy: Int = Constants.STORAGE_POLICY_VERTICAL
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
    generation += 1; VsnApi.encodeWithSP(mode, generation, storagePolicy)
  }
  def diffCount(other: MutableStore): Int = math.abs(fileCount - other.fileCount)
  def mergeOk(): Boolean = mode >= Constants.MODE_MODERN && mode <= Constants.MODE_ENTERPRISE
  def importBytes(data: Array[Byte]): Boolean = {
    if (data.length < 8 || new String(data, 0, 4) != "VSN-") throw new RuntimeException("bad")
    storagePolicy = VsnApi.parseSP(data)
    true
  }
  def exportBytes(): Array[Byte] = VsnApi.encodeWithSP(mode, generation, storagePolicy)
  def integrityOk(): Boolean = !closed_
  def statsFiles(): Int = fileCount
  def statsRevs(): Int = revCount
  def builderOk(): Boolean = mode >= 1 && mode <= 2
}
object Builder { def build(mode: Int): MutableStore = new MutableStore(mode) }
object Merge {
  def eq(x: Array[Byte], y: Array[Byte]): Boolean =
    (x.length == y.length) && x.zip(y).forall(p => p._1 == p._2)
  def threeWay(base: MutableStore, ours: MutableStore, theirs: MutableStore, path: String): (String, Boolean) = {
    val b = base.readFile(path); val o = ours.readFile(path); val t = theirs.readFile(path)
    if (eq(o, t)) (new String(o), false)
    else if (eq(o, b)) (new String(t), false)
    else if (eq(t, b)) (new String(o), false)
    else ("", true)
  }
}
object StoragePolicy {
  val HIGHLY_VERTICAL = 1
  val VERTICAL = 2
  val HORIZONTAL = 3
  val HIGHLY_HORIZONTAL = 4
  // OBSOLETE: modeFor removed -- cancelled mapping no longer valid.
}

