package vsn
import scala.concurrent.{Future, Await}
import scala.concurrent.ExecutionContext.Implicits.global
import scala.concurrent.duration._

object TestVSN {
  def runCap(n: Int): Boolean = {
    val s = new MutableStore(Constants.MODE_MODERN)
    val ok =
      try {
        n match {
          case 1  => s.mode == Constants.MODE_MODERN && Builder.build(Constants.MODE_ENTERPRISE).mode == Constants.MODE_ENTERPRISE
          case 2  =>
            val fid = s.createFile("a", "hello".getBytes)
            fid.nonEmpty && s.fileExists(fid) && new String(s.readFile(fid)) == "hello"
          case 3  =>
            val fid = s.createFile("r", "v1".getBytes)
            s.writeFile(fid, "v2".getBytes); s.writeFile(fid, "v3".getBytes)
            s.listRevisions(fid) == 3
          case 4  =>
            val fid = s.createFile("lc", Array[Byte](1))
            for (_ <- 1 to 5) s.writeFile(fid, Array[Byte](2))
            val removed = s.limitCleanup(fid, 3)
            removed == 3 && s.listRevisions(fid) == 3
          case 5  =>
            s.createFile("o", Array[Byte](1, 2)); s.listObjects() == 1
          case 6  =>
            val tx = s.beginTransaction()
            s.stageAdd("t", Array[Byte](1))
            val b = s.commitTransaction(tx); b.length >= 8 && s.generation >= 1
          case 7  => Constants.REP_DIRECT_1 == 1 && Constants.REP_EXTENTS_1 == 2
          case 8  => Builder.build(Constants.MODE_ENTERPRISE).mode == Constants.MODE_ENTERPRISE
          case 9  => VsnApi.validate(s.exportBytes())
          case 10 => VsnApi.recover(s.exportBytes()) >= 0
          case 11 =>
            s.createFile("x", Array[Byte](1))
            val s2 = new MutableStore(Constants.MODE_MODERN)
            s.diffCount(s2) == 1 && s.diffCount(s) == 0
          case 12 => s.mergeOk()
          case 13 =>
            val bytes = s.exportBytes(); val s2 = new MutableStore(); s2.importBytes(bytes)
            s2.mode == s.mode && s2.generation == s.generation
          case 14 =>
            val fid = s.createFile("big", Array[Byte](1, 2, 3))
            s.readFile(fid).length == 3
          case 15 => s.statsRevs() >= 0 && s.statsFiles() >= 0
          case 16 => s.integrityOk()
          case 17 =>
            s.createFile("stat", Array[Byte](1)); s.statsFiles() == 1 && s.statsRevs() >= 1
          case 18 => Builder.build(Constants.MODE_ENTERPRISE).builderOk()
          case 19 => VsnApi.magicCheck(VsnApi.encode(1, 1))
          case _  => false
        }
      } catch { case _: Throwable => false }
    s.close()
    if (ok) println(s"PASS $n") else println(s"FAIL $n")
    ok
  }

  def main(args: Array[String]): Unit = {
    val results = (1 to 19).map(n => Future { runCap(n) })
    val flags = Await.result(Future.sequence(results), Duration.Inf)
    val passed = flags.count(identity)
    println(s"SUMMARY $passed/19")
    if (passed < 19) sys.exit(1)
  }
}
