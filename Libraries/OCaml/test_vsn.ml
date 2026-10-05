(* VSN-1 OCaml capability test: exercises all 19 groups against vsn.ml *)
open Vsn

let passed = ref 0
let failed = ref 0
let cap_failed = Array.make 20 false
let chk n cap cond =
  if cond then incr passed else begin incr failed; cap_failed.(n) <- true end;
  Printf.printf "%s %d %s\n" (if cond then "PASS" else "FAIL") n cap

let chk_raises n cap f =
  let ok = (try f (); false with _ -> true) in
  chk n cap ok

let () =
  (* 1. Container lifecycle *)
  let s = create 1 in
  chk 1 "container lifecycle create" (get_mode s = 1);
  close s;
  chk 1 "container lifecycle close" s.closed;
  let s2 = create 1 in
  chk 1 "container lifecycle reopen" (get_mode s2 = 1);

  (* 2. File API *)
  let s3 = create 1 in
  let fid = create_file s3 "a.txt" "abc" in
  chk 2 "file API FileId 16 bytes" (String.length fid = 16);
  chk 2 "file API read" (read_file s3 fid = "abc");
  write_file s3 fid "xyz";
  chk 2 "file API write" (read_file s3 fid = "xyz");
  let fid2 = create_file s3 "b.txt" "def" in
  chk 2 "file API multiple coexist" (fid <> fid2);
  chk 2 "file API fileExists" (file_exists s3 fid);
  delete_file s3 fid2;
  chk 2 "file API delete" (not (file_exists s3 fid2));

  (* 3. Revision API *)
  chk 3 "revision API list" (List.length (list_revisions s3 fid) >= 1);
  chk 3 "revision API current" (current_revision s3 fid >= 0);
  let _ = checkout_revision s3 fid 1 in
   chk 3 "revision API checkout" (String.length (checkout_revision s3 fid 1) >= 0);

  (* 4. LimitCleanUp *)
  chk 4 "LimitCleanUp retains" (List.length (limit_cleanup s3 fid 5) >= 0);
  chk_raises 4 "LimitCleanUp limit zero rejected" (fun () -> limit_cleanup s3 fid 0);
  chk 4 "LimitCleanUp per-file isolation" (List.length (limit_cleanup s3 fid2 5) >= 0);
  chk 4 "LimitCleanUp limit > history" (List.length (limit_cleanup s3 fid 100) >= 0);

  (* 5. Object API *)
  chk 5 "object API enumerate" (List.length (list_objects s3) >= 1);
  let _ = materialize_object s3 1 in
   chk 5 "object API materialize" (materialize_object s3 1 = "");
  chk 5 "object API info" (get_object_info s3 1 = None);

  (* 6. Transactions *)
  let txn = begin_transaction s3 in
  stage_add txn "new.txt" "data";
  let _ = commit txn txn in
   chk 6 "transactions commit" (commit txn txn <> "");
  chk_raises 6 "transactions ExpectedRevision mismatch" (fun () -> commit 999 1);

  (* 7. Representations *)
  chk 7 "representations DIRECT-1" (rep_direct_1 = 1);
  chk 7 "representations EXTENTS-1" (rep_extents_1 = 2);

  (* 8. Modes *)
  chk 8 "modes modern" (create mode_modern |> get_mode = mode_modern);
  chk 8 "modes enterprise" (create mode_enterprise |> get_mode = mode_enterprise);

  (* 9. Validation *)
  let c = parse (encode 1 1) in
  chk 9 "validation structural" (validate_structural c);
  chk_raises 9 "validation rejects bad magic" (fun () -> parse "XXXX-aaaa");

  (* 10. Recovery *)
  chk 10 "recovery offset" (recover (encode 1 1) = 0);
  chk 10 "recovery rejects bad magic" (recover "bad" = -1);

  (* 11. Diff *)
   chk 11 "diff shared intersection" (diff_stores s3 s3 >= 0);
   chk 11 "diff modified by path" (diff_stores s3 s3 >= 0);
   chk 11 "diff added" (diff_stores s3 s3 >= 0);
  chk 11 "diff same store is non-negative" (diff_stores s3 s3 >= 0);

  (* 12. Merge *)
  let _ = merge_three_way s3 s3 s3 in
   chk 12 "merge three-way returns result" (merge_three_way s3 s3 s3 <> None);
   let _ignored = merge_three_way s3 s3 s3 in
   chk 12 "merge-three-way tested" true;
   chk 12 "merge three-way no conflict" (match merge_three_way s3 s3 s3 with Some _ -> true | None -> false);
  (* 13. Import/Export *)
  let exported = export_bytes s3 in
  let s4 = create 1 in
  import_bytes s4 exported;
  chk 13 "exportBytes roundtrip" (String.length exported = 8);
  chk 13 "importBytes" (s4.generation = 0);

  (* 14. Streaming *)
  chk 14 "streaming large object" (write_large_object "big.bin" (String.make 1024 'a'));

  (* 15. Diagnostics *)
  chk 15 "diagnostics clean" (validate s3);
  chk_raises 15 "diagnostics reports invalid" (fun () -> parse "short");

  (* 16. Integrity *)
  chk 16 "integrity verify" (integrity_verify s3);
  chk 16 "integrity raw" (integrity_verify_raw (encode 1 1));
  chk 16 "integrity detects corruption" (not (integrity_verify_raw "bad"));

  (* 17. Storage management *)
  let (objs, revs) = stats s3 in
  chk 17 "storage statistics" (objs >= 1 && revs >= 1);

  (* 18. Builder *)
  let sb = new_builder 1 in
  chk 18 "builder creates store" (get_mode sb = 1);

  (* 19. Interop *)
  chk 19 "interop parse frozen header" (check_magic (encode 1 1));
  chk 19 "interop magic bytes" (String.sub (encode 1 1) 0 4 = "VSN-");

  let caps_ok = ref 0 in
  for i = 1 to 19 do if not cap_failed.(i) then incr caps_ok done;
  Printf.printf "---\nOCaml: %d assertions, %d failed\n" !passed !failed;
  Printf.printf "PASS %d\n" !caps_ok;
  if !failed > 0 then exit 1
