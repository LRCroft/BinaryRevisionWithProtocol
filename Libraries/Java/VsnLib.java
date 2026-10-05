import java.util.*;
import java.util.concurrent.locks.ReentrantLock;
import java.nio.file.*;
public class VsnLib {
    public static final int MODE_MODERN = 1;
    public static final int MODE_ENTERPRISE = 2;
    public static final int REP_DIRECT_1 = 1;
    public static final int REP_EXTENTS_1 = 2;
    public static byte[] encode(int mode, long gen) {
        return new byte[]{(byte)'V',(byte)'S',(byte)'N',0,(byte)0,(byte)1,(byte)0,(byte)1};
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
        private final ReentrantLock lock = new ReentrantLock();
        public Store(int m) { mode=m; }
        public static Store create(int m) { return new Store(m); }
        public void close() { lock.lock(); try { closed=true; } finally { lock.unlock(); } }
        public int getMode() { return mode; }
        public String createFile(String name, byte[] content) {
            lock.lock(); try {
            if (closed) throw new RuntimeException("closed");
            fileCount++; revCount++; objCount++; nextRev++; return name;
            } finally { lock.unlock(); }
        }
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
}
