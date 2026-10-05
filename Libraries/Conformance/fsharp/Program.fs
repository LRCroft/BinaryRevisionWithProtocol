// Executable LimitCleanUp probe for the F# library.
// Real 10-revision history, retention verification, reopen, recovery, rejection.
// Prints a machine-readable final line:
//    LIMIT_CLEANUP <PASS|FAIL> removed=<csv> retained=<csv>

module LimitCleanupProbe

open System
open System.Text
open Vsn

let failures = ResizeArray<string>()
let check cond label = if not cond then failures.Add label

let bytes (s: string) = Encoding.ASCII.GetBytes s
let str (b: byte[]) = Encoding.ASCII.GetString b

let build (n: int) =
    let c = Container(M.MODERN)
    let f = Store.createFile c "a.txt" (bytes "v1")
    for i in 2 .. n do Store.writeFile c f (bytes (sprintf "v%d" i))
    c, f

// 1-8: real container, 10 revisions, limitCleanup(file, 5)
let store, fid = build 10
let before =
    Store.listRevisions store fid
    |> List.map (fun r -> r, Store.getObjectSerial store fid r)
let removed = Store.limitCleanup store fid 5u |> List.sort
let retained = Store.listRevisions store fid |> List.sort
check (List.length removed = 5) "exactly 5 removed"
check (List.length retained = 5) "exactly 5 retained"
check (removed = [ 1u; 2u; 3u; 4u; 5u ]) "removed ids"
check (retained = [ 6u; 7u; 8u; 9u; 10u ]) "retained ids"

// 6: ObjectSerials of retained revisions
for (r, serial) in before do
    if List.contains r retained then
        check (Store.getObjectSerial store fid r = serial) (sprintf "retained serial %d unchanged" r)

// 7: deleted revisions are inaccessible (frozen contract: 0x0009)
let goneRaises c revId =
    try
        Store.checkoutRevision c fid revId |> ignore
        false
    with
    | VsnException(ErrorCode.MissingRef) -> true
    | _ -> false

for gone in [ 1u; 2u; 3u; 4u; 5u ] do
    check (goneRaises store gone) (sprintf "deleted revision %d raises 0x0009" gone)

// 8: FileHead is the newest retained revision
check (Store.readFile store fid = Some (bytes "v10")) "FileHead is newest retained"

// 9: commit / reopen
let data = Store.commit store
let reopened = Store.openContainer data data.Length
check ((Store.listRevisions reopened fid |> List.sort) = retained) "reopen lists retained set"
check (Store.readFile reopened fid = Some (bytes "v10")) "reopened FileHead"
for gone in [ 1u; 2u; 3u; 4u; 5u ] do
    check (goneRaises reopened gone) (sprintf "deleted %d raises 0x0009 after reopen" gone)

// 10: recovery
let mutable recovered = true
try
    Recovery.recover data |> ignore
with _ -> recovered <- false
check recovered "recovery succeeded"

// 11-12: idempotency
for i in 1..3 do
    check ((Store.limitCleanup reopened fid 5u) = []) (sprintf "repeat %d removes nothing" i)
check ((Store.listRevisions reopened fid |> List.sort) = retained) "retained set stable"

// 13: limit greater than history removes nothing
let fresh, ffid = build 3
check ((Store.limitCleanup fresh ffid 99u) = []) "limit > history removes nothing"
check ((Store.listRevisions fresh ffid).Length = 3) "limit > history keeps all"

// 14: limit 0 rejected with 0x000C
let mutable rejected = false
try
    Store.limitCleanup reopened fid 0u |> ignore
with
| VsnException(ErrorCode.BadLimit) -> rejected <- true
| _ -> rejected <- false
check rejected "limit 0 rejected with 0x000C"
check ((Store.listRevisions reopened fid |> List.sort) = retained) "history unchanged after reject"

// 15: an unrelated file is untouched
let two, fa = build 6
let fb = Store.createFile two "b.txt" (bytes "b1")
for i in 2 .. 5 do Store.writeFile two fb (bytes (sprintf "b%d" i))
let bBefore = Store.listRevisions two fb |> List.sort
Store.limitCleanup two fa 2u |> ignore
check ((Store.listRevisions two fb |> List.sort) = bBefore) "unrelated file revisions unchanged"
check (Store.readFile two fb = Some (bytes "b5")) "unrelated file content unchanged"

let status = if failures.Count = 0 then "PASS" else "FAIL"
let fmt (xs: uint32 list) = xs |> List.map string |> String.concat ","
printfn "LIMIT_CLEANUP %s removed=%s retained=%s" status (fmt removed) (fmt retained)
for f in failures do printfn "  FAIL: %s" f
if failures.Count = 0 then 0 else 1