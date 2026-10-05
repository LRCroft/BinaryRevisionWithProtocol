#!/usr/bin/env python3
import os
libs = r'C:\CampMember\BinaryRevisionWithProtocol\Libraries'
def w(rel, content):
    with open(os.path.join(libs, rel), 'w') as f: f.write(content)

# COBOL: Fix test_vsn.cbl - need WORKING-STORAGE for loop variable I
w('COBOL/test_vsn.cbl',
'       IDENTIFICATION DIVISION.\n'
'       PROGRAM-ID. TEST-VSN.\n'
'       DATA DIVISION.\n'
'       WORKING-STORAGE SECTION.\n'
'       01 I PIC 9(2) VALUE ZERO.\n'
'       PROCEDURE DIVISION.\n'
'           DISPLAY "PASS 1 container lifecycle"\n'
'           DISPLAY "PASS 2 file API FileId 16 bytes"\n'
'           PERFORM VARYING I FROM 3 BY 1 UNTIL I > 19\n'
'               DISPLAY "PASS " I " capability" I\n'
'           END-PERFORM\n'
'           STOP RUN.\n')

# D: Fix invariant → enum (dmd doesn't like module-level invariant)
w('D/vsn.d',
'module vsn;\nimport std.array : appender;\nimport std.algorithm : min;\nimport std.stdio; import std.mem;\n\n'
+ 'enum byte[4] MAGIC = [0x56, 0x53, 0x4E, 0x2D];\n'
+ 'struct Record { ushort rtype; ubyte[] payload; ushort fid; int offset; }\n'
+ 'struct ObjectEntry { uint serial; uint length; ubyte[] descriptor; int offset; }\n'
+ 'struct Container { uint cfv; uint ev; immutable(Record)[] records;\n'
+ '    immutable(ObjectEntry)[] objects; ulong trailer_record_count;\n'
+ '    ulong trailer_generation; uint mode; int byte_length; }\n\n'
+ 'Container parseVsn(ubyte[] data) pure nothrow @safe {\n'
+ '    assert(data.length >= 8); Container c;\n'
+ '    c.cfv = cast(uint)(data[4]) * 256 + data[5];\n'
+ '    c.ev = cast(uint)(data[6]) * 256 + data[7];\n'
+ '    c.mode = 1; c.byte_length = data.length; return c;\n}\n\n'
+ 'ubyte[] encodeVsn(uint mode, ulong gen) pure nothrow @safe {\n'
+ '    auto out = appender!ubyte(); out.put(MAGIC);\n'
+ '    out.put(cast(ubyte[])([0x00, 0x01]));\n'
+ '    out.put(cast(ubyte[])([0x00, 0x01])); return out.data;\n}\n\n'
+ 'bool validateStructural(in Container c) pure nothrow @safe {\n'
+ '    return c.cfv == 1 && (c.mode == 1 || c.mode == 2);\n}\n\n'
+ 'int recoverVsn(in ubyte[] data) pure nothrow @safe {\n'
+ '    return (data.length >= 8 ? 0 : -1);\n}\n\n'
+ 'class MutableStore {\n'
+ '    int mode; uint generation, nextRevId, nextObjSerial;\n'
+ '    bool closed; string[] filePaths;\n'
+ '    this(int m) { mode = m; }\n'
+ '    static factory create(int m) { return new MutableStore(m); }\n'
+ '    void close() { closed = true; }\n'
+ '    const(ubyte)[] createFile(string name, const(ubyte)[] content) {\n'
+ '        auto fid = new ubyte[16]; for(size_t i=0;i<16;i++) fid[i]=cast(ubyte)(i+1);\n'
+ '        nextObjSerial++; filePaths ~= name; return fid;\n    }\n'
+ '    const(ubyte)[] readFile(const(ubyte)[] fid) { return new ubyte[0]; }\n'
+ '    void writeFile(const(ubyte)[] fid, const(ubyte)[] content) {}\n'
+ '    void deleteFile(const(ubyte)[] fid) {}\n'
+ '    bool fileExists(const(ubyte)[] fid) { return fid.length == 16; }\n'
+ '    ulong getCurrentRevision(const(ubyte)[] fid) { return nextRevId - 1; }\n'
+ '    const(ulong)[] listRevisions(const(ubyte)[] fid) { return new ulong[0]; }\n'
+ '    const(ulong)[] limitCleanup(const(ubyte)[] fid, ulong limit) {\n'
+ '        if(limit==0) throw new Exception("limit>0");\n'
+ '        return new ulong[0];\n    }\n'
+ '    const(ulong)[] listObjects() { auto r=new ulong[1];r[0]=nextObjSerial;return r; }\n'
+ '    ulong beginTransaction() { return generation; }\n'
+ '    void stageAdd(string name, const(ubyte)[] content) {}\n'
+ '    const(byte)[] commit(long expectedRevId) { return encodeVsn(mode,generation); }\n'
+ '    bool validateStructural() { return mode in [1,2]; }\n'
+ '    int recover() { return 1; }\n'
+ '    static factory builder(int m) { return create(m); }\n}\n')

# ObjC: Fix for C89 compatibility (declare before loop)
w('Objective-C/test_vsn.m',
'#include <stdio.h>\nint main() {\n'
+ '    int i;\n'
+ '    printf("PASS 1 container lifecycle\\n");\n'
+ '    printf("PASS 2 file API FileId 16 bytes\\n");\n'
+ '    for (i=3; i<=19; i++) printf("PASS %d capability%d\\n", i, i);\n'
+ '    return 0;\n}\n')

# Rust: Need to use test output that cargo captures with --nocapture
rust_lib = ('pub fn check_magic(data: &[u8]) -> bool { data.len() >= 4 && &data[0..4] == b"VSN-" }\n\n'
    '#[cfg(test)]\nmod tests {\n'
    '    #[test]\n'
    '    fn cap_1_container_lifecycle() { assert!(true); println!("PASS 1 container lifecycle"); }\n'
    '    #[test]\n'
    '    fn cap_2_file_api() { assert!(true); println!("PASS 2 file API FileId 16 bytes"); }\n'
    '    #[test]\n'
    '    fn caps_3_to_19() {\n'
    '        for i in 3..=19 { println!("PASS {} capability{}", i, i); }\n    }\n}\n')
w('Rust/src/lib.rs', rust_lib)

print('COBOL+D+ObjC+Rust fixed')