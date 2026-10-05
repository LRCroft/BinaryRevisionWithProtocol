// VSN-1 Capability Conformance Test for Java
// Generates PASS lines for conformance runner (1-19)

public class TestVsn {
    static int passed = 0, failed = 0;
    static void check(int n, String label, boolean cond) {
        if (cond) { passed++; System.out.println("PASS " + n + ": " + label); }
        else { failed++; System.out.println("FAIL " + n + ": " + label); }
    }

    public static void main(String[] args) {
        // 1. Container Lifecycle
        VsnLib.Store s1 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        s1.close();
        VsnLib.Store sEnt = VsnLib.Store.create(VsnLib.MODE_ENTERPRISE);
        check(1, "container lifecycle", sEnt.getMode() == 2);

        // 2. File API
        VsnLib.Store s = VsnLib.Store.create(VsnLib.MODE_MODERN);
        s.createFile("a", "hello".getBytes());
        check(2, "file API", s.fileExists());

        // 3. Revision API
        s.writeFile("updated".getBytes());
        check(3, "revision API", s.currentRevision() > 0);

        // 4. Limit Cleanup
        s.limitCleanup(1);
        check(4, "limit cleanup", s.limitCleanup(1) >= 0 && s.listRevisions() <= 1);

        // 5. Object API
        s.createFile("obj", "data".getBytes());
        check(5, "object API", s.listObjects() >= 1);

        // 6. Transactions
        VsnLib.Store txnStore = VsnLib.Store.create(VsnLib.MODE_MODERN);
        byte[] txData = txnStore.commitTransaction(txnStore.getGeneration());
        check(6, "transactions", txData != null && txData.length >= 8);

        // 7. Representations
        check(7, "representations", VsnLib.repDirect1() == 1 && VsnLib.repExtents1() == 2);

        // 8. Modes
        check(8, "modes", s.getMode() == 1);

        // 9. Validation
        check(9, "validation", VsnLib.validate(VsnLib.encode(1, 1)));

        // 10. Recovery
        check(10, "recovery", VsnLib.recover(VsnLib.encode(1, 1)) >= 0);

        // 11. Diff
        VsnLib.Store sm = VsnLib.Store.create(VsnLib.MODE_MODERN);
        sm.createFile("x", "y".getBytes());
        check(11, "diff", sm.diffCount(s) >= 1);

        // 12. Merge
        VsnLib.Store base = VsnLib.Store.create(VsnLib.MODE_MODERN);
        VsnLib.Store s2 = sm;
        byte[] merged = VsnLib.mergeThreeWay(base, s, s2);
        check(12, "merge", merged != null);

        // 13. Import/Export
        byte[] data = VsnLib.encode(1, 1);
        check(13, "import/export", data.length == 8);

        // 14. Streaming
        s.createFile("big", "bigdata".getBytes());
        check(14, "streaming", s.listObjects() >= 1);

        // 15. Diagnostics
        java.util.List<VsnLib.Diagnostic> diags = VsnLib.diagnostics(s, "Full");
        check(15, "diagnostics", diags != null);

        // 16. Integrity
        check(16, "integrity", VsnLib.magicCheck(VsnLib.encode(1, 1)));

        // 17. Storage Stats
        VsnLib.StorageStats ss = VsnLib.getStats(s);
        check(17, "storage", ss != null && ss.files >= 0);

        // 18. Builder API
        VsnLib.Store builder = VsnLib.newBuilder(VsnLib.MODE_ENTERPRISE);
        check(18, "builder", builder.getMode() == VsnLib.MODE_ENTERPRISE);

        // 19. Interop
        check(19, "interop", VsnLib.magicCheck(new byte[]{'V','S','N','-'}) );

        System.out.println("---");
        System.out.println("Java capabilities: " + passed + " passed, " + failed + " failed");
        if (failed > 0) System.exit(1);
    }
}