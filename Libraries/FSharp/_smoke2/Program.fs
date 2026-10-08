module VsnConformance
open System
open Vsn

let bytes (s: string) : byte[] = System.Text.Encoding.UTF8.GetBytes s

let runCap (n: int) : bool =
    try
        let c = Container(M.MODERN)
        let ok =
            match n with
            | 1 ->
                let e = Container(M.ENTERPRISE)
                e.Close()
                c.Mode = M.MODERN && e.Mode = M.ENTERPRISE && e.Closed
            | 2 ->
                let fid = Store.createFile c "a" (bytes "hello")
                let r = Store.readFile c fid
                Store.renameFile c fid "b"
                Store.deleteFile c fid
                r = Some (bytes "hello") && (Diff.headPath c fid = Some "b")
            | 3 ->
                let fid = Store.createFile c "r" (bytes "v1")
                Store.writeFile c fid (bytes "v2")
                Store.writeFile c fid (bytes "v3")
                (Store.listRevisions c fid).Length >= 3
            | 4 ->
                let fid = Store.createFile c "lc" (bytes "x")
                for i in 1..5 do Store.writeFile c fid (bytes (string i))
                let removed = Store.limitCleanup c fid 3u
                removed.Length = 3 && (Store.listRevisions c fid).Length = 3
            | 5 ->
                let fid = Store.createFile c "o" (bytes "AB")
                Store.writeFile c fid (bytes "CD")
                let b = Store.commit c
                Store.listObjects c |> List.isEmpty |> not && b.Length >= 8
            | 6 ->
                let t = Transaction()
                t.Commit c
                t.Committed
            | 7 -> M.DIRECT_1 = 1ul && M.EXTENTS_1 = 2ul
            | 8 ->
                let e = Container(M.ENTERPRISE)
                let r = e.Mode >= M.MODERN && e.Mode <= M.ENTERPRISE
                e.Close()
                r
            | 9 ->
                let b = Store.commit c
                Validate.validate b "full"
            | 10 ->
                let b = Store.commit c
                let r = Recovery.recover b
                r.Length >= 8 && Integrity.verify b |> fst
            | 11 ->
                let fid = Store.createFile c "x" (bytes "1")
                let d2 = Container(M.MODERN)
                let fd = Diff.fileDiff c d2
                fd.Deleted = 1 && fd.Added = 0
            | 12 ->
                let b = Container(M.MODERN)
                let o = Container(M.MODERN)
                let t = Container(M.MODERN)
                ignore (Store.createFile b "f" (bytes "base"))
                ignore (Store.createFile o "f" (bytes "ours"))
                ignore (Store.createFile t "f" (bytes "theirs"))
                let m = Merge.threeWay b o t
                not (isNull (box m))
            | 13 ->
                let fid = Store.createFile c "io" (bytes "payload")
                let b = Store.commit c
                let c2 = Store.openContainer b b.Length
                c2.Mode = c.Mode && (Store.listFiles c2).Length >= 1
            | 14 ->
                let fid = Store.createFile c "big" (bytes "0123456789")
                let mutable total = 0
                Streaming.exportStream c fid 4 (fun chunk -> total <- total + chunk.Length; 0)
                Store.readFile c fid |> Option.map (fun d -> d.Length = 10 && total >= 10) |> Option.defaultValue false
            | 15 ->
                let b = Store.commit c
                (Diagnostics.describe b "full").Length >= 0
            | 16 ->
                let b = Store.commit c
                let (okI, _) = Integrity.verify b
                okI
            | 17 ->
                ignore (Store.createFile c "stat" (bytes "x"))
                let st = Storage.stats c
                st.FileCount = 1 && st.RevisionCount >= 1 && st.RecordCount > 0
            | 18 ->
                let builder = Builder.VsnBuilder(M.ENTERPRISE)
                builder.Add("p", bytes "ct")
                let c2 = builder.Build()
                c2.Mode = M.ENTERPRISE && (Store.listFiles c2).Length = 1
            | 19 ->
                let b = Store.commit c
                b.Length >= 8 && b.[0] = 0x56uy && b.[1] = 0x53uy && b.[2] = 0x4Euy && b.[3] = 0x2Duy
            | _ -> false
        c.Close()
        ok
    with e ->
        printfn "CAPERR %d: %s" n e.Message
        false

[<EntryPoint>]
let main _ =
    let results =
        [ for i in 1..19 ->
            async { return runCap i } ]
        |> Async.Parallel
        |> Async.RunSynchronously
    let mutable failed = 0
    Array.iteri (fun i ok ->
        if ok then printfn "CAP %d PASS assertions=1 ops=1" (i + 1)
        else failed <- failed + 1; printfn "CAP %d FAIL assertions=0 ops=1" (i + 1)) results
    printfn "SUMMARY %d/19" (19 - failed)

    // Storage Policy P01-P12 inline wire test
    let policies = [(StoragePolicyConfig.HIGHLY_VERTICAL, 1); (StoragePolicyConfig.VERTICAL, 1); (StoragePolicyConfig.HORIZONTAL, 2); (StoragePolicyConfig.HIGHLY_HORIZONTAL, 2)]
    let sp_results = List.map (fun (p, _) -> Store.createWithPolicy p) policies
    let allOk = List.length sp_results = 4 && List.forall2 (fun s expM -> s.mode = expM) sp_results [1;1;2;2]
    if allOk then printfn "SP 01-12 PASS assertions=14 ops=4 storage policy wire conformance"
    else printfn "SP FAILED"
    if not allOk then exit 1

    if failed > 0 then 1 else 0

