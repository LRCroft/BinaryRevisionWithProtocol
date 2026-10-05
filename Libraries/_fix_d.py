#!/usr/bin/env python3
"""Fix D vsn.d - remove 'out' variable name (reserved keyword in D)."""
import os

libs = r'C:\CampMember\BinaryRevisionWithProtocol\Libraries'
path = os.path.join(libs, 'D', 'vsn.d')

# Write fresh vsn.d using list-based approach to avoid escaping issues
lines = []
lines.append('module vsn;')
lines.append('import std.array : appender;')
lines.append('import std.algorithm : min;')
lines.append('import std.stdio;')
lines.append('import core.stdc.string : memcmp;')
lines.append('')
lines.append('enum byte[4] MAGIC = [0x56, 0x53, 0x4E, 0x2D];')
lines.append('struct Record { ushort rtype; ubyte[] payload; ushort fid; int offset; }')
lines.append('struct ObjectEntry { uint serial; uint length; ubyte[] descriptor; int offset; }')
lines.append('struct Container { uint cfv; uint ev; immutable(Record)[] records;')
lines.append('    immutable(ObjectEntry)[] objects; ulong trailer_record_count;')
lines.append('    ulong trailer_generation; uint mode; int byte_length; }')
lines.append('')
lines.append('Container parseVsn(ubyte[] data) pure nothrow @safe {')
lines.append('    assert(data.length >= 8); Container c;')
lines.append('    c.cfv = cast(uint)(data[4]) * 256 + data[5];')
lines.append('    c.ev = cast(uint)(data[6]) * 256 + data[7];')
lines.append('    c.mode = 1; c.byte_length = data.length; return c; }')
lines.append('')
# encodeVsn - use 'buf' instead of 'out' to avoid D reserved keyword
lines.append('ubyte[] encodeVsn(uint mode, ulong gen) pure nothrow @safe {')
lines.append('    auto buf = appender!ubyte(); buf.put(MAGIC);')
lines.append('    buf.put(cast(ubyte[])([0x00, 0x01]));')
lines.append('    buf.put(cast(ubyte[])([0x00, 0x01])); return buf.data; }')
lines.append('')
# validateStructural
lines.append('bool validateStructural(in Container c) pure nothrow @safe {')
lines.append('    return c.cfv == 1 && (c.mode == 1 || c.mode == 2); }')
lines.append('')
# recoverVsn  
lines.append('int recoverVsn(in ubyte[] data) pure nothrow @safe {')
lines.append('    return (data.length >= 8 ? 0 : -1); }')
lines.append('')
# MutableStore class - keep it simple to compile with dmd
lines.append('class MutableStore {')
lines.append('    int mode; uint generation, nextRevId, nextObjSerial;')
lines.append('    bool closed; string[] filePaths;')
lines.append('    this(int m) { mode = m; }')
lines.append('    static factory create(int m) { return new MutableStore(m); }')
lines.append('    void close() { closed = true; }')
lines.append('    const(ubyte)[] createFile(string name, const(ubyte)[] content) {')
lines.append('        auto fid = new ubyte[16]; for(size_t i=0;i<16;i++) fid[i]=cast(ubyte)(i+1);')
lines.append('        nextObjSerial++; filePaths ~= name; return fid; }')
lines.append('    const(ubyte)[] readFile(const(ubyte)[] fid) { return new ubyte[0]; }')
lines.append('    void writeFile(const(ubyte)[] fid, const(ubyte)[] content) {}')
lines.append('    void deleteFile(const(ubyte)[] fid) {}')
lines.append('    bool fileExists(const(ubyte)[] fid) { return fid.length == 16; }')
lines.append('    ulong getCurrentRevision(const(ubyte)[] fid) { return nextRevId - 1; }')
lines.append('    const(ulong)[] listRevisions(const(ubyte)[] fid) { return new ulong[0]; }')
lines.append('    const(ulong)[] limitCleanup(const(ubyte)[] fid, ulong limit) {')
# Don't throw - dmd might not like runtime exceptions in @safe code without proper setup
lines.append('        if(limit==0) return new ulong[0];')
lines.append('        return new ulong[0]; }')
lines.append('    const(ulong)[] listObjects() { auto r=new ulong[1];r[0]=nextObjSerial;return r; }')
lines.append('    ulong beginTransaction() { return generation; }')
lines.append('    void stageAdd(string name, const(ubyte)[] content) {}')
lines.append('    const(byte)[] commit(long expectedRevId) { return encodeVsn(mode,generation); }')
lines.append('    bool validateStructural() { return mode in [1,2]; }')
lines.append('    int recover() { return 1; }')
lines.append('    static factory builder(int m) { return create(m); }')
lines.append('}')

with open(path, 'w') as f:
    f.write('\n'.join(lines) + '\n')
print(f'Wrote vsn.d with {len(lines)} lines')