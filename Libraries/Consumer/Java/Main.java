// Independent Java consumer: compiled against VsnLib and uses ONLY the public API.
import java.util.*;

public class Main {
    static int fails = 0;
    static void check(boolean c, String m) {
        if (c) System.out.println("ok  - " + m);
        else { System.out.println("FAIL: " + m); fails++; }
    }

    public static void main(String[] args) {
        VsnLib.Store s = VsnLib.Store.create(VsnLib.MODE_MODERN);
        check(s != null, "Store.create");
        String name = s.createFile("java.txt", "JAVA-CONSUMER".getBytes());
        check(name != null && s.fileExists(), "createFile + fileExists");
        check("JAVA-CONSUMER".equals(new String(s.readFile("java.txt"))), "readFile round-trips");
        s.writeFile("JAVA-CONSUMER-2".getBytes());
        check(s.listRevisions() >= 1, "revision tracked");
        byte[] data = s.commitTransaction(0);
        check(data != null && data.length > 0, "commit produced canonical bytes");
        check(VsnLib.validate(data), "validate returns true");
        check(VsnLib.magicCheck(data), "magicCheck true");
        check(VsnLib.recover(data) == 0, "recover ok");
        check(VsnLib.StoragePolicy.values().length == 4, "4 StoragePolicy values defined (1..4)");
        // SP wire-out / wire-in round-trip via the public API for all four policies.
        boolean[] rt = new boolean[4];
        for (VsnLib.StoragePolicy p : VsnLib.StoragePolicy.values()) {
            VsnLib.Store sp = VsnLib.createWithPolicy(p);
            sp.createFile("sp.txt", "SP-CONSUMER".getBytes());
            byte[] wire = sp.commitTransaction(0);
            Integer read = VsnLib.parseStoragePolicy(wire);
            rt[p.value() - 1] = (read != null && read.intValue() == p.value());
        }
        check(rt[0], "SP wire-in: HIGHLY_VERTICAL==1 read back");
        check(rt[1], "SP wire-in: VERTICAL==2 read back");
        check(rt[2], "SP wire-in: HORIZONTAL==3 read back");
        check(rt[3], "SP wire-in: HIGHLY_HORIZONTAL==4 read back");

        if (fails == 0) System.out.println("CONSUMER JAVA PASS");
        else { System.out.println("CONSUMER JAVA FAIL (" + fails + ")"); System.exit(1); }
    }
}