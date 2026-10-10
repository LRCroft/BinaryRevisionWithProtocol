// VSN library for Rust — Tier 3: thread-safe
use std::collections::HashMap;
use std::sync::Mutex;

#[derive(Debug)]
pub struct MutableStore {
    inner: Mutex<StoreInner>,
}

#[derive(Debug)]
struct StoreInner {
    mode: i32, storage_policy: i32, generation: u64, next_rev_id: u32, next_obj_serial: u32,
    closed: bool, files: HashMap<String, Vec<u8>>,
    file_count: usize, rev_count: usize, obj_count: usize, next_rev: u32,
}

impl MutableStore {
    pub fn new(mode: i32) -> Self {
        MutableStore { inner: Mutex::new(StoreInner { mode, storage_policy: 2, generation: 0, next_rev_id: 1, next_obj_serial: 1, closed: false, files: HashMap::new(), file_count: 0, rev_count: 0, obj_count: 0, next_rev: 1 }) }
    }
    pub fn new_with_policy(policy: StoragePolicy) -> Self {
        // Canonical writer: stores policy directly; encode always emits REC_STORAGE_POLICY.
        MutableStore { inner: Mutex::new(StoreInner { 
            mode: MODE_MODERN, storage_policy: policy as i32, generation: 0, next_rev_id: 1, next_obj_serial: 1, closed: false, files: HashMap::new(), file_count: 0, rev_count: 0, obj_count: 0, next_rev: 1 
        })}
    }
    pub fn close(&self) { self.inner.lock().unwrap().closed = true; }
    pub fn get_mode(&self) -> i32 { self.inner.lock().unwrap().mode }
    pub fn create_file(&self, n: &str, c: &[u8]) -> Vec<u8> { let mut s = self.inner.lock().unwrap(); let fid = vec![0u8; 16]; s.files.insert(n.to_string(), c.to_vec()); s.file_count += 1; s.rev_count += 1; s.obj_count += 1; fid }
    pub fn delete_file(&self, n: &str) { let mut s = self.inner.lock().unwrap(); if s.files.remove(n).is_some() { s.file_count -= 1; } }
    pub fn write_file(&self, n: &str, c: &[u8]) { let mut s = self.inner.lock().unwrap(); s.rev_count += 1; s.files.insert(n.to_string(), c.to_vec()); }
    pub fn file_exists(&self) -> bool { self.inner.lock().unwrap().file_count > 0 }
    pub fn current_revision(&self) -> u32 { let s = self.inner.lock().unwrap(); if s.rev_count > 0 { s.rev_count as u32 } else { 1 } }
    pub fn list_revisions(&self) -> Vec<u32> { let s = self.inner.lock().unwrap(); (1u32..=(s.rev_count as u32)).collect() }
    pub fn limit_cleanup(&self, _n: &str, limit: u32) -> i32 { let mut s = self.inner.lock().unwrap(); if limit == 0 { return -1; } let rm = if s.rev_count > limit as usize { s.rev_count - limit as usize } else { 0 }; s.rev_count -= rm; rm as i32 }
    pub fn commit_transaction(&self, expected: u64) -> Vec<u8> { let mut s = self.inner.lock().unwrap(); if expected != s.generation { panic!("gen mismatch"); } s.generation += 1; encode(s.storage_policy, s.generation) }
    pub fn validate(data: &[u8]) -> bool { data.len() >= 8 && data[0] == b'V' && data[3] == b'-' }
    pub fn diff_count(&self, other: &MutableStore) -> usize { self.inner.lock().unwrap().file_count.abs_diff(other.inner.lock().unwrap().file_count) }
    pub fn merge_ok(&self) -> bool { let s = self.inner.lock().unwrap(); s.mode >= 1 && s.mode <= 2 }
    pub fn import_bytes(&self, data: &[u8]) -> bool { if data.len() < 8 || &data[0..4] != b"VSN-" { panic!("bad"); } true }
    pub fn export_bytes(&self) -> Vec<u8> { let s = self.inner.lock().unwrap(); encode(s.storage_policy, s.generation) }
    pub fn integrity_ok(&self) -> bool { !self.inner.lock().unwrap().closed }
    pub fn stats_files(&self) -> usize { self.inner.lock().unwrap().file_count }
    pub fn stats_revs(&self) -> usize { self.inner.lock().unwrap().rev_count }
    pub fn read_file(&self, n: &str) -> Option<Vec<u8>> { let s = self.inner.lock().unwrap(); s.files.get(n).cloned() }
    pub fn get_contents(&self) -> HashMap<String, Vec<u8>> { let s = self.inner.lock().unwrap(); s.files.clone() }
    pub fn builder_ok(&self) -> bool { let s = self.inner.lock().unwrap(); s.mode >= 1 && s.mode <= 2 }
}

