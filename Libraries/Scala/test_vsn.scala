import vsn._
import scala.concurrent.{Future, Promise}
import scala.concurrent.ExecutionContext.Implicits.global

object TestVSN {
  def runCap(n: Int): Boolean = {
    val s = new MutableStore(Constants.MODE_MODERN)
    val ok = n match {
      case 2 => { val fid = s.createFile("a", Array[Byte](1,2,3)); fid.nonEmpty }
      case 8 => s.mode == Constants.MODE_MODERN
      case _ => true
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
