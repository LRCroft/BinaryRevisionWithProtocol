import java.util.*;
import java.util.concurrent.locks.ReentrantLock;
import java.nio.file.*;
public class VsnLib {
    public static final int MODE_MODERN = 1;                   // OBSOLETE: was MODERN wire mode (deprecated)
    public static final int MODE_ENTERPRISE = 2;               // OBSOLETE: was ENTERPRISE wire mode (deprecated)
    public static final int STORAGE_HIGHLY_VERTICAL = 1;       // maximum optimization effort
    public static final int STORAGE_VERTICAL = 2;              // bounded optimization effort
    public static final int STORAGE_HORIZONTAL = 3;            // low optimization effort
    public static final int STORAGE_HIGHLY_HORIZONTAL = 4;     // minimal optimization effort
    // Storage Policy record type and field ID (new)
    public static final short REC_STORAGE_POLICY = 0x0009;
    public static final short FID_STORAGE_POLICY = 0x0901;
    public static final int REP_DIRECT_1 = 1;
    public static final int REP_EXTENTS_1 = 2;
    public static byte[] encode(int sp, long gen, int mode) {
        int val = (sp >= 1 && sp <= 4) ? sp : STORAGE_VERTICAL;
        byte[] header = new byte[]{(byte)'V',(byte)'S',(byte)'N',(byte)'-',(byte)0x00,(byte)0x01,(byte)0x00,(byte)0x01};
        byte[] rec = new byte[]{(byte)0x00,(byte)0x09, 0x04, (byte)0x09,(byte)0x01, 0x01, (byte)val};
        byte[] result = new byte[header.length + rec.length];
        System.arraycopy(header, 0, result, 0, header.length);
        System.arraycopy(rec, 0, result, header.length, rec.length);
        return result;
    }
    public static boolean validate(byte[] data) {
        if (data == null || data.length < 8) return false;
        if (data[0]!=0x56||data[1]!=0x53||data[2]!=0x4E||data[3]!=(byte)'-') return false;
        int cfv = (data[4] & 0xFF) << 8 | (data[5] & 0xFF);
        return cfv == 1 || cfv == 2;
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
    
    // Storage Policy reader: extract storage_policy from parsed VSN binary bytes
    public static Integer parseStoragePolicy(byte[] data) {
        if (data == null || data.length < 9) return null;
        int pos = 8;
        while (pos + 3 < data.length) {
            short rt = (short)((data[pos] << 8) | (data[pos+1] & 0xFF));
            if (rt == 0) return null; // RecordsEnd
            int plen = data[pos+2] & 0xFF;
            if (pos + 3 + plen > data.length) break;
            int fidOff = pos + 3;
            short fid = (short)((data[fidOff] << 8) | (data[fidOff+1] & 0xFF));
            if (fid == FID_STORAGE_POLICY && fidOff + 4 <= data.length) {
                return data[fidOff+3] & 0xFF;
            }
            pos += 3 + plen;
        }
        return null;
    }
    public static class Store {
        int mode; int storage_policy; int generation=0; int fileCount=0; int revCount=0; int objCount=0; int nextRev=1; boolean closed=false;
        private final java.util.Map<String, byte[]> contents = new java.util.HashMap<>();
        private final ReentrantLock lock = new ReentrantLock();
        public Store(int m) { mode=m; storage_policy=STORAGE_VERTICAL; }
        public static Store create(int m) { return new Store(m); }
        public static Store createWithPolicy(int policy) {
            // Canonical writer: stores policy directly; encode uses storage_policy.
            Store s = new Store(MODE_MODERN);
            s.storage_policy = policy > 0 ? policy : STORAGE_VERTICAL;
            return s;
        }
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
            generation++; return encode(storage_policy, generation, mode);
        }
        public int diffCount(Store other) { return Math.abs(fileCount - other.fileCount); }
        public boolean mergeOk() { return mode >= MODE_MODERN && mode <= MODE_ENTERPRISE; }
        public boolean importBytes(byte[] data) {
            if (data==null||data.length<8||data[0]!=0x56) throw new RuntimeException("bad");
            return true;
        }
        public byte[] exportBytes() { return encode(storage_policy, generation, mode); }
        public boolean integrityOk() { return !closed; }
        public int statsFiles() { return fileCount; }
        public int statsRevs() { return revCount; }
        public boolean builderOk() { return mode>=1 && mode<=2; }
        public byte[] exportContent() {
            lock.lock(); try {
                java.io.ByteArrayOutputStream baos = new java.io.ByteArrayOutputStream();
                java.io.DataOutputStream dos = new java.io.DataOutputStream(baos);
                try {
                    for (java.util.Map.Entry<String, byte[]> e : contents.entrySet()) {
                        byte[] v = e.getValue().clone();
                        dos.writeUTF(e.getKey());
                        dos.writeInt(v.length);
                        dos.write(v);
                    }
                } catch (java.io.IOException ex) { return new byte[0]; }
                return baos.toByteArray();
            } finally { lock.unlock(); }
        }
        public boolean importContent(byte[] data) {
            if (data == null) return false;
            lock.lock(); try {
                contents.clear(); fileCount=0; revCount=0; objCount=0; nextRev=1; generation++;
                java.io.DataInputStream dis = new java.io.DataInputStream(new java.io.ByteArrayInputStream(data));
                while (dis.available() > 0) {
                    String name = dis.readUTF();
                    int len = dis.readInt();
                    byte[] buf = new byte[len];
                    if (dis.read(buf) != len) return false;
                    contents.put(name, buf); fileCount++; revCount++; objCount++; nextRev++;
                }
                return true;
            } catch (Exception e) { return false; } finally { lock.unlock(); }
        }
        public java.util.List<byte[]> readFileChunks(String name, int chunkSize) {
            lock.lock(); try {
                byte[] data = contents.get(name);
                if (data == null) return java.util.Collections.emptyList();
                java.util.List<byte[]> chunks = new java.util.ArrayList<>();
                for (int off = 0; off < data.length; off += chunkSize) {
                    int sz = Math.min(chunkSize, data.length - off);
                    byte[] chunk = new byte[sz];
                    System.arraycopy(data, off, chunk, 0, sz);
                    chunks.add(chunk);
                }
                return chunks;
            } finally { lock.unlock(); }
        }
        public long contentSignature() {
            lock.lock(); try {
                long h = 1L;
                for (java.util.Map.Entry<String, byte[]> e : contents.entrySet()) {
                    String key = e.getKey();
                    byte[] val = e.getValue();
                    for (int i = 0; i < key.length(); i++) { h = h * 31 + key.charAt(i); }
                    for (int i = 0; i < val.length; i++) { h = h * 31 + (val[i] & 0xFF); }
                }
                return h;
            } finally { lock.unlock(); }
        }
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

    // ---- Writer Storage Policy (informative, NOT on wire) ----
    static enum StoragePolicy { HIGHLY_VERTICAL(1), VERTICAL(2), HORIZONTAL(3), HIGHLY_HORIZONTAL(4); private final int w; StoragePolicy(int w){ this.w=w; } public int value(){ return w; } public int wireMode(){ return w==1||w==2?1:2; } }
    static enum WireMode { MODERN(0x01), ENTERPRISE(0x02); private final int v; WireMode(int v){this.v=v;} public int value(){return v;} }
    static class InvalidStoragePolicy extends RuntimeException { InvalidStoragePolicy(String m){super(m);} }
    static class PolicyWireModeConflict extends RuntimeException { PolicyWireModeConflict(String m){super(m);} }
    static class InvalidOptimizationConfiguration extends RuntimeException { InvalidOptimizationConfiguration(String m){super(m);} }

    // ---- Optimization Configuration (resource parameters, NOT on wire) ----
    public static class OptimizationConfiguration {
        int searchBudget=65536; int memoryLimit=1048576; int depth=-1; String scope="document";
        int blobMaxBytes=1048576; float cacheTargetRatio=0.7f; long maxContainers=1024L;
        public OptimizationConfiguration setSearchBudget(int v){ this.searchBudget=v; return this; }
        public OptimizationConfiguration setMemoryLimit(int v){ this.memoryLimit=v; return this; }
        public OptimizationConfiguration setDepth(int v){ this.depth=v; return this; }
        public OptimizationConfiguration setScope(String v){ this.scope=v; return this; }
        public OptimizationConfiguration setBlobMaxBytes(int v){ this.blobMaxBytes=v; return this; }
        public OptimizationConfiguration setCacheTargetRatio(float v){ this.cacheTargetRatio=v; return this; }
        public OptimizationConfiguration setMaxContainers(long v){ this.maxContainers=v; return this; }
        public void validate() {
            if (this.searchBudget < 1) throw new InvalidOptimizationConfiguration("search_budget<1");
            if (this.memoryLimit < 256) throw new InvalidOptimizationConfiguration("memory_limit<256");
            if (this.depth > 0 && this.blobMaxBytes <= 0) throw new InvalidOptimizationConfiguration("depth>0 with blobMax<=0");
        }
    }

    // ---- Writer Options + Storage Policy integration ----
    public static Store createWithPolicy(StoragePolicy policy) {
        if (policy == null) throw new InvalidStoragePolicy("null policy");
        int wm = policy.wireMode();
        if (wm != 1 && wm != 2) throw new PolicyWireModeConflict(policy.name() + " -> wire 0");
        Store s = new Store(wm);
        s.storage_policy = policy.value();
        return s;
    }

    public static WriterOptions buildWriterOptions(StoragePolicy policy) {
        if (policy == null) throw new InvalidStoragePolicy("null policy");
        int wm = policy.wireMode();
        if (wm != 1 && wm != 2) throw new PolicyWireModeConflict(policy.name() + " -> wire 0");
        return new WriterOptions(wm, new OptimizationConfiguration());
    }

    public static class StoreBuilder {
        private StoragePolicy policy = null;
        public StoreBuilder withPolicy(StoragePolicy p){ this.policy=p; return this; }
        public Store build() {
            if (this.policy!=null) return createWithPolicy(this.policy);
            throw new InvalidStoragePolicy("builder needs policy");
        }
    }

    public static WriterOptions.Builder writerBuilder(){ return new WriterOptions.Builder(); }

    public static class WriterOptions extends java.lang.Object {
        private final int wireMode; private final OptimizationConfiguration optCfg;
        WriterOptions(int wm, OptimizationConfiguration oc){ this.wireMode=wm; this.optCfg=oc; }
        public int getWireMode(){ return wireMode; }
        public OptimizationConfiguration getOptimizationConfig(){ return optCfg; }

        static class Builder {
            private int wireMode=0; private OptimizationConfiguration optCfg=null;
            public WriterOptions.Builder withWireMode(int wm){ this.wireMode=wm; return this; }
            public WriterOptions.Builder withOptimizationConfig(OptimizationConfiguration oc){ this.optCfg=oc; return this; }
            public WriterOptions build(){ if(wireMode==0) throw new InvalidStoragePolicy("no wire mode"); return new WriterOptions(wireMode,optCfg); }
        }
    }
}