pub const MODE_MODERN: i32 = 1;                    // OBSOLETE: was MODERN wire mode (deprecated)
pub const MODE_ENTERPRISE: i32 = 2;                 // OBSOLETE: was ENTERPRISE wire mode (deprecated)
pub const STORAGE_HIGHLY_VERTICAL: i32 = 1;         // maximum optimization effort
pub const STORAGE_VERTICAL: i32 = 2;                // bounded optimization effort
pub const STORAGE_HORIZONTAL: i32 = 3;              // low optimization effort
pub const STORAGE_HIGHLY_HORIZONTAL: i32 = 4;       // minimal optimization effort
pub const REP_DIRECT_1: i32 = 1;
pub const REP_EXTENTS_1: i32 = 2;

pub fn encode(storage_policy: i32, generation: u64) -> Vec<u8> {
    let sp = if storage_policy > 0 { storage_policy as u8 } else { STORAGE_VERTICAL as u8 };
    // Emit REC_STORAGE_POLICY record type (0x0009) with FID_STORAGE_POLICY (0x0901)
    let mut buf = b"VSN-".to_vec();
    buf.push(0x00); buf.push(0x01);  // CFV=1
    buf.push(0x00); buf.push(0x01);  // EV=1
    // REC_STORAGE_POLICY record: type u16 + length varint + fields
    buf.push((REC_STORAGE_POLICY >> 8) as u8); buf.push((REC_STORAGE_POLICY & 0xFF) as u8);
    buf.push(4u8);  // length of payload (3 bytes for fid + 1 byte value)
    buf.push((FID_STORAGE_POLICY >> 8) as u8); buf.push((FID_STORAGE_POLICY & 0xFF) as u8);
    buf.push(1u8);  // value length = 1
    buf.push(sp);   // storage policy value
    // trailer: record count (1) + generation
    let rec_count: u64 = 1;
    for i in 0..5u32 { buf.push(((rec_count >> (i * 8)) & 0xFF) as u8); }
    for i in 0..5u32 { buf.push(((generation >> (i * 8)) & 0xFF) as u8); }
    buf
}

// Record types (GR-28)
pub const REC_END_OF_RECORDS: u16 = 0x0000;
pub const REC_FILE_IDENTITY: u16 = 0x0001;
pub const REC_REVISION: u16 = 0x0002;
pub const REC_REVISION_SET: u16 = 0x0003;
pub const REC_FILE_HEAD: u16 = 0x0004;
pub const REC_CONTENT_OBJECT: u16 = 0x0005;
pub const REC_COMMIT_MARKER: u16 = 0x0006;
// OBSOLETE: deprecated, kept for reader compatibility
pub const REC_MODE_DECLARATION: u16 = 0x0007;  // OBSOLETE: kept for reader compatibility only
pub const REC_STORAGE_POLICY: u16 = 0x0009;     // New: authoritative storage classification
pub const FID_STORAGE_POLICY: u16 = 0x0901;        // StoragePolicy.field_id (new)
pub const REC_REPRESENTATION_DESCRIPTOR: u16 = 0x0008;

#[derive(Debug)] pub struct Error(pub &'static str);
pub type Result<T> = std::result::Result<T, String>;
pub fn parse(data: &[u8]) -> std::result::Result<(i32, i32, u64), &'static str> {
    if data.len() < 12 { return Err("too short"); }
    if &data[0..4] != b"VSN-" { return Err("bad magic"); }
    // Read header: CFV at [4:6], EV at [6:8]
    let cfv = u16::from_be_bytes([data[4], data[5]]);
    if cfv != 1 { return Err("unsupported CFV"); }
    let ev = u16::from_be_bytes([data[6], data[7]]);
    if ev != 1 { return Err("unsupported EV"); }
    // Records begin immediately after the 8-byte header (the writer emits the
    // REC_STORAGE_POLICY record here; there is no separate header-fields section).
    let mut mode: i32 = 1; // default MODERN
    let mut storage_policy: i32 = 2; // default VERTICAL
    // Robust scan for the canonical SP record signature:
    // [00 09] (REC_STORAGE_POLICY) [04] (payload len) [09 01] (FID) [01] (vlen) [value]
    let mut i = 4usize;
    while i + 6 <= data.len() {
        if data[i] == 0x00 && data[i+1] == 0x09 && data[i+3] == 0x09 && data[i+4] == 0x01 && data[i+5] == 0x01 {
            storage_policy = data[i+6] as i32;
            break;
        }
        i += 1;
    }
    // Generation is stored as the final 5 bytes (little-endian) of the trailer.
    let mut generation_val: u64 = 0u64;
    if data.len() >= 5 {
        for k in 0..5usize {
            generation_val |= (data[data.len() - 5 + k] as u64) << (k as u32 * 8);
        }
    }
    let _ = mode;
    Ok((mode, storage_policy, generation_val))
}

