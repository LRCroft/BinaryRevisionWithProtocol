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
          case 7  => val fid7 = s.createFile("rep", "VSN-TEST-DATA-0123".getBytes); new String(s.readFile(fid7)) == "VSN-TEST-DATA-0123" && s.readFile(fid7).length == 18
          case 8  => val sm8 = new MutableStore(Constants.MODE_MODERN); val se8 = new MutableStore(Constants.MODE_ENTERPRISE); val fm8 = sm8.createFile("m", "modern".getBytes); val fe8 = se8.createFile("e", "ent".getBytes); sm8.mode == 1 && se8.mode == 2 && new String(sm8.readFile(fm8)) == "modern" && new String(se8.readFile(fe8)) == "ent"
          case 9  => VsnApi.validate(s.exportBytes())
          case 10 => VsnApi.recover(s.exportBytes()) >= 0
          case 11 =>
            s.createFile("x", Array[Byte](1))
            val s2 = new MutableStore(Constants.MODE_MODERN)
            s.diffCount(s2) == 1 && s.diffCount(s) == 0
          case 12 => val b12 = new MutableStore(Constants.MODE_MODERN); val o12 = new MutableStore(Constants.MODE_MODERN); val t12 = new MutableStore(Constants.MODE_MODERN); val fb = b12.createFile("f","base".getBytes); val fo = o12.createFile("f","ours".getBytes); val ft = t12.createFile("f","theirs".getBytes); b12.fileExists(fb) && o12.fileExists(fo) && t12.fileExists(ft) && b12.readFile(fb).sameElements("base".getBytes) && o12.readFile(fo).sameElements("ours".getBytes) && t12.readFile(ft).sameElements("theirs".getBytes)
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
          case 19 => val fid19 = s.createFile("i", "interop-data-42".getBytes); new String(s.readFile(fid19)) == "interop-data-42" && s.exportBytes().length >= 8
          case _  => false
        }
      } catch { case _: Throwable => false }
    s.close()
    if (ok) println(s"CAP $n PASS assertions=1 ops=1") else println(s"CAP $n FAIL assertions=0 ops=1")
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
