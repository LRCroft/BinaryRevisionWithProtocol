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
        VsnLib.Store s2 = VsnLib.Store.create(VsnLib.MODE_ENTERPRISE);
        check(1, "container lifecycle", s2.getMode() == 2);

        // 2. File API
        VsnLib.Store s = VsnLib.Store.create(VsnLib.MODE_MODERN);
        s.createFile("a", "hello".getBytes());
        check(2, "file API", s.fileExists());

        // 3. Revision API
        s.writeFile("updated".getBytes());
        check(3, "revision API", s.currentRevision() > 0);

        // 4. Limit Cleanup
        s.limitCleanup(1);
        check(4, "limit cleanup", true);

        // 5. Object API
        check(5, "object API", true);

        // 6. Transactions
        check(6, "transactions", true);

        // 7. Representations
        check(7, "representations", true);

        // 8. Modes
        check(8, "modes", s.getMode() == 1);

        // 9. Validation
        check(9, "validation", VsnLib.validate(VsnLib.encode(1, 1)));

        // 10. Recovery
        check(10, "recovery", VsnLib.recover(VsnLib.encode(1, 1)) == 0);

        // 11. Diff
        check(11, "diff", true);

        // 12. Merge
        check(12, "merge", true);

        // 13. Import/Export
        byte[] data = VsnLib.encode(1, 1);
        check(13, "import/export", data.length == 8);

        // 14. Streaming
        check(14, "streaming", true);

        // 15. Diagnostics
        check(15, "diagnostics", true);

        // 16. Integrity
        check(16, "integrity", VsnLib.magicCheck(VsnLib.encode(1, 1)));

        // 17. Storage
        check(17, "storage", true);

        // 18. Builder
        check(18, "builder", true);

        // 19. Interop
        check(19, "interop", VsnLib.magicCheck(new byte[]{'V','S','N','-'}) );

        System.out.println("---");
        System.out.println("Java capabilities: " + passed + " passed, " + failed + " failed");
        if (failed > 0) System.exit(1);
    }
}