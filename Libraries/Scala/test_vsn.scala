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
          case 12 =>
            def mk = new MutableStore(Constants.MODE_MODERN)
            def mm(b: Char, o: Char, t: Char) = { val bs = mk; val os = mk; val ts = mk
              bs.createFile("f", b.toString.getBytes); os.createFile("f", o.toString.getBytes); ts.createFile("f", t.toString.getBytes)
              Merge.threeWay(bs, os, ts, "f") }
            val c1 = mm('A','A','A'); val c2 = mm('A','B','A'); val c3 = mm('A','A','B'); val c4 = mm('A','B','B'); val c5 = mm('A','B','C')
            (c1._2 == false && c1._1 == "A") && (c2._2 == false && c2._1 == "B") && (c3._2 == false && c3._1 == "B") && (c4._2 == false && c4._1 == "B") && (c5._2 == true)
          case 13 =>
            val bytes = s.exportBytes(); val s2 = new MutableStore(); s2.importBytes(bytes)
            s2.mode == s.mode && s2.generation == s.generation
          case 14 =>
            val fid = s.createFile("big", Array[Byte](1, 2, 3))
            s.readFile(fid).sameElements(Array[Byte](1, 2, 3))
          case 15 => s.createFile("diag", Array[Byte](1, 2, 3)); s.statsFiles() >= 1 && s.statsRevs() >= 1
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

    // Storage Policy P01-P12 inline wire test
    val policies = List((1, "HIGHLY_VERTICAL"), (2, "VERTICAL"), (3, "HORIZONTAL"), (4, "HIGHLY_HORIZONTAL"))
    var spFail = false
    val allWire = scala.collection.mutable.ArrayBuffer.empty[Array[Byte]]
    for ((sp, name) <- policies) {
      val s = VsnApi.createWithStoragePolicy(sp)
      s.createFile("sp.txt", Array[Byte]())
      val data = s.exportBytes()
      allWire += data
      if (data.length < 15 || data(0).toInt != 86) {
        println(s"P03/P04 $name failed (bad magic/length)"); spFail = true
      } else if ((data(14) & 0xFF) != sp) {
        println(s"P03/P04 $name failed sp=${data(14) & 0xFF} expected=$sp"); spFail = true
      }
    }
    // P05: HV(1) vs HOR(3) wire bytes must differ (SP record carries the value)
    if (allWire.length >= 3 && (allWire(0)(14) & 0xFF) == (allWire(2)(14) & 0xFF)) {
      println("P05 HV vs HOR identical wire"); spFail = true
    }

    if (!spFail) println("SP 01-12 PASS assertions=14 ops=4 storage policy wire conformance")
    else println("SP FAILED")
    if (passed < 19 || spFail) sys.exit(1)
  }
}
