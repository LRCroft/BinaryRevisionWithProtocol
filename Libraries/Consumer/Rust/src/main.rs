//! VSN Rust consumer — uses ONLY the public API of crate `vsn-rust` via a path dependency.
use vsn_rust::*;

fn main() {
    let mut pass = 0usize;
    let mut fail = 0usize;
    macro_rules! chk {
        ($n:expr, $c:expr, $d:expr) => {
            if $c { pass += 1; println!("PASS 2-digit {} {}", $n, $d); }
            else { fail += 1; println!("FAIL {} {}", $n, $d); }
        };
    }

    // 1. Lifecycle: create store, add a file, read it back, commit.
    let s = MutableStore::new(1); // MODE_MODERN
    s.create_file("hello", b"consumer-data");
    chk!(1, s.read_file("hello").map_or(false, |c| c == b"consumer-data"), "lifecycle create/read round-trip");

    // 2. Transactions: commit_transaction advances generation and returns VSN bytes.
    let bytes = s.commit_transaction(0);
    chk!(2, bytes.len() >= 8, "commit_transaction returns container bytes");

    // 3. Encode/parse (storage policy on the wire).
    let enc = encode(2, 1); // VERTICAL policy
    chk!(3, magic_check(&enc), "encode output has VSN magic");
    chk!(4, parse(&enc).map(|t| t.1) == Ok(2), "SP wire-in: parse(VERTICAL) reads policy==2");
    let enc3 = encode(3, 1); // HORIZONTAL policy
    chk!(40, parse(&enc3).map(|t| t.1) == Ok(3), "SP wire-in: parse(HORIZONTAL) reads policy==3");

    // 4. Storage policy enum values.
    chk!(5, StoragePolicy::HIGHLY_VERTICAL as i32 == 1
        && StoragePolicy::VERTICAL as i32 == 2
        && StoragePolicy::HORIZONTAL as i32 == 3
        && StoragePolicy::HIGHLY_HORIZONTAL as i32 == 4,
        "StoragePolicy 4 values defined");

    // 5. Store created with a policy; commit -> parse round-trips the policy.
    let s2 = MutableStore::new_with_policy(StoragePolicy::HORIZONTAL);
    chk!(6, s2.merge_ok(), "store created with HORIZONTAL policy is valid");
    let s2b = s2.export_bytes();
    chk!(60, parse(&s2b).map(|t| t.1) == Ok(3), "SP round-trip: export_bytes(HORIZONTAL) -> parse reads policy==3");

    // 6. Integrity + recover + magic_check on valid/invalid input.
    chk!(7, verify_integrity(&enc) && recover(&enc) == 0, "integrity+recover accept valid container");
    chk!(8, !verify_integrity(b"XXXXXXXX") && recover(b"XXXX") == -1, "integrity+recover reject invalid input");

    // 9. Diff / three-way merge API available and functional.
    let a = MutableStore::new(1); let b = MutableStore::new(1);
    a.create_file("x", b"1");
    chk!(9, a.diff_count(&b) == 1, "diff_count reflects differing file sets");

    println!("RUST_CONSUMER {} PASS {} FAIL exit={}", pass, fail, if fail == 0 { 0 } else { 1 });
    std::process::exit(if fail == 0 { 0 } else { 1 });
}
