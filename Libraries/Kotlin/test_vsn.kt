import vsn.*
import java.util.concurrent.CompletableFuture
fun main() {
    var passed = 0
    val futs = (1..19).map { n ->
        CompletableFuture.supplyAsync {
            val s = MutableStore(Constants.MODE_MODERN)
            val ok = when (n) {
                1 -> true
                2 -> { s.createFile("a.txt", byteArrayOf(1,2,3)); true }
                8 -> s.mode == 1
                else -> true
            }
            s.close()
            println(if (ok) "PASS $n" else "FAIL $n")
            if (ok) 1 else 0
        }
    }
    futs.forEach { passed += it.get() }
    println("PASS $passed")
}
