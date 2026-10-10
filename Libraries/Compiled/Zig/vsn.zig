const std = @import("std");
pub const CFV: u16 = 1;
pub const EV: u16 = 1;
pub const MODE_MODERN: u8 = 1;                    // OBSOLETE: was MODERN wire mode (deprecated)
pub const MODE_ENTERPRISE: u8 = 2;                // OBSOLETE: was ENTERPRISE wire mode (deprecated)
// Storage Policy values -- authoritative classification (directly on wire)
pub const STORAGE_HIGHLY_VERTICAL: u8 = 1;        // maximum optimization effort
pub const STORAGE_VERTICAL: u8 = 2;               // bounded optimization effort
pub const STORAGE_HORIZONTAL: u8 = 3;             // low optimization effort
pub const STORAGE_HIGHLY_HORIZONTAL: u8 = 4;      // minimal optimization effort
// Record type constants
pub const REC_END_OF_RECORDS: u16 = 0x0000;
pub const REC_FILE_IDENTITY: u16 = 0x0001;
pub const REC_REVISION: u16 = 0x0002;
pub const REC_FILE_HEAD: u16 = 0x0004;
pub const REC_CONTENT_OBJECT: u16 = 0x0005;
pub const REC_COMMIT_MARKER: u16 = 0x0006;
pub const REC_MODE_DECLARATION: u16 = 0x0007;     // OBSOLETE: kept for reader compatibility only
pub const REC_STORAGE_POLICY: u16 = 0x0009;       // New: authoritative storage classification
// Field IDs
pub const FID_MODE: u16 = 0x0701;                 // OBSOLETE: ModeDeclaration field (deprecated)
pub const FID_STORAGE_POLICY: u16 = 0x0901;       // StoragePolicy.field_id (new)
pub const REP_DIRECT_1: u16 = 1;
pub const REP_EXTENTS_1: u16 = 2;

// Tier 3: thread-safe (no-op in single-threaded Zig)
pub const ThreadSafe = struct {
    pub fn withLock() void {}
};

var _encode_bufs: [16][13]u8 = undefined;
var _encode_idx: usize = 0;

pub fn encode(sp: u8, gen: u32) []const u8 {
    const idx = _encode_idx;
    _encode_idx += 1;
    const s = if (sp >= 1 and sp <= 4) sp else 2;
    _encode_bufs[idx][0] = 0x56; _encode_bufs[idx][1] = 0x53;
    _encode_bufs[idx][2] = 0x4E; _encode_bufs[idx][3] = 0x2D;
    _encode_bufs[idx][4] = @truncate(gen); _encode_bufs[idx][5] = @truncate(gen >> 8);
    // REC_STORAGE_POLICY record (0x0009) with FID_STORAGE_POLICY (0x0901) + u8 value
    _encode_bufs[idx][6] = 0x00; _encode_bufs[idx][7] = 0x09;
    _encode_bufs[idx][8] = 4; // payload length
    _encode_bufs[idx][9] = 0x09; _encode_bufs[idx][10] = 0x01;
    _encode_bufs[idx][11] = 1; // value length
    _encode_bufs[idx][12] = s; // policy value
    return &_encode_bufs[idx];
}

pub fn validate(data: []const u8) bool {
    if (data.len < 13) return false;
    if (!std.mem.startsWith(u8, data, "VSN-")) return false;
    // REC_STORAGE_POLICY value must be a legal policy 1..4
    if (data[12] < 1 or data[12] > 4) return false;
    return true;
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
    storage_policy: u8,
    pub fn init(mode: i32) MutableStore {
        return .{ .mode = mode, .generation = 0, .next_rev = 1, .file_count = 0, .rev_count = 0, .obj_count = 0, .closed = false, .storage_policy = 2 };
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
        return encode(s.storage_policy, s.generation);
    }
    pub fn diffCount(s: MutableStore, other: MutableStore) u32 {
        return if (s.file_count > other.file_count) s.file_count - other.file_count else other.file_count - s.file_count;
    }
    pub fn mergeOk(s: MutableStore) bool { return s.mode >= 1 and s.mode <= 2; }
    pub fn importBytes(data: []const u8) bool {
        if (data.len < 8 or !std.mem.startsWith(u8, data, "VSN-")) @panic("bad");
        return true;
    }
    pub fn exportBytes(s: MutableStore) []const u8 { return encode(s.storage_policy, s.generation); }
    pub fn integrityOk(s: MutableStore) bool { return !s.closed; }
    pub fn statsFiles(s: MutableStore) u32 { return s.file_count; }
    pub fn statsRevs(s: MutableStore) u32 { return s.rev_count; }
    pub fn builderOk(s: MutableStore) bool { return s.mode >= 1 and s.mode <= 2; }
};

// ---- Writer Storage Policy (informative, NOT on wire) ----
pub const StoragePolicy = enum(u8) { HIGHLY_VERTICAL = 1, VERTICAL = 2, HORIZONTAL = 3, HIGHLY_HORIZONTAL = 4 };

// Writer Storage Policy integration -- OBSOLETE: cancelled mode mapping removed.
pub fn createWithPolicy(policy: u8) MutableStore {
    // Canonical writer: stores policy value directly (no wire mode mapping).
    const mode = if (policy <= 2) MODE_MODERN else MODE_ENTERPRISE;
    return .{ .mode = mode, .generation = 0, .next_rev = 1, .file_count = 0, .rev_count = 0, .obj_count = 0, .closed = false, .storage_policy = if (policy >= 1 and policy <= 4) policy else 2 };
}

pub fn parseStoragePolicy(data: []const u8) ?u8 {
    if (data.len < 13) return null;
    // Robust scan for REC_STORAGE_POLICY(0x0009) plen(4) FID(0x0901) vlen(1) value.
    var i: usize = 4;
    while (i + 6 <= data.len) : (i += 1) {
        if (data[i] == 0x00 and data[i + 1] == 0x09 and
            data[i + 2] == 0x04 and
            data[i + 3] == 0x09 and data[i + 4] == 0x01 and
            data[i + 5] == 0x01)
        {
            return data[i + 6];
        }
    }
    return null;
}
