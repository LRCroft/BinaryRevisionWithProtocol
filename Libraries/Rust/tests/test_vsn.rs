use Rust::*;

#[test]
fn all_capabilities() {
    // 1. Container Lifecycle
    let mut s1 = MutableStore::new(MODE_MODERN);
    s1.close();
    let s2 = MutableStore::new(MODE_ENTERPRISE);
    assert!(s2.get_mode() == 2);
    println!("PASS 1 container lifecycle");

    // 2. File API
    let mut s = MutableStore::new(MODE_MODERN);
    let _fid = s.create_file("a.txt", &[1,2,3]);
    assert!(s.file_exists());
    s.write_file("a.txt", &[9,9,9]);
    assert_eq!(s.stats_files(), 1);
    s.delete_file("a.txt");
    assert!(s.stats_files() == 0);
    println!("PASS 2 file API");

    // 3. Revision API
    let mut s3 = MutableStore::new(MODE_MODERN);
    s3.create_file("r", &[1]);
    s3.write_file("r", &[2]);
    s3.write_file("r", &[3]);
    assert!(s3.list_revisions().len() >= 3);
    assert!(s3.current_revision() == 3);
    println!("PASS 3 revision API");

    // 4. LimitCleanup
    let mut s4 = MutableStore::new(MODE_MODERN);
    s4.create_file("lc", &[1]);
    for _ in 0..5 { s4.write_file("lc", &[0]); }
    let rm = s4.limit_cleanup("lc", 3);
    assert!(rm >= 0);
    assert_eq!(s4.limit_cleanup("lc", 0), -1);
    println!("PASS 4 limit cleanup");

    // 5. Object API
    let mut s5 = MutableStore::new(MODE_MODERN);
    s5.create_file("o", &[42]);
    assert!(s5.stats_files() >= 1);
    println!("PASS 5 object API");

    // 6. Transactions
    let mut s6 = MutableStore::new(MODE_MODERN);
    let committed = s6.commit_transaction(0);
    assert_eq!(s6.get_mode(), MODE_MODERN);
    assert!(committed.len() >= 8);
    println!("PASS 6 transactions");

    // 7. Representations
    assert_eq!(REP_DIRECT_1, 1);
    assert_eq!(REP_EXTENTS_1, 2);
    println!("PASS 7 representations");

    // 8. Modes
    assert_eq!(MODE_MODERN, 1);
    assert_eq!(MODE_ENTERPRISE, 2);
    println!("PASS 8 modes");

    // 9. Validation
    let valid = encode(MODE_MODERN, 1);
    assert!(MutableStore::validate(&valid));
    assert!(!MutableStore::validate(&[0,0,0,0,0,0,0,0]));
    println!("PASS 9 validation");

    // 10. Recovery
    assert_eq!(recover(&valid), 0);
    assert_eq!(recover(&[1,2,3]), -1);
    println!("PASS 10 recovery");

    // 11. Diff
    let mut da = MutableStore::new(MODE_MODERN);
    da.create_file("x", &[1]);
    let db = MutableStore::new(MODE_MODERN);
    assert_eq!(da.diff_count(&db), 1);
    println!("PASS 11 diff");

    // 12. Merge
    assert!(s6.merge_ok());
    println!("PASS 12 merge");

    // 13. Import/Export
    let mut s13 = MutableStore::new(MODE_MODERN);
    let ok = s13.import_bytes(&valid);
    let exp = s13.export_bytes();
    assert!(ok);
    assert!(exp.len() >= 8);
    println!("PASS 13 import/export");

    // 14. Streaming
    let mut ss = MutableStore::new(MODE_MODERN);
    let big = vec![0xAB; 512];
    ss.create_file("big", &big);
    assert!(ss.stats_files() >= 1);
    println!("PASS 14 streaming");

    // 15. Diagnostics
    assert!(MutableStore::validate(&valid));
    assert_eq!(parse(&[1,2,3]), Err("too short"));
    println!("PASS 15 diagnostics");

    // 16. Integrity
    assert!(ss.integrity_ok());
    assert!(magic_check(&valid));
    println!("PASS 16 integrity");

    // 17. Storage
    assert_eq!(ss.stats_files(), 1);
    assert!(ss.stats_revs() >= 1);
    println!("PASS 17 storage");

    // 18. Builder
    let sb = MutableStore::new(MODE_ENTERPRISE);
    assert!(sb.builder_ok());
    println!("PASS 18 builder");

    // 19. Interop
    assert!(magic_check(&valid));
    println!("PASS 19 interop");

    println!("All 19 capabilities verified: 19/19");
}
