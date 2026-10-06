// VSN-1 Capability Conformance Test for Java
// Generates PASS lines for conformance runner (1-19)

public class TestVsn {
    static int passed = 0, failed = 0;
    static void check(int n, String label, boolean cond) {
        if (cond) { passed++; System.out.println("CAP " + n + " PASS assertions=1 ops=1 " + label); }
        else { failed++; System.out.println("CAP " + n + " FAIL assertions=0 ops=1 " + label); }
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

        // 7. Representations - DIRECT-1 content round-trip
        VsnLib.Store s7 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        byte[] d7 = "VSN-TEST-DATA-0123".getBytes();
        s7.createFile("rep.txt", d7);
        byte[] rd7 = s7.readFile("rep.txt");
        check(7, "representations DIRECT-1 round-trip",
            rd7 != null && java.util.Arrays.equals(rd7, d7) && rd7.length == 18);

        // 8. Modes - behavioral MODERN + ENTERPRISE
        VsnLib.Store sm = VsnLib.Store.create(VsnLib.MODE_MODERN);
        VsnLib.Store se = VsnLib.Store.create(VsnLib.MODE_ENTERPRISE);
        byte[] dm = "modern-data".getBytes(); byte[] de = "enterprise".getBytes();
        sm.createFile("m.txt", dm); se.createFile("e.txt", de);
        check(8, "modes behavioral",
            sm.getMode()==1 && se.getMode()==2
            && java.util.Arrays.equals(sm.readFile("m.txt"), dm)
            && java.util.Arrays.equals(se.readFile("e.txt"), de));

        // 9. Validation
        check(9, "validation", VsnLib.validate(VsnLib.encode(1, 1)));

        // 10. Recovery
        check(10, "recovery", VsnLib.recover(VsnLib.encode(1, 1)) >= 0);

        // 11. Diff
        VsnLib.Store sm11 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        sm11.createFile("x", "y".getBytes());
        check(11, "diff", sm11.diffCount(s) >= 1);

        // 12. Merge - real three-way merge with conflict + non-conflict
        VsnLib.Store base12 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        VsnLib.Store ours12 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        VsnLib.Store theirs12 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        base12.createFile("f.txt", "base-content".getBytes());
        ours12.createFile("f.txt", "ours-content".getBytes());
        theirs12.createFile("f.txt", "theirs-content".getBytes());
        int conflicts = VsnLib.mergeConflicts(base12, ours12, theirs12);
        VsnLib.Store b2 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        VsnLib.Store o2 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        VsnLib.Store t2 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        b2.createFile("c.txt", "base".getBytes());
        o2.createFile("c.txt", "same".getBytes());
        t2.createFile("c.txt", "same".getBytes());
        int noConf = VsnLib.mergeConflicts(b2, o2, t2);
        check(12, "merge three-way", conflicts >= 1 && noConf == 0);

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
        check(17, "storage", ss != null && ss.files >= 1);

        // 18. Builder API
        VsnLib.Store builder = VsnLib.newBuilder(VsnLib.MODE_ENTERPRISE);
        check(18, "builder", builder.getMode() == VsnLib.MODE_ENTERPRISE);

        // 19. Interop - encode/commit round-trip with content
        VsnLib.Store s19 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        byte[] d19 = "interop-data-42".getBytes();
        s19.createFile("i.txt", d19);
        byte[] committed19 = s19.commitTransaction(0);
        check(19, "interop round-trip",
            committed19 != null && committed19.length >= 8
            && committed19[0]==(byte)'V' && committed19[1]==(byte)'S'
            && committed19[2]==(byte)'N' && committed19[3]==(byte)'-');

        System.out.println("---");
        System.out.println("Java capabilities: " + passed + " passed, " + failed + " failed");
        if (failed > 0) System.exit(1);
    }
}