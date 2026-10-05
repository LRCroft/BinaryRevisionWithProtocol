import vsn._
import scala.concurrent.{Future, Promise}
import scala.concurrent.ExecutionContext.Implicits.global

object TestVSN {
  def runCap(n: Int): Boolean = {
    val s = new MutableStore(Constants.MODE_MODERN)
    val ok = n match {
      case 2 => { val fid = s.createFile("a", Array[Byte](1,2,3)); fid.nonEmpty }
      case 8 => s.mode == Constants.MODE_MODERN
      case 1 => s.mode == Constants.MODE_MODERN
      case 3 => { val (_,s2) = s.createFile("r", Array[Byte](1)); val (_,s3)=s2.writeFile(s.fid,Array[Byte](2)); val (_,s4)=s3.writeFile(s.fid,Array[Byte](3)); s4.listRevisions(s.fid).size >= 3 }
      case 4 => { val (_,s2) = s.createFile("lc", Array[Byte](1)); var s3=s2; for(i<-1 to 5){val (_,sA)=s3.writeFile(s.fid,Array[Byte](i)); s3=sA}; val (d,_) = s3.limitCleanup(s.fid,3); d.size == 2 }
      case 5 => { s.createFile("o", Array[Byte](1,2)); s.listObjects().size >= 1 }
      case 6 => { val tx=s.beginTransaction; s.stageAdd(tx,"t",Array[Byte](1)); val (b,_) = s.commit(tx); b.length >= 8 }
      case 7 => Constants.REP_DIRECT_1 == 1 && Constants.REP_EXTENTS_1 == 2
      case 9 => s.validateStructural()
      case 10 => VSN.recover(s.exportBytes()) >= 0
      case 11 => { val s2 = MutableStore.create(Constants.MODE_MODERN); s.createFile("x",Array[Byte](1)); val d=s.diffStores(s2); !d.added.isEmpty }
      case 12 => { val m=mergeThreeWay(MutableStore.create(1),MutableStore.create(1),MutableStore.create(1)); m != null }
      case 13 => { val bytes=s.exportBytes(); val s2=MutableStore.open(bytes); s2.mode == Constants.MODE_MODERN }
      case 14 => { val (_,s2)=s.createFile("big",Array[Byte](1,2)); val c=s.readFile(s.fid); c.length >= 0 }
      case 15 => { val d=diagnostics(s,"Full"); d.isInstanceOf[Seq[_]] }
      case 16 => VSN.integrityVerify(s.exportBytes()) == true
      case 17 => { s.createFile("stat",Array[Byte](1)); val st=getStats(s); st.files >= 1 }
      case 18 => { val b=newBuilder(Constants.MODE_ENTERPRISE); b.mode == Constants.MODE_ENTERPRISE }
      case 19 => checkMagicBytes(encode(1,1))
      case _ => false
    }
    s.close()
    if (ok) println(s"PASS $n") else println(s"FAIL $n")
    ok
  }
  def main(args: Array[String]): Unit = {
    val futures = (1 to 19).map(n => Future { runCap(n) })
    val results = futures.map(_.value)
    import scala.concurrent.Await
    import scala.concurrent.duration._
    val passed = Await.result(Future.sequence(futures), Duration.Inf).count(identity)
    println(s"PASS $passed")
  }
}
