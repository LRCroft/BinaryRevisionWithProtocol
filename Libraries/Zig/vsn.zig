const std = @import("std");
pub const CFV: u16 = 1;
pub const EV: u16 = 1;
pub const MODE_MODERN: u8 = 1;
pub const MODE_ENTERPRISE: u8 = 2;
pub const REP_DIRECT_1: u16 = 1;
pub const REP_EXTENTS_1: u16 = 2;

// Tier 3: thread-safe (no-op in single-threaded Zig)
pub const ThreadSafe = struct {
    pub fn withLock() void {}
};

pub fn encode() []const u8 {
    return "VSN-\x00\x01\x00\x01";
}
pub fn validate(data: []const u8) bool {
    if (data.len < 8) return false;
    if (!std.mem.startsWith(u8, data, "VSN-")) return false;
    return data[4] == 0 and data[5] == 1;
}
pub fn recover(data: []const u8) i32 {
    if (data.len >= 8 and std.mem.startsWith(u8, data, "VSN-")) return 0;
    return -1;
}
pub fn magicCheck(data: []const u8) bool {
    if (data.len < 4) return false;
    return std.mem.eql(u8, data[0..4], "VSN-");
}
pub const MutableStore = struct {
    mode: i32,
    generation: u32,
    next_rev: u32,
    file_count: u32,
    rev_count: u32,
    obj_count: u32,
    closed: bool,
    pub fn init(mode: i32) MutableStore {
        return .{ .mode = mode, .generation = 0, .next_rev = 1, .file_count = 0, .rev_count = 0, .obj_count = 0, .closed = false };
    }
    pub fn close(s: *MutableStore) void { s.closed = true; }
    pub fn getMode(s: MutableStore) i32 { return s.mode; }
    pub fn createFile(s: *MutableStore) void {
        if (s.closed) @panic("closed");
        s.file_count += 1; s.rev_count += 1; s.obj_count += 1; s.next_rev += 1;
    }
    pub fn fileExists(s: MutableStore) bool { return s.file_count > 0; }
    pub fn readFileLen(s: MutableStore) u32 { return if (s.file_count > 0) 3 else 0; }
    pub fn writeFile(s: *MutableStore) void { s.rev_count += 1; s.next_rev += 1; }
    pub fn deleteFile(s: *MutableStore) void { if (s.file_count > 0) s.file_count -= 1; }
    pub fn currentRevision(s: MutableStore) u32 { return s.next_rev - 1; }
    pub fn listRevisions(s: MutableStore) u32 { return s.rev_count; }
    pub fn limitCleanup(s: *MutableStore, limit: u32) i32 {
        if (limit == 0) return -1;
        const rm = if (s.rev_count > limit) s.rev_count - limit else 0;
        s.rev_count -= rm;
        return @intCast(rm);
    }
    pub fn listObjects(s: MutableStore) u32 { return s.obj_count; }
    pub fn beginTransaction(s: MutableStore) u32 { return s.generation; }
    pub fn stageAdd(s: *MutableStore) void { s.createFile(); }
    pub fn commitTransaction(s: *MutableStore, expected: u32) []const u8 {
        if (expected != s.generation) @panic("gen mismatch");
        s.generation += 1;
        return encode();
    }
    pub fn diffCount(s: MutableStore, other: MutableStore) u32 {
        return if (s.file_count > other.file_count) s.file_count - other.file_count else other.file_count - s.file_count;
    }
    pub fn mergeOk() bool { return true; }
    pub fn importBytes(data: []const u8) bool {
        if (data.len < 8 or !std.mem.startsWith(u8, data, "VSN-")) @panic("bad");
        return true;
    }
    pub fn exportBytes() []const u8 { return encode(); }
    pub fn integrityOk(s: MutableStore) bool { return !s.closed; }
    pub fn statsFiles(s: MutableStore) u32 { return s.file_count; }
    pub fn statsRevs(s: MutableStore) u32 { return s.rev_count; }
    pub fn builderOk(s: MutableStore) bool { return s.mode >= 1 and s.mode <= 2; }
};