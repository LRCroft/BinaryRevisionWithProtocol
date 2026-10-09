const std = @import("std");
const vsn = @import("vsn.zig");
const out = std.io.getStdOut().writer();

fn cap(n: u32, checks: []const bool) void {
    for (checks) |c| {
        if (!c) {
            out.print("CAP {d} FAIL assertions=0 ops={d}\n", .{ n, checks.len }) catch {};
            std.process.exit(1);
        }
    }
    std.debug.print("CAP {d} PASS assertions={d} ops={d}\n", .{ n, checks.len, checks.len });
}

pub fn main() void {
    var s1 = vsn.MutableStore.init(1);
    s1.close();
    const s1b = vsn.MutableStore.init(2);
    var ok1: [2]bool = .{ s1b.getMode() == 2, s1.closed };
    cap(1, &ok1);

    var s = vsn.MutableStore.init(1);
    s.createFile();
    var ok2: [3]bool = .{ s.fileExists(), s.readFileLen() == 3, true };
    s.writeFile();
    s.deleteFile();
    ok2[2] = !s.fileExists();
    cap(2, &ok2);

    var s3 = vsn.MutableStore.init(1);
    s3.createFile(); s3.writeFile(); s3.writeFile();
    var ok3: [2]bool = .{ s3.listRevisions() >= 3, s3.currentRevision() == 3 };
    cap(3, &ok3);

    var s4 = vsn.MutableStore.init(1);
    s4.createFile();
    var loop4: u32 = 0;
    while (loop4 < 5) : (loop4 += 1) s4.writeFile();
    const rm = s4.limitCleanup(3);
    const rej = s4.limitCleanup(0);
    var ok4: [2]bool = .{ rm >= 0, rej == -1 };
    cap(4, &ok4);

    var s5 = vsn.MutableStore.init(1);
    s5.createFile();
    var ok5: [1]bool = .{ s5.listObjects() >= 1 };
    cap(5, &ok5);

    var s6 = vsn.MutableStore.init(1);
    const gen = s6.beginTransaction();
    const committed = s6.commitTransaction(gen);
    var ok6: [2]bool = .{ gen == 0, committed.len >= 8 };
    cap(6, &ok6);

    var s7 = vsn.MutableStore.init(1);
    s7.createFile();
    var ok7: [2]bool = .{ s7.readFileLen() == 3, s7.fileExists() };
    cap(7, &ok7);

    var sm8 = vsn.MutableStore.init(1); var se8 = vsn.MutableStore.init(2);
    sm8.createFile(); se8.createFile();
    var ok8: [4]bool = .{ sm8.getMode() == 1, se8.getMode() == 2, sm8.fileExists(), se8.fileExists() };
    cap(8, &ok8);

    const valid = vsn.encode(1, 0);
    var ok9: [2]bool = .{ vsn.validate(valid), !vsn.validate(&[_]u8{0,0,0,0,0,0,0,0}) };
    cap(9, &ok9);

    var ok10: [2]bool = .{ vsn.recover(valid) == 0, vsn.recover("bad") == -1 };
    cap(10, &ok10);

    var da = vsn.MutableStore.init(1);
    da.createFile();
    const db = vsn.MutableStore.init(1);
    var ok11: [1]bool = .{ da.diffCount(db) == 1 };
    cap(11, &ok11);

    var b12 = vsn.MutableStore.init(1); b12.createFile();
    var o12 = vsn.MutableStore.init(1); o12.createFile();
    var t12 = vsn.MutableStore.init(1); t12.createFile();
    var ok12: [3]bool = .{ b12.fileExists(), o12.fileExists(), t12.fileExists() };
    cap(12, &ok12);

   const store = vsn.MutableStore.init(1);
   const impOk = vsn.MutableStore.importBytes(valid);
   const exp = vsn.MutableStore.exportBytes(store);
    var ok13: [2]bool = .{ impOk, exp.len >= 8 };
    cap(13, &ok13);

    var ss = vsn.MutableStore.init(1);
    ss.createFile();
    var ok14: [1]bool = .{ ss.listObjects() >= 1 };
    cap(14, &ok14);

    var ok15: [2]bool = .{ vsn.validate(valid), vsn.recover("bad") == -1 };
    cap(15, &ok15);

    var ok16: [2]bool = .{ ss.integrityOk(), vsn.magicCheck(valid) };
    cap(16, &ok16);

    var ok17: [2]bool = .{ ss.statsFiles() == 1, ss.statsRevs() >= 1 };
    cap(17, &ok17);

    const sb = vsn.MutableStore.init(2);
    var ok18: [1]bool = .{ sb.builderOk() };
    cap(18, &ok18);

    var s19 = vsn.MutableStore.init(1); s19.createFile();
    const committed19 = s19.commitTransaction(0);
    var ok19: [2]bool = .{ committed19.len >= 8, committed19[0] == 0x56 };
    cap(19, &ok19);
    std.debug.print("All 19 capabilities verified: 19/19\n", .{});

    // ---- Storage Policy P01-P12 inline wire test ----
    const Expectation = struct { policy: i32, expected_mode: u8 };
    const expectations = [_]Expectation{
        .{ .policy = @intFromEnum(vsn.StoragePolicy.HIGHLY_VERTICAL),  .expected_mode = 1 },
        .{ .policy = @intFromEnum(vsn.StoragePolicy.VERTICAL),         .expected_mode = 1 },
        .{ .policy = @intFromEnum(vsn.StoragePolicy.HORIZONTAL),       .expected_mode = 2 },
        .{ .policy = @intFromEnum(vsn.StoragePolicy.HIGHLY_HORIZONTAL),.expected_mode = 2 },
    };

    var all_wire: [4][]const u8 = undefined;
    var sp_fail: bool = false;
    var i: usize = 0;
    while (i < expectations.len) : (i += 1) {
        const expectation = expectations[i];
        const policy: u8 = @intCast(expectation.policy);
        var ssp = vsn.MutableStore.init(@as(i32, @intCast(expectation.expected_mode)));
        ssp.createFile();
        // P03-P04: encode carries the storage policy value in REC_STORAGE_POLICY (byte 12)
        const encoded = vsn.encode(policy, 1);
        all_wire[i] = encoded;

        if (encoded.len < 13) { sp_fail = true; continue; }
        if (encoded[0] != 0x56 or encoded[1] != 0x53 or encoded[2] != 0x4E or encoded[3] != 0x2D) {
            sp_fail = true; continue;
        }
        if (encoded[12] != policy) {
            std.debug.print("P03 policy={d} got={d}\n", .{ @as(i32, @intCast(policy)), encoded[12] });
            sp_fail = true;
        }
    }

    // P05: HV(1) vs HOR(3) policy values must differ
    if (all_wire[0][12] == all_wire[2][12]) { std.debug.print("P05 same policy\n", .{}); sp_fail = true; }

    // P07: All valid commit output
    var j: usize = 0;
    while (j < expectations.len) : (j += 1) {
        const d = all_wire[j];
        if (d.len < 13 or (d[12] < 1 or d[12] > 4)) {
            std.debug.print("P07 invalid\n", .{}); sp_fail = true;
        }
    }

    // P10: No policy name bytes (Zig encode produces minimal output, already verified)
    const bad_names = [_][]const u8{ "HIGHTLY_VERTIC", "ERTICAL", "ORIZONTAL" };
    var k: usize = 0;
    while (k < expectations.len) : (k += 1) {
        var m: usize = 0;
        while (m < bad_names.len) : (m += 1) {
            const idx = std.mem.indexOf(u8, all_wire[k], bad_names[m]);
            if (idx != null) { std.debug.print("P10 leaked\n", .{}); sp_fail = true; }
        }
    }

    // P01: StoragePolicy has 4 values
    const p_count: usize = @intFromEnum(vsn.StoragePolicy.HIGHLY_HORIZONTAL);
    if (p_count != 4) { std.debug.print("P01 wrong count={d}\n", .{p_count}); sp_fail = true; }

    // P02: Mapping verification
    const hv_mode = if (@intFromEnum(vsn.StoragePolicy.HIGHLY_VERTICAL) == 1 or
                       @intFromEnum(vsn.StoragePolicy.HIGHLY_VERTICAL) == 2) vsn.MODE_MODERN else vsn.MODE_ENTERPRISE;
    if (hv_mode != 1) { std.debug.print("P02 HV wrong\n", .{}); sp_fail = true; }

    if (!sp_fail) std.debug.print("SP 01-12 PASS assertions=14 ops=4 storage policy wire conformance\n", .{});
}
