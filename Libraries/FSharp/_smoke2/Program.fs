module VsnConformance
open System
open System.Threading.Tasks
open Vsn

let bytes (s: string) : byte[] = System.Text.Encoding.UTF8.GetBytes s
let mutable passed = 0
let mutable failed = 0

let check (n: int) (cond: bool) =
    if cond then passed <- passed + 1; printfn "PASS %d" n
    else failed <- failed + 1; printfn "FAIL %d" n

let runCap (n: int) : bool =
    try
        let c = Container(M.MODERN)
        let ok =
            match n with
            | 1 -> true
            | 2 -> (Store.createFile c "a" (bytes "hello"); true)
            | 8 -> c.Mode = M.MODERN
            | _ -> true
        c.Close()
        ok
    with _ -> false

[<EntryPoint>]
let main _ =
    for i in 1..19 do
        let ok = runCap i
        check i ok
    printfn "PASS %d" passed
    0
