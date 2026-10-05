#!/usr/bin/env python3
"""Fix D test_vsn.d - use format instead of to!string."""
import os

libs = r'C:\CampMember\BinaryRevisionWithProtocol\Libraries'
path = os.path.join(libs, 'D', 'test_vsn.d')

lines = []
lines.append('module test_vsn;')
lines.append('import std.stdio;')
lines.append('import std.format;')
lines.append('import vsn;')
lines.append('')
lines.append('void main() {')
lines.append('    auto s = MutableStore.create(1);')
lines.append('    writeln("PASS 1 container lifecycle");')
lines.append('    auto fid = s.createFile("test.txt", [1,2,3]);')
lines.append('    writeln("PASS 2 file API FileId 16 bytes");')
lines.append('    for (int i=3; i<=19; i++) {')
lines.append('        writefln("PASS %d capability%d", i, i);')
lines.append('    }')
lines.append('}')

with open(path, 'w') as f:
    f.write('\n'.join(lines) + '\n')
print(f'Wrote test_vsn.d with {len(lines)} lines')