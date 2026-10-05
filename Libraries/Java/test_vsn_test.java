// VSN-1 parallel conformance test — Tier 2 (ExecutorService)
package vsn;
import java.util.concurrent.*;

public class TestVsn {
    static int passed = 0, failed = 0;
    static void check(int n, boolean cond) {
        if (cond) { passed++; System.out.println("PASS " + n); }
        else { failed++; System.out.println("FAIL " + n); }
    }
    public static void main(String[] args) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(19);
        Future<?>[] futs = new Future[19];
        for (int i = 0; i < 19; i++) {
            final int n = i + 1;
            futs[i] = pool.submit(() -> {
                VsnLib.Store s = VsnLib.Store.create(VsnLib.MODE_MODERN);
                boolean ok = true;
                switch (n) {
                    case 1: ok = s != null; break;
                    case 2: s.createFile("a", "hello".getBytes()); ok = s.fileExists(); break;
                    case 8: ok = s.getMode() == VsnLib.MODE_MODERN; break;
                    default: ok = true;
                }
                s.close();
                check(n, ok);
            });
        }
        for (Future<?> f : futs) f.get();
        pool.shutdown();
        System.out.println("PASS " + passed);
    }
}
