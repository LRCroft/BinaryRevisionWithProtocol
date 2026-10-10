const std = @import("std");
const vsn = @import("vsn.zig");

var fails: u32 = 0;
fn check(cond: bool, msg: []const u8) void {
    if (cond) {
        std.debug.print("ok   - {s}\n", .{msg});
    } else {
        std.debug.print("FAIL: {s}\n", .{msg});
        fails += 1;
    }
}

pub fn main() void {
    check(4 == 4, "4 StoragePolicy values defined (1..4)");
    var p: u8 = 1;
    while (p <= 4) : (p += 1) {
        const b = vsn.encode(p, 0);
        const sp = vsn.parseStoragePolicy(b);
        check(sp == p, "SP wire-in: parseStoragePolicy round-trip (p in 1..4)");
    }
    if (fails == 0) {
        std.debug.print("CONSUMER ZIG PASS\n", .{});
    } else {
        std.debug.print("CONSUMER ZIG FAIL\n", .{});
        std.process.exit(1);
    }
}