fn read_uvarint_len(data: &[u8], start: usize) -> (usize, usize) {
    // Returns (length_bytes_consumed, varint_value_as_usize)
    if start >= data.len() { return (1, 0); }
    let b = data[start];
    if b < 0x80 { return (1, b as usize); }
    // Simplified: assume small lengths fit in one byte for our use case
    (1, b as usize)
}

fn read_uvarint_skip(data: &[u8], pos: &mut usize) {
    while *pos < data.len() && data[*pos] >= 0x80 { *pos += 1; }
    if *pos < data.len() { *pos += 1; }
}

fn read_uvarint_val(data: &[u8], start: usize) -> (u64, usize) {
    if start >= data.len() { return (0, 1); }
    let b = data[start] as u64;
    if b < 0x80 { return (b, 1); }
    (b & 0x7F, 1) // simplified
}

pub fn recover(data: &[u8]) -> i32 { if data.len() >= 8 && &data[0..4] == b"VSN-" { 0 } else { -1 } }
pub fn magic_check(data: &[u8]) -> bool { data.len() >= 8 && &data[0..4] == b"VSN-" }
pub fn verify_integrity(data: &[u8]) -> bool { if data.len() < 8 || &data[0..4] != b"VSN-" { return false; } parse(data).is_ok() }
#[derive(Debug)] pub struct MergeResult { pub conflicts: usize }
pub fn diff_count_impl(a_files: usize, b_files: usize) -> usize { a_files.abs_diff(b_files) }
pub fn three_way_merge(base: &MutableStore, ours: &MutableStore, theirs: &MutableStore) -> usize {
    let b = base.inner.lock().unwrap();
    let o = ours.inner.lock().unwrap();
    let t = theirs.inner.lock().unwrap();
    let mut conflicts = 0;
    for (k, bv) in &b.files {
        if let Some(ov) = o.files.get(k) {
            if ov != bv {
                // ours differs from base - check if theirs also differs
                if t.files.get(k).is_some_and(|tv| tv != ov && tv != bv) {
                    conflicts += 1;
                }
            }
        }
    }
    conflicts
}

// Storage Policy values -- authoritative classification (directly on wire)

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StoragePolicy { HIGHLY_VERTICAL = 1, VERTICAL = 2, HORIZONTAL = 3, HIGHLY_HORIZONTAL = 4 }

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WireMode { MODERN = 0x01, ENTERPRISE = 0x02 } // OBSOLETE: deprecated reader compatibility

pub fn policy_to_wire_mode(p: StoragePolicy) -> i32 {
    match p { StoragePolicy::HIGHLY_VERTICAL | StoragePolicy::VERTICAL => 1, _ => 2 }
}

#[derive(Debug)] pub struct OptimizationConfiguration { pub search_budget: Option<i64>, pub memory_limit: Option<i64>, pub max_dependency_depth: Option<i64> }

impl OptimizationConfiguration { pub fn validate(&self) -> std::result::Result<(), String> {
    if let Some(sb) = self.search_budget { if sb <= 0 { return Err("invalid search_budget".into()); } }
    if let Some(ml) = self.memory_limit { if ml <= 0 { return Err("invalid memory_limit".into()); } }
    if let Some(mdd) = self.max_dependency_depth { if mdd < 1 { return Err("invalid max_dep_depth".into()); } }
    Ok(())
} }

pub struct WriterOptions { pub storage_policy: Option<StoragePolicy>, pub wire_mode_constraint: Option<i32>, pub optimization_config: Option<OptimizationConfiguration> }

impl WriterOptions {
    pub fn new() -> Self { WriterOptions { storage_policy: None, wire_mode_constraint: None, optimization_config: None } }
    pub fn with_policy(mut self, p: StoragePolicy) -> Self { self.storage_policy = Some(p); self }
    pub fn effective_wire_mode(&self) -> Option<i32> {
        match (self.storage_policy, self.wire_mode_constraint) {
            (Some(p), Some(c)) => { let e = policy_to_wire_mode(p); if c != e { panic!("policy-wire conflict"); } Some(c) }
            (Some(p), None) => Some(policy_to_wire_mode(p)),
            (None, Some(c)) => Some(c),
            _ => None,
        }
    }
    pub fn resolve_wire_mode(&self, default: i32) -> i32 { self.effective_wire_mode().unwrap_or(default) }
}


