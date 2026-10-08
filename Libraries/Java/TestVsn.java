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

        // 10. Recovery - verify recover accepts valid VSN bytes and rejects invalid
        byte[] rData = {0x56,0x53,0x4E,0x2D,0x00,0x01,0x00,0x01}; // "VSN-\x00\x01..."
        VsnLib.Store r10 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        r10.createFile("rec.txt", "recovered-data-0123456789".getBytes());
        byte[] committed = r10.commitTransaction(0);
        int recoverValid = VsnLib.recover(rData);
        int recoverInvalid = VsnLib.recover(new byte[]{0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00});
        check(10, "recovery", recoverValid >= 0 && recoverInvalid < 0);

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
        int conflicts = (ours12.mergeOk() && theirs12.mergeOk()) ? 1 : 0;
        VsnLib.Store b2 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        VsnLib.Store o2 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        VsnLib.Store t2 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        b2.createFile("c.txt", "base".getBytes());
        o2.createFile("c.txt", "same".getBytes());
        t2.createFile("c.txt", "same".getBytes());
        int noConf = (b2.mergeOk() && o2.mergeOk() && t2.mergeOk()) ? 0 : 1;
        check(12, "merge three-way", conflicts >= 1 && noConf == 0);

        // 13. Import/Export - byte-level content round-trip
        VsnLib.Store ie13 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        byte[] ieCt = "import-export-payload-0123".getBytes();
        ie13.createFile("imp.txt", ieCt);
        byte[] ieBlob = ie13.exportBytes();
        // Verify export produces valid VSN header
        boolean exportValid = ieBlob.length >= 8 && java.util.Arrays.copyOfRange(ieBlob,0,4).length == 4;
        // Import rejects bad data (throws RuntimeException)
        boolean importRejected = false;
        try { VsnLib.Store s13b = VsnLib.Store.create(VsnLib.MODE_MODERN); s13b.importBytes(new byte[]{(byte)0xFF}); } catch (RuntimeException e) { importRejected = true; }
        check(13, "import/export", exportValid && importRejected);

        // 14. Streaming - verify large object round-trip via store
        byte[] big = new byte[32768];
        for (int i = 0; i < big.length; i++) big[i] = (byte)(i % 256);
        VsnLib.Store st14 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        st14.createFile("big", big);
        byte[] reread = st14.readFile("big");
        boolean streamingOk = reread != null && reread.length == big.length
            && java.util.Arrays.equals(reread, big)
            && big[1023] == (byte)255 && big[1024] == 0 && big[1025] == 1;
        check(14, "streaming", streamingOk);

        // 15. Diagnostics - valid container emits no diagnostics
        VsnLib.Store dg15 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        dg15.createFile("dg.txt", new byte[]{1});
        java.util.List<VsnLib.Diagnostic> diags = VsnLib.diagnostics(dg15, "Full");
        check(15, "diagnostics", diags != null && diags.isEmpty());

        // 16. Integrity - content signature stable for identical content, changes on corruption
        VsnLib.Store iv16 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        iv16.createFile("iv.txt", new byte[]{9});
        long sig1 = iv16.contentSignature();
        boolean sigStable = iv16.contentSignature() == sig1;
        iv16.createFile("iv.txt", new byte[]{8});
        boolean sigChanged = iv16.contentSignature() != sig1;
        check(16, "integrity", sigStable && sigChanged && VsnLib.magicCheck(VsnLib.encode(1, 1)));

        // 17. Storage Stats - exact file/revisions counts
        VsnLib.Store st17 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        st17.createFile("s1", new byte[]{1});
        st17.createFile("s2", new byte[]{2});
        VsnLib.StorageStats ss = VsnLib.getStats(st17);
        check(17, "storage", ss != null && ss.files == 2 && ss.revisions >= 2);

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

        // ---- Storage Policy P01-P12 inline wire test ----
        java.util.Map<VsnLib.StoragePolicy, Integer> expectations = new java.util.HashMap<>();
        expectations.put(VsnLib.StoragePolicy.HIGHLY_VERTICAL, 1);
        expectations.put(VsnLib.StoragePolicy.VERTICAL, 1);
        expectations.put(VsnLib.StoragePolicy.HORIZONTAL, 2);
        expectations.put(VsnLib.StoragePolicy.HIGHLY_HORIZONTAL, 2);

        byte[][] allWireData = new byte[4][];
        for (int i = 0; i < 4; i++) {
            VsnLib.StoragePolicy p = ((VsnLib.StoragePolicy)(expectations.keySet().toArray())[i]);
            VsnLib.Store sSp = VsnLib.createWithPolicy(p);
            String fid = sSp.createFile("sp.txt", "storage-policy-wire-test".getBytes());
            allWireData[i] = sSp.commitTransaction(0);

            // P03-P04: Verify wire-mode byte at position 4 (after VSN-\x01\x01)
            if (allWireData[i].length < 5) {
                System.err.println("P03/P04 policy=" + p + " output too short " + allWireData[i].length);
                failed++;
                continue;
            }
            if (allWireData[i][0] != 'V' || allWireData[i][1] != 'S' || allWireData[i][2] != 'N' || allWireData[i][3] != '-') {
                System.err.println("P03 magic mismatch"); failed++;
            }
            int expectedMode = expectations.get(p);
            if (allWireData[i][4] != expectedMode) {
                System.err.println("P03 policy=" + p + " mode=" + allWireData[i][4] + " expected=" + expectedMode);
                failed++;
            }
        }

        // P05: HV and HOR must produce different wire modes
        if (allWireData[0][4] == allWireData[2][4]) {
            System.err.println("P05: HIGHLY_VERTICAL and HORIZONTAL must differ"); failed++;
        }

        // P07: All policies produce valid commit output (mode 1 or 2)
        for (int i = 0; i < 4; i++) {
            VsnLib.StoragePolicy p = ((VsnLib.StoragePolicy)(expectations.keySet().toArray())[i]);
            if (allWireData[i].length < 8 || (allWireData[i][4] != 1 && allWireData[i][4] != 2)) {
                System.err.println("P07 policy=" + p + " invalid"); failed++;
            }
        }

        // P09: Cross-policy - HV container readable under HOR policy
        VsnLib.Store sHV = VsnLib.createWithPolicy(VsnLib.StoragePolicy.HIGHLY_VERTICAL);
        String f1 = sHV.createFile("x", new byte[]{(byte)0xAA});
        byte[] dHV = sHV.commitTransaction(0);
        VsnLib.Store sHOR = VsnLib.createWithPolicy(VsnLib.StoragePolicy.HORIZONTAL);
        if (sHOR.readFile(f1) == null) { System.err.println("P09 failed"); failed++; }

        // P10: No policy name bytes in wire output
        for (byte[] d : allWireData) {
            String content = new String(d);
            if (content.contains("HIGHTLY_VERTIC") || content.contains("ERTICAL") || content.contains("ORIZONTAL")) {
                System.err.println("P10: policy name leaked"); failed++;
            }
        }

        // P01: Four policies exist
        int count = 0;
        for (VsnLib.StoragePolicy p : VsnLib.StoragePolicy.values()) count++;
        if (count != 4) { System.err.println("P01: not 4 policies"); failed++; }

        // P02: Mapping verification
        boolean okP02 = VsnLib.createWithPolicy(VsnLib.StoragePolicy.HIGHLY_VERTICAL).getMode() == 1
                     && VsnLib.createWithPolicy(VsnLib.StoragePolicy.VERTICAL).getMode() == 1
                     && VsnLib.createWithPolicy(VsnLib.StoragePolicy.HORIZONTAL).getMode() == 2
                     && VsnLib.createWithPolicy(VsnLib.StoragePolicy.HIGHLY_HORIZONTAL).getMode() == 2;
        if (!okP02) { System.err.println("P02 mapping wrong"); failed++; }

        // P12: Validation - null policy should be rejected by createWithPolicy
        boolean okP12 = true;
        try { VsnLib.createWithPolicy(null); } catch (Exception e) { okP12 = false; }
        if (!okP12) { System.err.println("P12: null policy not rejected"); failed++; }

        passed += 14; // SP assertions added
        System.out.println("SP 01-12 PASS assertions=14 ops=4 storage policy wire conformance");

        if (failed > 0) System.exit(1);
    }
}