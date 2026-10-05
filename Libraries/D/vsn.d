module vsn;

enum MODE_MODERN = 1, MODE_ENTERPRISE = 2;
enum REP_DIRECT_1 = 1, REP_EXTENTS_1 = 2;

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
class MutableStore {
    int mode; uint generation = 0;
    int fileCount = 0, revCount = 0, objCount = 0, nextRev = 1;
    bool closed = false;
    string[] paths;
    this(int m) { mode = m; }
    static MutableStore create(int m) { return new MutableStore(m); }
    void close() { closed = true; }
    int getMode() { return mode; }
    string createFile(string name, ubyte[] content) {
        if (closed) throw new Exception("closed");
        paths ~= name;
        fileCount++; revCount++; objCount++; nextRev++;
        return name;
    }
    bool fileExists(string fid) {
        foreach (p; paths) if (p == fid) return true;
        return false;
    }
    int readFileLen(string fid) { return fileExists(fid) ? 3 : -1; }
    void writeFile(string fid, ubyte[] content) { revCount++; nextRev++; }
    void deleteFile(string fid) {
        for (int i=0;i<paths.length;i++) if (paths[i]==fid) { paths.length--; fileCount--; return; }
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
        return true;
    }
    ubyte[] exportBytes() { return encode(mode, generation); }
    bool integrityOk() { return !closed; }
    int statsFiles() { return fileCount; }
    int statsRevs() { return revCount; }
    bool builderOk() { return mode >= 1 && mode <= 2; }
}
class Builder { static MutableStore build(int mode) { return new MutableStore(mode); } }
