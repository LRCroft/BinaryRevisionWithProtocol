// VSN-1 library for Rust — Tier 3: thread-safe
use std::collections::HashMap;
use std::sync::Mutex;

#[derive(Debug)]
pub struct MutableStore {
    inner: Mutex<StoreInner>,
}

#[derive(Debug)]
struct StoreInner {
    mode: i32, generation: u64, next_rev_id: u32, next_obj_serial: u32,
    closed: bool, files: HashMap<String, Vec<u8>>,
    file_count: usize, rev_count: usize, obj_count: usize, next_rev: u32,
}

impl MutableStore {
    pub fn new(mode: i32) -> Self {
        MutableStore { inner: Mutex::new(StoreInner { mode, generation: 0, next_rev_id: 1, next_obj_serial: 1, closed: false, files: HashMap::new(), file_count: 0, rev_count: 0, obj_count: 0, next_rev: 1 }) }
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
    pub fn commit_transaction(&self, expected: u64) -> Vec<u8> { let mut s = self.inner.lock().unwrap(); if expected != s.generation { panic!("gen mismatch"); } s.generation += 1; encode(s.mode, s.generation) }
    pub fn validate(data: &[u8]) -> bool { data.len() >= 8 && data[0] == b'V' && data[3] == b'-' }
    pub fn diff_count(&self, other: &MutableStore) -> usize { self.inner.lock().unwrap().file_count.abs_diff(other.inner.lock().unwrap().file_count) }
    pub fn merge_ok(&self) -> bool { let s = self.inner.lock().unwrap(); s.mode >= 1 && s.mode <= 2 }
    pub fn import_bytes(&self, data: &[u8]) -> bool { if data.len() < 8 || &data[0..4] != b"VSN-" { panic!("bad"); } true }
    pub fn export_bytes(&self) -> Vec<u8> { let s = self.inner.lock().unwrap(); encode(s.mode, s.generation) }
    pub fn integrity_ok(&self) -> bool { !self.inner.lock().unwrap().closed }
    pub fn stats_files(&self) -> usize { self.inner.lock().unwrap().file_count }
    pub fn stats_revs(&self) -> usize { self.inner.lock().unwrap().rev_count }
    pub fn builder_ok(&self) -> bool { let s = self.inner.lock().unwrap(); s.mode >= 1 && s.mode <= 2 }
}

pub const MODE_MODERN: i32 = 1;
pub const MODE_ENTERPRISE: i32 = 2;
pub const REP_DIRECT_1: i32 = 1;
pub const REP_EXTENTS_1: i32 = 2;

pub fn encode(mode: i32, generation: u64) -> Vec<u8> {
    let mut buf = b"VSN-".to_vec(); buf.push(0x01); buf.push(0x01);
    buf.push((mode & 0xFF) as u8);
    for i in 0..5u32 { buf.push(((generation >> (i * 8)) & 0xFF) as u8); } buf
}

#[derive(Debug)] pub struct Error(pub &'static str);
pub type Result<T> = std::result::Result<T, Error>;
pub fn parse(data: &[u8]) -> std::result::Result<(i32, u64), &'static str> { if data.len() < 8 { return Err("too short"); } if &data[0..4] != b"VSN-" { return Err("bad magic"); } let m = data[4] as i32; let g = u64::from(data[5]) | (u64::from(data[6]) << 8) | (u64::from(data[7]) << 16); Ok((m, g)) }
pub fn recover(data: &[u8]) -> i32 { if data.len() >= 8 && &data[0..4] == b"VSN-" { 0 } else { -1 } }
pub fn magic_check(data: &[u8]) -> bool { data.len() >= 8 && &data[0..4] == b"VSN-" }
pub fn verify_integrity(data: &[u8]) -> bool { data.len() >= 8 && &data[0..4] == b"VSN-" }
#[derive(Debug)] pub struct MergeResult { pub conflicts: usize }
pub fn diff_count_impl(a_files: usize, b_files: usize) -> usize { a_files.abs_diff(b_files) }

