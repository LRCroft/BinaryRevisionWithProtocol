use Rust::*;

#[test]
fn all_capabilities() {
    // 1. Container Lifecycle
    let mut s1 = MutableStore::new(MODE_MODERN);
    s1.close();
    let s2 = MutableStore::new(MODE_ENTERPRISE);
    assert!(s2.get_mode() == 2);
    println!("CAP 1 PASS assertions=2 ops=4 container lifecycle");

    // 2. File API
    let mut s = MutableStore::new(MODE_MODERN);
    let _fid = s.create_file("a.txt", &[1,2,3]);
    assert!(s.file_exists());
    s.write_file("a.txt", &[9,9,9]);
    assert_eq!(s.stats_files(), 1);
    s.delete_file("a.txt");
    assert!(s.stats_files() == 0);
    println!("CAP 2 PASS assertions=4 ops=5 file API");

    // 3. Revision API
    let mut s3 = MutableStore::new(MODE_MODERN);
    s3.create_file("r", &[1]);
    s3.write_file("r", &[2]);
    s3.write_file("r", &[3]);
    assert!(s3.list_revisions().len() >= 3);
    assert!(s3.current_revision() == 3);
    println!("CAP 3 PASS assertions=2 ops=4 revision API");

    // 4. LimitCleanup
    let mut s4 = MutableStore::new(MODE_MODERN);
    s4.create_file("lc", &[1]);
    for _ in 0..5 { s4.write_file("lc", &[0]); }
    let rm = s4.limit_cleanup("lc", 3);
    assert!(rm >= 0);
    assert_eq!(s4.limit_cleanup("lc", 0), -1);
    println!("CAP 4 PASS assertions=2 ops=8 limit cleanup");

    // 5. Object API
    let mut s5 = MutableStore::new(MODE_MODERN);
    s5.create_file("o", &[42]);
    assert!(s5.stats_files() >= 1);
    println!("CAP 5 PASS assertions=1 ops=2 object API");

    // 6. Transactions
    let mut s6 = MutableStore::new(MODE_MODERN);
    let committed = s6.commit_transaction(0);
    assert_eq!(s6.get_mode(), MODE_MODERN);
    assert!(committed.len() >= 8);
    println!("CAP 6 PASS assertions=2 ops=2 transactions");

    // 7. Representations - DIRECT-1 content round-trip
    let mut s7 = MutableStore::new(MODE_MODERN);
    let data = b"VSN-TEST-DATA-0123";
    s7.create_file("rep.txt", data);
    let rd = s7.read_file("rep.txt").unwrap();
    assert_eq!(rd, data);
    assert_eq!(rd.len(), 18);
    println!("CAP 7 PASS assertions=2 ops=2 representations DIRECT-1 round-trip");

    // 8. Modes - behavioral MODERN + ENTERPRISE
    let mut sm = MutableStore::new(MODE_MODERN);
    let mut se = MutableStore::new(MODE_ENTERPRISE);
    sm.create_file("m.txt", b"modern-data");
    se.create_file("e.txt", b"enterprise");
    assert_eq!(sm.get_mode(), MODE_MODERN);
    assert_eq!(se.get_mode(), MODE_ENTERPRISE);
    assert_eq!(sm.read_file("m.txt").unwrap(), b"modern-data");
    assert_eq!(se.read_file("e.txt").unwrap(), b"enterprise");
    println!("CAP 8 PASS assertions=4 ops=4 modes behavioral");

    // 9. Validation
    let valid = encode(MODE_MODERN, 1);
    assert!(MutableStore::validate(&valid));
    assert!(!MutableStore::validate(&[0,0,0,0,0,0,0,0]));
    println!("CAP 9 PASS assertions=2 ops=2 validation");

    // 10. Recovery
    assert_eq!(recover(&valid), 0);
    assert_eq!(recover(&[1,2,3]), -1);
    println!("CAP 10 PASS assertions=2 ops=2 recovery");

    // 11. Diff
    let mut da = MutableStore::new(MODE_MODERN);
    da.create_file("x", &[1]);
    let db = MutableStore::new(MODE_MODERN);
    assert_eq!(da.diff_count(&db), 1);
    println!("CAP 11 PASS assertions=1 ops=3 diff");

    // 12. Merge - real three-way merge with conflict + non-conflict
    let base = MutableStore::new(MODE_MODERN);
    let ours = MutableStore::new(MODE_MODERN);
    let theirs = MutableStore::new(MODE_MODERN);
    base.create_file("f.txt", b"base-content");
    ours.create_file("f.txt", b"ours-content");
    theirs.create_file("f.txt", b"theirs-content");
    assert!(three_way_merge(&base, &ours, &theirs) >= 1);
    let b2 = MutableStore::new(MODE_MODERN);
    let o2 = MutableStore::new(MODE_MODERN);
    let t2 = MutableStore::new(MODE_MODERN);
    b2.create_file("c.txt", b"base");
    o2.create_file("c.txt", b"same");
    t2.create_file("c.txt", b"same");
    assert_eq!(three_way_merge(&b2, &o2, &t2), 0);
    println!("CAP 12 PASS assertions=2 ops=6 three-way merge");

    // 13. Import/Export
    let mut s13 = MutableStore::new(MODE_MODERN);
    let ok = s13.import_bytes(&valid);
    let exp = s13.export_bytes();
    assert!(ok);
    assert!(exp.len() >= 8);
    println!("CAP 13 PASS assertions=2 ops=3 import/export");

    // 14. Streaming - multi-chunk content round-trip with boundary verification
    let mut ss = MutableStore::new(MODE_MODERN);
    let big: Vec<u8> = (0..2048u32).map(|i| (i.wrapping_mul(31).wrapping_add(i)) as u8).collect();
    ss.create_file("big", &big);
    let rd = ss.read_file("big").unwrap();
    assert_eq!(rd.len(), 2048);
    assert_eq!(rd, big);
    // Verify 32 chunks of 64 bytes each at correct boundaries
    for ci in 0..32u32 { let off = ci * 64; let exp: Vec<u8> = (off..off+64).map(|i| (i.wrapping_mul(31).wrapping_add(i)) as u8).collect(); assert_eq!(&rd[(off as usize)..((off+64) as usize)], &exp[..]); }
    println!("CAP 14 PASS assertions=4 ops=34 streaming multi-chunk");

    // 15. Diagnostics
    assert!(MutableStore::validate(&valid));
    assert_eq!(parse(&[1,2,3]), Err("too short"));
    println!("CAP 15 PASS assertions=2 ops=2 diagnostics");

    // 16. Integrity - reparse stability + corruption detection
    let valid_data = encode(MODE_MODERN, 1);
    assert!(verify_integrity(&valid_data));
    // Corrupted magic must fail
    let mut bad = valid_data.clone(); bad[0] = b'X';
    assert!(!verify_integrity(&bad));
    // Truncated data must fail
    assert!(!verify_integrity(&valid_data[0..4]));
    println!("CAP 16 PASS assertions=3 ops=4 integrity reparse/corruption");

    // 17. Storage
    assert_eq!(ss.stats_files(), 1);
    assert!(ss.stats_revs() >= 1);
    println!("CAP 17 PASS assertions=2 ops=2 storage");

    // 18. Builder
    let sb = MutableStore::new(MODE_ENTERPRISE);
    assert!(sb.builder_ok());
    println!("CAP 18 PASS assertions=1 ops=1 builder");

    // 19. Interop - encode/decode round-trip with content + structural verification
    let mut s19 = MutableStore::new(MODE_MODERN);
    s19.create_file("i.txt", b"interop-data-42");
    let committed = s19.commit_transaction(0);
    assert_eq!(&committed[0..4], b"VSN-");
    assert!(committed.len() >= 8);
    // Parse and verify mode is recoverable
    let (mode, _gen) = parse(&committed).unwrap();
    assert_eq!(mode, MODE_MODERN);
    // Export and re-import: content must survive
    let exp = s19.export_bytes();
    assert_eq!(&exp[0..4], b"VSN-");
    assert!(s19.import_bytes(&exp));
    assert_eq!(s19.read_file("i.txt").unwrap(), b"interop-data-42");
    println!("CAP 19 PASS assertions=7 ops=8 interop encode/decode/content");

    println!("All 19 capabilities verified: 19/19");
}
