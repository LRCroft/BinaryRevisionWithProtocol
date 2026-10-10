(* VSN-1 independent consumer (OCaml) -- Storage Policy round-trip.
   Uses the library's encode_with_policy (wire-out) + parse (wire-in). *)
open Vsn

let has_sig s =
  let l = String.length s in
  let r = ref false in
  for i = 0 to max 0 (l - 7) do
    if s.[i] = Char.chr 0 && s.[i+1] = Char.chr 9 && s.[i+2] = Char.chr 4 &&
       s.[i+3] = Char.chr 9 && s.[i+4] = Char.chr 1 && s.[i+5] = Char.chr 1
    then r := true
  done;
  !r

let bad = ref false
let () =
  for p = 1 to 4 do
    let b = encode_with_policy 1 0 p in
    if not (has_sig b) then begin
      Printf.eprintf "FAIL p=%d wire-out\n" p; bad := true
    end;
    let c = parse b in
    match c.storage_policy with
    | Some q when q = p -> ()
    | Some q -> (Printf.eprintf "FAIL p=%d got=%d\n" p q; bad := true)
    | None -> (Printf.eprintf "FAIL p=%d parse=None\n" p; bad := true)
  done;
  if !bad then (print_endline "CONSUMER OCAML FAIL"; exit 1)
  else print_endline "CONSUMER OCAML PASS"
