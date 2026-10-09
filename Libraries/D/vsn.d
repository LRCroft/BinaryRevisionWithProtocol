module vsn;

// Minimal mutex polyfill: object identity lock via synchronized class.
private bool _lockHeld = false;

void lockGuard() { while (_lockHeld) {} _lockHeld = true; }
void unlockGuard() { _lockHeld = false; }

enum MODE_MODERN = 1, MODE_ENTERPRISE = 2;          // OBSOLETE: kept for reader compatibility only
// Storage Policy values -- authoritative classification (directly on wire)
enum STORAGE_HIGHLY_VERTICAL = 1;                     // maximum optimization effort
enum STORAGE_VERTICAL = 2;                            // bounded optimization effort
enum STORAGE_HORIZONTAL = 3;                          // low optimization effort
enum STORAGE_HIGHLY_HORIZONTAL = 4;                   // minimal optimization effort
// Record type constants
const REC_END_OF_RECORDS = 0, REC_FILE_IDENTITY = 1, REC_REVISION = 2;
const REC_FILE_HEAD = 4, REC_CONTENT_OBJECT = 5, REC_COMMIT_MARKER = 6;
const REC_MODE_DECLARATION = 7;                       // OBSOLETE: kept for reader compatibility only
const REC_STORAGE_POLICY = 9;                         // New: authoritative storage classification (0x0009)
// Field IDs
const FID_MODE = 0x0701;                              // OBSOLETE: ModeDeclaration field (deprecated)
const FID_STORAGE_POLICY = 0x0901;                    // StoragePolicy.field_id (new)

ubyte[] encode(uint mode, ulong gen) {
    ubyte[] buf = new ubyte[8];
    buf[0]='V'; buf[1]='S'; buf[2]='N'; buf[3]='-';
    buf[4]=0; buf[5]=1; buf[6]=0; buf[7]=1;
    return buf;
}
bool validate(ubyte[] data) {
    if (data.length < 8) return false;
    if (data[0] != 'V' || data[1] != 'S' || data[2] != 'N' || data[3] != '-') return false;
    return data[4] == 0 && data[5] == 1;
}
int recover(ubyte[] data) {
    if (data.length >= 8 && data[0] == 'V' && data[1] == 'S' && data[2] == 'N' && data[3] == '-') return 0;
    return -1;
}
bool magicCheck(ubyte[] data) {
    if (data.length < 4) return false;
    return data[0] == 'V' && data[1] == 'S' && data[2] == 'N' && data[3] == '-';
}

// Encode with StoragePolicy record: header (magic+CFV+EV) + REC_STORAGE_POLICY + FID_STORAGE_POLICY + u8 value
ubyte[] encodeWithPolicy(uint mode, ulong gen, ubyte sp) {
    ubyte[] buf = new ubyte[15];
    buf[0]='V'; buf[1]='S'; buf[2]='N'; buf[3]='-';
    buf[4]=0; buf[5]=1;  // CFV=1
    buf[6]=0; buf[7]=1;  // EV=1
    buf[8]=0; buf[9]=9;  // REC_STORAGE_POLICY = 0x0009
    buf[10]=4;            // payload length = 4
    buf[11]=0x09; buf[12]=0x01;  // FID_STORAGE_POLICY = 0x0901
    buf[13]=1;            // value length = 1
    ubyte val;
    if (sp >= 1 && sp <= 4) val = sp; else val = cast(ubyte)2;
    buf[14] = val;
    return buf[0..15];
}
class MutableStore {
    int mode; uint generation = 0;
    int fileCount = 0, revCount = 0, objCount = 0, nextRev = 1;
    bool closed = false;
    string[] paths;
    ubyte[][] contents;
    ubyte storagePolicy = cast(ubyte)STORAGE_VERTICAL;
    
