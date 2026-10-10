// VSN-1 independent consumer (Scala) -- Storage Policy round-trip.
// Uses the library's VsnApi.encodeWithSP (wire-out) + VsnApi.parseSP (wire-in).
package vsn

object Consumer {
  def sig(b: Array[Byte]): Boolean = {
    var ok = false
    if (b.length >= 7) for (i <- 0 to b.length - 7)
      if ((b(i) & 0xff) == 0 && (b(i+1) & 0xff) == 9 && (b(i+2) & 0xff) == 4 &&
          (b(i+3) & 0xff) == 9 && (b(i+4) & 0xff) == 1 && (b(i+5) & 0xff) == 1) ok = true
    ok
  }
  def main(args: Array[String]): Unit = {
    var bad = false
    for (p <- 1 to 4) {
      val b = VsnApi.encodeWithSP(1, 0L, p)
      if (!sig(b)) { System.err.println(s"FAIL p=$p wire-out"); bad = true }
      val got = VsnApi.parseSP(b)
      if (got != p) { System.err.println(s"FAIL p=$p got=$got"); bad = true }
    }
    if (bad) { println("CONSUMER SCALA FAIL"); sys.exit(1) }
    else println("CONSUMER SCALA PASS")
  }
}
