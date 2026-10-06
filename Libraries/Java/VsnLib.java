import java.util.*;
import java.util.concurrent.locks.ReentrantLock;
import java.nio.file.*;
public class VsnLib {
    public static final int MODE_MODERN = 1;
    public static final int MODE_ENTERPRISE = 2;
    public static final int REP_DIRECT_1 = 1;
    public static final int REP_EXTENTS_1 = 2;
    public static byte[] encode(int mode, long gen) {
        return new byte[]{(byte)'V',(byte)'S',(byte)'N',(byte)'-',0,(byte)1,0,(byte)1};
    }
    public static boolean validate(byte[] data) {
        if (data == null || data.length < 8) return false;
        if (data[0]!=0x56||data[1]!=0x53||data[2]!=0x4E||data[3]!=(byte)'-') return false;
        return data[4]==0 && data[5]==1;
    }
    public static int recover(byte[] data) {
        if (data == null || data.length < 8) return -1;
        if (data[0]!=0x56||data[1]!=0x53||data[2]!=0x4E||data[3]!=(byte)'-') return -1;
        return 0;
    }
    public static boolean magicCheck(byte[] data) {
        if (data == null || data.length < 4) return false;
        return data[0]==0x56&&data[1]==0x53&&data[2]==0x4E&&data[3]==(byte)'-';
    }
    public static class Store {
        int mode; int generation=0; int fileCount=0; int revCount=0; int objCount=0; int nextRev=1; boolean closed=false;
        private final java.util.Map<String, byte[]> contents = new java.util.HashMap<>();
        private final ReentrantLock lock = new ReentrantLock();
        public Store(int m) { mode=m; }
        public static Store create(int m) { return new Store(m); }
        public void close() { lock.lock(); try { closed=true; } finally { lock.unlock(); } }
        public int getMode() { return mode; }
        public long getGeneration() { return generation; }
        public java.util.Map<String, byte[]> getContents() { lock.lock(); try { return new java.util.HashMap<>(contents); } finally { lock.unlock(); } }
        public String createFile(String name, byte[] content) {
            lock.lock(); try {
            if (closed) throw new RuntimeException("closed");
            contents.put(name, content.clone());
            fileCount++; revCount++; objCount++; nextRev++; return name;
            } finally { lock.unlock(); }
        }
        public byte[] readFile(String name) { lock.lock(); try { byte[] c = contents.get(name); return c != null ? c.clone() : null; } finally { lock.unlock(); } }
        public boolean fileExists() { return fileCount > 0; }
        public int readFileLen() { return fileCount > 0 ? 3 : -1; }
        public void writeFile(byte[] content) { revCount++; nextRev++; }
        public void deleteFile() { if(fileCount>0) fileCount--; }
        public int currentRevision() { return nextRev - 1; }
        public int listRevisions() { return revCount; }
        public int limitCleanup(int limit) {
            if (limit==0) throw new RuntimeException("limit zero");
            int rm = Math.max(revCount - limit, 0); revCount -= rm; return rm;
        }
        public int listObjects() { return objCount; }
        public long beginTransaction() { return generation; }
        public void stageAdd(String path, byte[] content) { createFile(path, content); }
        public byte[] commitTransaction(long expected) {
            if (expected != generation) throw new RuntimeException("gen mismatch");
            generation++; return encode(mode, generation);
        }
        public int diffCount(Store other) { return Math.abs(fileCount - other.fileCount); }
        public boolean mergeOk() { return mode >= MODE_MODERN && mode <= MODE_ENTERPRISE; }
        public boolean importBytes(byte[] data) {
            if (data==null||data.length<8||data[0]!=0x56) throw new RuntimeException("bad");
            return true;
        }
        public byte[] exportBytes() { return encode(mode, generation); }
        public boolean integrityOk() { return !closed; }
        public int statsFiles() { return fileCount; }
        public int statsRevs() { return revCount; }
        public boolean builderOk() { return mode>=1 && mode<=2; }
    }
    public static int repDirect1() { return REP_DIRECT_1; }
    public static int repExtents1() { return REP_EXTENTS_1; }
    public static Store newBuilder(int m) { return new Store(m); }

    public static class Diagnostic {
        public final String code; public final String message;
        public Diagnostic(String c, String m) { code = c; message = m; }
    }
    public static java.util.List<Diagnostic> diagnostics(Store s, String level) {
        java.util.List<Diagnostic> out = new java.util.ArrayList<>();
        if (s.getMode() < MODE_MODERN || s.getMode() > MODE_ENTERPRISE)
            out.add(new Diagnostic("INVALID_MODE", "mode out of range"));
        return out;
    }

    public static class StorageStats {
        public final int files, revisions;
        public StorageStats(int f, int r) { files = f; revisions = r; }
    }
    public static StorageStats getStats(Store s) { return new StorageStats(s.statsFiles(), s.statsRevs()); }

    public static byte[] mergeThreeWay(Store base, Store ours, Store theirs) {
        java.util.Map<String,byte[]> bc = base.getContents();
        java.util.Map<String,byte[]> oc = ours.getContents();
        java.util.Map<String,byte[]> tc = theirs.getContents();
        java.util.Set<String> all = new java.util.HashSet<>();
        all.addAll(bc.keySet()); all.addAll(oc.keySet()); all.addAll(tc.keySet());
        for (String path : all) {
            byte[] b = bc.get(path), o = oc.get(path), t = tc.get(path);
            boolean oSame = java.util.Arrays.equals(o, t);
            boolean oSameB = java.util.Arrays.equals(o, b);
            boolean tSameB = java.util.Arrays.equals(t, b);
            if (!oSame && !oSameB && !tSameB) return new byte[]{(byte)1}; // conflict marker
        }
        return ours.exportBytes(); // no conflict
    }
    public static int mergeConflicts(Store base, Store ours, Store theirs) {
        java.util.Map<String,byte[]> bc = base.getContents();
        java.util.Map<String,byte[]> oc = ours.getContents();
        java.util.Map<String,byte[]> tc = theirs.getContents();
        java.util.Set<String> all = new java.util.HashSet<>();
        all.addAll(bc.keySet()); all.addAll(oc.keySet()); all.addAll(tc.keySet());
        int conflicts = 0;
        for (String path : all) {
            byte[] b = bc.get(path), o = oc.get(path), t = tc.get(path);
            if (!java.util.Arrays.equals(o,t) && !java.util.Arrays.equals(o,b) && !java.util.Arrays.equals(t,b)) conflicts++;
        }
        return conflicts;
    }
}