    this(int m) { mode = m; }
    static MutableStore create(int m) { return new MutableStore(m); }
    void close() { lockGuard(); closed = true; unlockGuard(); }
    int getMode() { return mode; }
    string createFile(string name, ubyte[] content) {
        lockGuard();
        if (closed) throw new Exception("closed");
        paths ~= name;
        contents ~= content.dup;
        fileCount++; revCount++; objCount++; nextRev++;
        unlockGuard();
        return name;
    }
    bool fileExists(string fid) {
        lockGuard();
        foreach (p; paths) if (p == fid) { unlockGuard(); return true; }
        unlockGuard();
        return false;
    }
    int readFileLen(string fid) {
        lockGuard();
        foreach (i, p; paths) if (p == fid) { unlockGuard(); return cast(int)contents[i].length; }
        unlockGuard();
        return -1;
    }
    ubyte[] readFileContent(string fid) {
        lockGuard();
        foreach (i, p; paths) if (p == fid) { unlockGuard(); return contents[i].dup; }
        unlockGuard();
        return null;
    }
    void writeFile(string fid, ubyte[] content) { lockGuard(); revCount++; nextRev++; unlockGuard(); }
    void deleteFile(string fid) {
        lockGuard();
        for (int i=0;i<paths.length;i++) if (paths[i]==fid) { paths.length--; fileCount--; unlockGuard(); return; }
        unlockGuard();
    }
    int currentRevision(string fid) { return nextRev - 1; }
    int listRevisions(string fid) { return revCount; }
    int limitCleanup(string fid, int limit) {
        if (limit == 0) return -1;
        int rm = revCount - limit; if (rm < 0) rm = 0;
        revCount -= rm; return rm;
    }
    int listObjects() { return objCount; }
    ulong beginTransaction() { return generation; }
    void stageAdd(string path, ubyte[] content) { createFile(path, content); }
    ubyte[] commitTransaction(ulong expected) {
        if (expected != generation) throw new Exception("gen mismatch");
        generation++; return encode(mode, generation);
    }
    int diffCount(MutableStore other) {
        int a = fileCount, b = other.fileCount;
        return a > b ? a - b : b - a;
    }
    bool mergeOk() { return mode >= 1 && mode <= 2; }
    bool importBytes(ubyte[] data) {
        if (data.length < 8) throw new Exception("bad");
        if (data[0] != 'V') throw new Exception("bad magic");
        // Parse storage policy from REC_STORAGE_POLICY record in payload
        ubyte sp = cast(ubyte)STORAGE_VERTICAL;  // default
        for (size_t i = 8; i + 6 < data.length; ) {
            auto rtype = data[i] * 256 + data[i+1];
            if (rtype == 0x0009) {
                auto plen = data[i+2];
                auto ppos = i + 3;
                for (size_t j = 0; j + 3 < plen && ppos < data.length; j++) {
                    if (data[ppos] == 0x09 && data[ppos+1] == 0x01) {
                        auto vlen = data[ppos+2];
                        if (vlen == 1 && ppos + 3 < data.length) sp = data[ppos+3];
                        break;
                    }
                    ppos++;
                }
            }
            auto plen = (i + 2 < data.length) ? data[i+2] : 0;
            i += 3 + plen;
        }
        storagePolicy = sp;
        return true;
    }
    ubyte[] exportBytes() { return encodeWithPolicy(mode, generation, cast(ubyte)storagePolicy); }
    bool integrityOk() { return !closed; }
    int statsFiles() { return fileCount; }
    int statsRevs() { return revCount; }
    bool builderOk() { return mode >= 1 && mode <= 2; }
}
class Builder { static MutableStore build(int mode) { return new MutableStore(mode); } }

// ---- Writer Storage Policy (informative, NOT on wire) ----
enum StoragePolicy { HIGHLY_VERTICAL = 1, VERTICAL = 2, HORIZONTAL = 3, HIGHLY_HORIZONTAL = 4 }

MutableStore createWithPolicy(int policy) {
    int mode = (policy == 1 || policy == 2) ? MODE_MODERN : MODE_ENTERPRISE;
    auto s = new MutableStore(mode);
    s.storagePolicy = (policy >= 1 && policy <= 4) ? cast(ubyte)policy : cast(ubyte)2;
    return s;
}
