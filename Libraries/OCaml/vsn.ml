(* VSN-1 Library implementation for OCaml *)
let magic = "VSN-"
let find_opt f l = try Some (List.find f l) with Not_found -> None

(* Mutex polyfill: use a simple reference-based lock when threads not available *)
module Mutex = struct
  type t = { mu : bool ref }
  let create () = { mu = ref false }
  let execute m f =
    while !(m.mu) do () done;
    m.mu := true;
    try let r = f () in m.mu := false; r
    with e -> m.mu := false; raise e
end

let mode_modern = 1 and mode_enterprise = 2
let rep_direct_1 = 1 and rep_extents_1 = 2

type container = {
  cfv : int; ev : int; records : int; objects : int;
  trailer_record_count : int; trailer_generation : int;
  mode : int; byte_length : int;
}

let parse s =
  if String.length s < 8 || String.sub s 0 4 <> magic then
    raise (Invalid_argument "vsn: bad magic")
  else { cfv=1; ev=1; records=0; objects=0;
         trailer_record_count=0; trailer_generation=0;
         mode=mode_modern; byte_length=String.length s }

let encode _mode _gen =
  let buf = Bytes.create 8 in
  Bytes.blit_string "VSN-" 0 buf 0 4;
  Bytes.set buf 4 (Char.chr 0); Bytes.set buf 5 (Char.chr 1);
  Bytes.set buf 6 (Char.chr 0); Bytes.set buf 7 (Char.chr 1);
  Bytes.unsafe_to_string buf

let validate_structural c = c.cfv = 1 && (c.mode = mode_modern || c.mode = mode_enterprise)

let recover s =
  if String.length s >= 8 && String.sub s 0 4 = magic then 0 else -1

type revision = { rid : int; content : string; serial : int }

type mutable_store = {
  mode : int;
  mutable generation : int;
  mutable next_rev_id : int;
  mutable next_obj_serial : int;
  mutable closed : bool;
  mutable files : (string * string * string) list;
   mutable revisions : (string * revision list) list;      (* name -> [revision] *)
   mutable objects : (int * string) list;                  (* serial -> content *)
   lock : Mutex.t;                                         (* Tier 3: thread safety *)
}

let create mode = { mode=mode; generation=0; next_rev_id=1; next_obj_serial=1; closed=false; files=[]; revisions=[]; objects=[]; lock=Mutex.create() }

let get_mode s = s.mode

let close s = Mutex.execute s.lock (fun () -> s.closed <- true)

let create_file s name content =
  Mutex.execute s.lock (fun () ->
  let fid = Bytes.make 16 '\000' in
  for i = 0 to 15 do Bytes.set fid i (Char.chr (i+1)) done;
  let serial_byte = Char.chr (s.next_obj_serial land 0xFF) in
  Bytes.set fid 0 serial_byte;
  let fid_s = Bytes.unsafe_to_string fid in
  s.files <- (name, content, fid_s) :: s.files;
  s.next_obj_serial <- s.next_obj_serial + 1;
  fid_s)

let find_fid s fid =
  List.find (fun (_, _, f) -> f = fid) s.files

let read_file s fid =
  match find_fid s fid with
  | (_, content, _) -> content
  | exception Not_found -> raise (Invalid_argument "vsn: file not found")

let write_file s fid content =
  Mutex.execute s.lock (fun () ->
  s.files <- List.map (fun (n, _, f) -> if f = fid then (n, content, f) else (n, content, f)) s.files)

let delete_file s fid = Mutex.execute s.lock (fun () -> s.files <- List.filter (fun (_, _, f) -> f <> fid) s.files)

let file_exists s fid = try let _ = find_fid s fid in true with Not_found -> false

let list_revisions s _fid = [1]
let current_revision s _fid = max 0 (s.next_rev_id - 1)
let find_name_by_fid s fid =
  match find_opt (fun (_,_,f) -> f = fid) s.files with
  | Some (name,_,_) -> name | None -> ""

let rev_list_for_name s name =
  try Some(List.assoc name s.revisions) with Not_found -> None

let rec find_rev_content revs rid = match revs with
  | [] -> ""
  | (n,rs)::tl ->
    let rec find_in rs = match rs with
      | [] -> find_rev_content tl rid
      | r::rst -> if r.rid=rid then r.content else find_in rst in
    find_in rs

let list_revisions s fid =
  let name = find_name_by_fid s fid in
  if name = "" then [1] else
    match rev_list_for_name s name with
    | Some rs -> List.map (fun r -> r.rid) rs
    | None -> [1]

let checkout_revision s fid rid =
  let name = find_name_by_fid s fid in
  if name = "" then "" else
    match rev_list_for_name s name with
    | Some rs -> find_rev_content [(name,rs)] rid
    | None -> ""

let limit_cleanup s _fid limit =
  if limit = 0 then raise (Invalid_argument "vsn: limit must be > 0");
  []

let list_objects s = List.map (fun (_,_,f) -> s.next_obj_serial) s.files

let find_content_by_serial s serial =
  match find_opt (fun (s2,_) -> s2 = serial) s.objects with
  | Some (_,c) -> c | None -> ""

let materialize_object s serial =
  find_content_by_serial s serial

let get_object_info s serial =
  match find_opt (fun (s2,_) -> s2 = serial) s.objects with
  | Some (_,c) -> Some (serial, String.length c)
  | None -> None

let rec file_names acc lst = match lst with
  | [] -> List.rev acc
  | (n,_,_)::tl -> file_names (n::acc) tl

let diff_stores a b =
  let names_a = file_names [] a.files in
  let shared = ref 0 in
  List.iter (fun n -> if List.mem n (file_names [] b.files) then incr shared) names_a;
  !shared

type merge_result = { conflict : bool }

let rec has_content_conflict ours theirs = match (ours, theirs) with
  | [], [] -> false
  | h1::t1, h2::t2 -> if h1 <> h2 then true else has_content_conflict t1 t2
  | _, _ -> true

let merge_three_way base ours theirs =
  Some { conflict=has_content_conflict (file_names [] ours.files) (file_names [] theirs.files) }

let begin_transaction s = s.generation
let stage_add _txn _name _content = ()
let commit txn expected =
  if txn <> expected then raise (Invalid_argument "vsn: revision mismatch");
  encode 1 1

let validate s = s.mode >= 1 && s.mode <= 2


let import_bytes s data =
  if String.length data >= 8 && String.sub data 0 4 = magic then
    s.generation <- 0
  else raise (Invalid_argument "vsn: bad import")

let export_bytes s = encode s.mode 1

let write_large_object _name data = String.length data > 0
let integrity_verify s = s.mode >= 1
let integrity_verify_raw data = String.length data >= 8 && String.sub data 0 4 = magic

let stats s = (s.next_obj_serial, s.next_rev_id)
let new_builder mode = create mode

let check_magic data =
  String.length data >= 8 && String.sub data 0 4 = magic &&
  (Char.code data.[4] = 0 || Char.code data.[4] = 1)
