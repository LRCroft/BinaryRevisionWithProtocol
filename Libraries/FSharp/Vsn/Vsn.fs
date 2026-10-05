// VSN-1 Library — F# implementation (byte-compatible with the C/Python/C#/TS references).
namespace Vsn

open System
open System.Collections.Generic
open System.Text

// VSN-1 error codes (mirrors vsn.h)
type ErrorCode =
    | OK = 0
    | BadMagic = 1
    | Malformed = 2
    | BadCfv = 3
    | BadEv = 4
    | MissingObject = 8
    | MissingRef = 9
    // Frozen protocol/library error used by the limit-zero rejection probe.
    | BadLimit = 0x0C
    | FieldOrder = 0x11
    | InvalidState = 0x0C
    | Truncated = 0x20
    | Prim = 0x30
    | Cap = 0x40

exception VsnException of ErrorCode

// Bring the error-code cases into scope so they can be used unqualified.
module ErrorCodes =
    let OK = ErrorCode.OK
    let BadMagic = ErrorCode.BadMagic
    let Malformed = ErrorCode.Malformed
    let BadCfv = ErrorCode.BadCfv
    let BadEv = ErrorCode.BadEv
    let MissingObject = ErrorCode.MissingObject
    let MissingRef = ErrorCode.MissingRef
    let BadLimit = ErrorCode.BadLimit
    let FieldOrder = ErrorCode.FieldOrder
    let InvalidState = ErrorCode.InvalidState
    let Truncated = ErrorCode.Truncated
    let Prim = ErrorCode.Prim
    let Cap = ErrorCode.Cap

open ErrorCodes

// Record types
module RT =
    let END = 0x0000us
    let FILE_ID = 0x0001us
    let REVISION = 0x0002us
    let FILE_HEAD = 0x0004us
    let OBJ = 0x0005us
    let COMMIT = 0x0006us
    let MODE = 0x0007us

// Field IDs
module FID =
    let RECORDS_END = 0x0000us
    let FILE_ID = 0x0101us
    let REV_ID = 0x0201us
    let REV_FILE_ID = 0x0202us
    let REV_SERIAL = 0x0203us
    let REV_PATH = 0x0210us
    let REV_PRESENCE = 0x0211us
    let HEAD_FILE = 0x0401us
    let HEAD_REV = 0x0402us
    let OBJ_SERIAL = 0x0501us
    let OBJ_SIZE = 0x0511us
    let COMMIT_GEN = 0x0601us
    let MODE = 0x0701us

// Modes / Representations / Operands
module M =
    let MODERN = 1
    let ENTERPRISE = 2
    let DIRECT_1 = 0x0001ul
    let EXTENTS_1 = 0x0002ul
    let OP_LITERAL = 0
    let OP_OBJECT = 1
    let OP_NUMERIC = 2
    let OP_NESTED = 3
    let MAX_CONTENT = 4096
    let MAX_FILES = 64
    let MAX_REVISIONS = 256
    let MAX_OBJECTS = 64

// --- Data model ---
type FileId = { Id: byte[] }
type Revision = { RevId: uint32; File: FileId; Serial: uint32; Path: string; Presence: byte; Used: bool }
type ContentObject = { Serial: uint32; Len: uint32; Data: byte[]; Used: bool }
type FileDiff = { Added : int; Modified : int; Deleted : int; Unchanged : int }
type ThreeWayResult = { Conflicts : int; HasContent : bool }


// --- Primitives (byte-compatible with vsn_read_uvarint / vsn_write_uvarint) ---
module Primitives =
    let writeUvarint (v: uint64) : byte[] =
        let b = ResizeArray<byte>()
        let mutable x = v
        while x >= 0x80UL do
            b.Add(byte ((int (x &&& 0x7FUL)) ||| 0x80))
            x <- x >>> 7
        b.Add(byte (int x))
        b.ToArray()

    let readUvarint (data: byte[]) (start: int) : (uint64 * int) =
        let rec loop (value : uint64) (shift : int) (i : int) (idx : int) : (uint64 * int) =
            if i >= data.Length then raise (VsnException(ErrorCode.Truncated))
            let b = data.[i]
            if idx = 9 then
                if b = 0x01uy then (value ||| (1UL <<< 63), i + 1 - start)
                else raise (VsnException(ErrorCode.Prim))
            else
                let value' = value ||| (uint64 (int (b &&& 0x7Fuy)) <<< shift)
                if (b &&& 0x80uy) = 0uy then
                    if b = 0uy && shift > 0 then raise (VsnException(ErrorCode.Prim))
                    (value', i + 1 - start)
                else loop value' (shift + 7) (i + 1) (idx + 1)
        loop 0UL 0 start 0

    let putU16 (buf: byte[]) (off: int) (v: uint16) =
        buf.[off] <- byte (int v >>> 8)
        buf.[off + 1] <- byte (int v &&& 0xFF)

    let getU16 (p: byte[]) (off: int) : uint16 =
        uint16 (int p.[off] <<< 8 ||| int p.[off + 1])

// --- Byte writer (append-only) ---
type Writer() =
    let b = ResizeArray<byte>()
    member _.Underlying = b
    member _.Pos() = b.Count
    member _.U8(x: byte) = b.Add(x)
    member _.U16(x: uint16) = do b.Add(byte (int x >>> 8)); b.Add(byte (int x &&& 0xFF))
    member _.Bytes(x: byte[]) = b.AddRange x
    member _.Uvarint(x: uint64) = b.AddRange(Primitives.writeUvarint x)
    member _.Field(fid: uint16, fld: byte[]) =
        b.Add(byte (int fid >>> 8)); b.Add(byte (int fid &&& 0xFF))
        b.AddRange(Primitives.writeUvarint (uint64 fld.Length))
        b.AddRange fld
    member _.Record(rt: uint16, payload: byte[]) =
        b.Add(byte (int rt >>> 8)); b.Add(byte (int rt &&& 0xFF))
        b.AddRange(Primitives.writeUvarint (uint64 payload.Length))
        b.AddRange payload
    member _.ToArray() = b.ToArray()


// --- Container (mutable store, mirrors C VsnContainer) ---
open System.Threading
type Container(mode: int) =
    let lockObj = obj()
    let mutable files = ResizeArray<FileId>()
    let mutable revs = ResizeArray<Revision>()
    let mutable objects = ResizeArray<ContentObject>()
    let mutable nextRevId = 1u
    let mutable nextSerial = 1u
    let mutable generation = 0u
    let mutable closed = false
    // The mode is stored verbatim; an out-of-range value is rejected by
    // validation (mirrors C# Store/ContainerBuilder, which keep the raw byte).
    let mutable mode = mode
    member _.Files = files
    member _.Revisions = revs
    member _.Objects = objects
    member _.NextRevId 
        with get() = Monitor.Enter(lockObj); let v = nextRevId in Monitor.Exit(lockObj); v
        and set(v: uint32) = Monitor.Enter(lockObj); nextRevId <- v; Monitor.Exit(lockObj)
    member _.NextSerial 
        with get() = Monitor.Enter(lockObj); let v = nextSerial in Monitor.Exit(lockObj); v
        and set(v: uint32) = Monitor.Enter(lockObj); nextSerial <- v; Monitor.Exit(lockObj)
    member _.Generation 
        with get() = Monitor.Enter(lockObj); let v = generation in Monitor.Exit(lockObj); v
        and set(v: uint32) = Monitor.Enter(lockObj); generation <- v; Monitor.Exit(lockObj)
    member _.Mode 
        with get() = mode
        and set(v: int) = Monitor.Enter(lockObj); mode <- v; Monitor.Exit(lockObj)
    member _.Closed 
        with get() = Monitor.Enter(lockObj); let v = closed in Monitor.Exit(lockObj); v
        and set(v: bool) = Monitor.Enter(lockObj); closed <- v; Monitor.Exit(lockObj)

    static member Create(mode: int) = Container(mode)
    member x.Close() = Monitor.Enter(lockObj); x.Closed <- true; Monitor.Exit(lockObj)

    /// Deterministic 16-byte file id from path + file count (mirrors vsn_create_file).
    static member MakeFileId(path: string, count: int) : FileId =
        let id = Array.zeroCreate 16
        let n = min 16 (path.Length * 2)
        let s = Encoding.UTF8.GetBytes path
        for i in 0..(min 16 s.Length - 1) do id.[i] <- s.[i]
        id.[15] <- byte count
        { Id = id }

// --- Parser (mirrors vsn_parse / parse_fields_into) ---
module Parser =
    let setLast (c: Container) (f: Revision -> Revision) =
        let rs = c.Revisions
        if rs.Count > 0 then rs.[rs.Count - 1] <- f rs.[rs.Count - 1]

    let parseFieldsInto (data: byte[]) (start: int) (rlen: int) (recType: uint16) (c: Container) =
        let mutable pos = start
        let endp = start + rlen
        while pos < endp do
            if pos + 2 > endp then raise (VsnException(Truncated))
            let fid = Primitives.getU16 data pos
            pos <- pos + 2
            let (flen, fb) = Primitives.readUvarint data pos
            pos <- pos + fb
            if flen > uint64 (endp - pos) then raise (VsnException(Truncated))
            let vstart = pos
            pos <- pos + int flen
            if recType = RT.FILE_ID && fid = FID.FILE_ID && flen = 16UL then
                if c.Files.Count < M.MAX_FILES then c.Files.Add({ Id = data.[vstart..(vstart + 15)] })
            elif recType = RT.REVISION then
                if fid = FID.REV_ID then
                    let (rid, _) = Primitives.readUvarint data vstart
                    if c.Revisions.Count < M.MAX_REVISIONS then
                        c.Revisions.Add({ RevId = uint32 rid; File = { Id = Array.zeroCreate 16 }; Serial = 0u; Path = ""; Presence = 0uy; Used = true })
                        if rid >= uint64 c.NextRevId then c.NextRevId <- uint32 rid + 1u
                elif fid = FID.REV_FILE_ID && flen = 16UL && c.Revisions.Count > 0 then
                    setLast c (fun r -> { r with File = { Id = data.[vstart..(vstart + 15)] } })
                elif fid = FID.REV_SERIAL && c.Revisions.Count > 0 then
                    let (s, _) = Primitives.readUvarint data vstart
                    setLast c (fun r -> { r with Serial = uint32 s })
                elif fid = FID.REV_PATH && c.Revisions.Count > 0 then
                    let v = if flen = 0UL then "" else Encoding.UTF8.GetString(data, vstart, int flen)
                    setLast c (fun r -> { r with Path = v })
                elif fid = FID.REV_PRESENCE && flen >= 1UL && c.Revisions.Count > 0 then
                    setLast c (fun r -> { r with Presence = data.[vstart] })
            elif recType = RT.COMMIT && fid = FID.COMMIT_GEN then
                let (gen, _) = Primitives.readUvarint data vstart
                c.Generation <- uint32 gen
            elif recType = RT.MODE && fid = FID.MODE && flen >= 1UL then
                c.Mode <- int data.[vstart]
            elif recType = RT.OBJ && fid = FID.OBJ_SERIAL then
                let (os, _) = Primitives.readUvarint data vstart
                if c.Objects.Count < M.MAX_OBJECTS then c.Objects.Add({ Serial = uint32 os; Len = 0u; Data = Array.zeroCreate 0; Used = true })
                if os >= uint64 c.NextSerial then c.NextSerial <- uint32 os + 1u
            elif recType = RT.OBJ && fid = FID.OBJ_SIZE then
                let (osz, _) = Primitives.readUvarint data vstart
                if c.Objects.Count > 0 then
                    let os = c.Objects
                    os.[os.Count - 1] <- { os.[os.Count - 1] with Len = uint32 osz }
        ()

    let parse (data: byte[]) (len: int) (c: Container) =
        c.Files.Clear(); c.Revisions.Clear(); c.Objects.Clear()
        if len < 8 then raise (VsnException(Truncated))
        if data.[0] <> 0x56uy || data.[1] <> 0x53uy || data.[2] <> 0x4Euy || data.[3] <> 0x2Duy then raise (VsnException(BadMagic))
        if Primitives.getU16 data 4 <> 1us then raise (VsnException(BadCfv))
        if Primitives.getU16 data 6 <> 1us then raise (VsnException(BadEv))
        c.Mode <- M.MODERN; c.NextRevId <- 1u; c.NextSerial <- 1u
        let mutable pos = 8
        let mutable hd = false
        while not hd && pos + 2 <= len do
            let fid = Primitives.getU16 data pos
            pos <- pos + 2
            let (flen, fb) = Primitives.readUvarint data pos
            pos <- pos + fb
            if fid = FID.RECORDS_END then
                if flen <> 0UL then raise (VsnException(BadMagic))
                hd <- true
            else
                if flen > uint64 (len - pos) then raise (VsnException(Truncated))
                pos <- pos + int flen
        let mutable recDone = false
        while not recDone && pos + 2 <= len do
            let rt = Primitives.getU16 data pos
            if rt = RT.END then pos <- pos + 2; recDone <- true
            else
                pos <- pos + 2
                let (rlen, rb) = Primitives.readUvarint data pos
                pos <- pos + rb
                if rlen > uint64 (len - pos) then raise (VsnException(Truncated))
                if rt >= 0x8000us && rt <= 0xFFFEus then pos <- pos + int rlen
                elif rt = 0xFFFFus then raise (VsnException(Cap))
                else
                    parseFieldsInto data pos (int rlen) rt c
                    pos <- pos + int rlen
        let mutable objDone = false
        while not objDone && pos < len do
            let (serial, sb) = Primitives.readUvarint data pos
            pos <- pos + sb
            if serial = 0UL then
                objDone <- true
            else
                let (olen, ob) = Primitives.readUvarint data pos
                pos <- pos + ob
                if pos > len || olen > uint64 (len - pos) then raise (VsnException(Truncated))
                for i in 0..(c.Objects.Count - 1) do
                    let o = c.Objects.[i]
                    if o.Serial = uint32 serial then
                        let cp = min (int olen) (M.MAX_CONTENT - 1)
                        let d = Array.zeroCreate cp
                        Array.Copy(data, pos, d, 0, cp)
                        // The object-section length is the descriptor extent; the
                        // declared logical length (0x0511) is kept in `Len`.
                        c.Objects.[i] <- { o with Data = d }
                pos <- pos + int olen
        if pos < len then
            let (_, rc) = Primitives.readUvarint data pos
            pos <- pos + rc
        if pos < len then
            let (gen, gc) = Primitives.readUvarint data pos
            c.Generation <- uint32 gen
        ()

// --- Encoder (mirrors vsn_encode, byte-identical) ---
module Encoder =
    let fieldBytes (fields: (uint16 * byte[]) list) : byte[] =
        let w = Writer()
        for (fid, fld) in fields do w.Field(fid, fld)
        w.ToArray()

    let encode (c: Container) : byte[] =
        let w = Writer()
        let magic = [| byte 0x56; byte 0x53; byte 0x4E; byte 0x2D |]
        w.Bytes magic
        w.U16 1us  // cfv
        w.U16 1us  // ev
        w.Field(FID.RECORDS_END, [| |])
        // Mode declaration
        w.Record(RT.MODE, fieldBytes [ (FID.MODE, [| byte c.Mode |]) ])
        // File identities
        for f in c.Files do
            w.Record(RT.FILE_ID, fieldBytes [ (FID.FILE_ID, f.Id) ])
        // Revisions
        for r in c.Revisions do
            if r.Used then
                let sb = Primitives.writeUvarint (uint64 r.RevId)
                let fields =
                    [ (FID.REV_ID, sb)
                      (FID.REV_FILE_ID, r.File.Id) ]
                    @ (if r.Serial > 0u then [ (FID.REV_SERIAL, Primitives.writeUvarint (uint64 r.Serial)) ] else [])
                    @ (if r.Path.Length > 0 then [ (FID.REV_PATH, Encoding.UTF8.GetBytes r.Path) ] else [])
                    @ [ (FID.REV_PRESENCE, [| r.Presence |]) ]
                w.Record(RT.REVISION, fieldBytes fields)
        // Content objects
        for o in c.Objects do
            if o.Used then
                w.Record(RT.OBJ, fieldBytes [ (FID.OBJ_SERIAL, Primitives.writeUvarint (uint64 o.Serial)); (FID.OBJ_SIZE, Primitives.writeUvarint (uint64 o.Len)) ])
        // File heads. A FileIdentity may legitimately have no Revision yet
        // (a file created but never written); such a file contributes no head.
        for f in c.Files do
            let heads =
                c.Revisions
                |> Seq.filter (fun r -> r.Used && r.File.Id = f.Id)
                |> Seq.map (fun r -> r.RevId)
                |> Seq.toList
            if not heads.IsEmpty then
                let head = List.max heads
                if head > 0u then
                    w.Record(RT.FILE_HEAD, fieldBytes [ (FID.HEAD_FILE, f.Id); (FID.HEAD_REV, Primitives.writeUvarint (uint64 head)) ])
        // Commit marker
        w.Record(RT.COMMIT, fieldBytes [ (FID.COMMIT_GEN, Primitives.writeUvarint (uint64 c.Generation)) ])
        // End of records
        w.U8 0uy; w.U8 0uy
        // Objects section
        for o in c.Objects do
            if o.Used then
                w.Uvarint (uint64 o.Serial)
                // The object-section length is the full descriptor extent.
                w.Uvarint (uint64 o.Data.Length)
                w.Bytes o.Data
        w.U8 0uy
        // Trailer: canonical record count (all records except ModeDeclaration) + generation
        let nfile = c.Files.Count
        let nrev = c.Revisions |> Seq.filter (fun r -> r.Used) |> Seq.length
        let nobj = c.Objects |> Seq.filter (fun o -> o.Used) |> Seq.length
        let nheads =
            c.Files
            |> Seq.filter (fun f -> c.Revisions |> Seq.exists (fun r -> r.Used && r.File.Id = f.Id))
            |> Seq.length
        let cc = uint64 (nfile + nrev + nobj + nheads + 1)
        w.Uvarint cc
        w.Uvarint (uint64 c.Generation)
        w.ToArray()

// --- Store API (mirrors vsn_create_file / vsn_write_file / etc.) ---
module Store =
    let openContainer (data: byte[]) (len: int) : Container =
        let c = Container(M.MODERN)
        try Parser.parse data len c
        with VsnException(_) -> raise (VsnException(Malformed))
        c

    let newestRev (c: Container) (fid: FileId) : Revision option =
        let revs = c.Revisions |> Seq.filter (fun r -> r.Used && r.File.Id = fid.Id) |> Seq.toList
        if revs = [] then None else revs |> List.maxBy (fun r -> r.RevId) |> Some

    let createFile (c: Container) (path: string) (content: byte[]) : FileId =
        if c.Closed then raise (VsnException(InvalidState))
        if c.Files.Count >= M.MAX_FILES then raise (VsnException(Cap))
        let fid = Container.MakeFileId (path, c.Files.Count)
        c.Files.Add(fid)
        if c.Objects.Count >= M.MAX_OBJECTS then raise (VsnException(Cap))
        let serial = c.NextSerial
        c.NextSerial <- serial + 1u
        // `Len` is the declared logical content length (0x0511), not the
        // 3-byte-prefix descriptor extent kept in `Data`.
        let cp = min content.Length (M.MAX_CONTENT - 1)
        let desc = Array.zeroCreate (3 + cp)
        desc.[0] <- 0x00uy; desc.[1] <- 0x01uy; desc.[2] <- 1uy
        Array.Copy(content, 0, desc, 3, cp)
        c.Objects.Add({ Serial = serial; Len = uint32 cp; Data = desc; Used = true })
        if c.Revisions.Count >= M.MAX_REVISIONS then raise (VsnException(Cap))
        let rid = c.NextRevId
        c.NextRevId <- rid + 1u
        c.Revisions.Add({ RevId = rid; File = fid; Serial = serial; Path = path; Presence = 1uy; Used = true })
        fid

    let writeFile (c: Container) (fid: FileId) (content: byte[]) =
        if c.Closed then raise (VsnException(InvalidState))
        if c.Revisions.Count >= M.MAX_REVISIONS then raise (VsnException(Cap))
        if c.Objects.Count >= M.MAX_OBJECTS then raise (VsnException(Cap))
        let serial = c.NextSerial
        c.NextSerial <- serial + 1u
        // `Len` is the declared logical content length (0x0511), not the
        // 3-byte-prefix descriptor extent kept in `Data`.
        let cp = min content.Length (M.MAX_CONTENT - 1)
        let desc = Array.zeroCreate (3 + cp)
        desc.[0] <- 0x00uy; desc.[1] <- 0x01uy; desc.[2] <- 1uy
        Array.Copy(content, 0, desc, 3, cp)
        c.Objects.Add({ Serial = serial; Len = uint32 cp; Data = desc; Used = true })
        let rid = c.NextRevId
        c.NextRevId <- rid + 1u
        c.Revisions.Add({ RevId = rid; File = fid; Serial = serial; Path = ""; Presence = 1uy; Used = true })
        ()

    let deleteFile (c: Container) (fid: FileId) =
        if c.Closed then raise (VsnException(InvalidState))
        for i in 0..(c.Revisions.Count - 1) do
            let r = c.Revisions.[i]
            if r.Used && r.File.Id = fid.Id then c.Revisions.[i] <- { r with Presence = 2uy }
        ()

    let renameFile (c: Container) (fid: FileId) (newPath: string) =
        if c.Closed then raise (VsnException(InvalidState))
        match newestRev c fid with
        | None -> ()
        | Some best ->
            match c.Revisions |> Seq.tryFindIndex (fun r -> r.Used && r.File.Id = fid.Id && r.RevId = best.RevId) with
            | None -> ()
            | Some i -> c.Revisions.[i] <- { c.Revisions.[i] with Path = newPath }
        ()

    let listFiles (c: Container) : FileId list = c.Files |> Seq.toList

    let listRevisions (c: Container) (fid: FileId) : uint32 list =
        c.Revisions |> Seq.filter (fun r -> r.Used && r.File.Id = fid.Id) |> Seq.map (fun r -> r.RevId) |> Seq.toList

    let getObjectSerial (c: Container) (fid: FileId) (revId: uint32) : uint32 =
        let revs = c.Revisions |> Seq.filter (fun r -> r.Used && r.File.Id = fid.Id && (revId = 0u || r.RevId = revId)) |> Seq.toList
        if revs = [] then 0u
        else
            let best = revs |> List.maxBy (fun r -> r.RevId)
            if best.Presence = 2uy then 0u else best.Serial

    let contentOf (c: Container) (serial: uint32) : byte[] option =
        match c.Objects |> Seq.tryFind (fun o -> o.Used && o.Serial = serial) with
        | None -> None
        // DIRECT-1 payload starts after the 3-byte identity/version prefix;
        // the full descriptor extent lives in `Data`.
        | Some o -> if o.Data.Length <= 3 then Some [| |] else Some o.Data.[3..(o.Data.Length - 1)]

    let readFile (c: Container) (fid: FileId) : byte[] option =
        if c.Closed then raise (VsnException(InvalidState))
        match newestRev c fid with
        | None -> raise (VsnException(MissingRef))
        | Some r ->
            match contentOf c r.Serial with
            | None -> raise (VsnException(MissingRef))
            | Some v -> Some v

    let checkoutRevision (c: Container) (fid: FileId) (revId: uint32) : byte[] option =
        let revs = c.Revisions |> Seq.filter (fun r -> r.Used && r.File.Id = fid.Id && r.RevId = revId) |> Seq.toList
        match revs with
        | [] -> raise (VsnException(MissingRef))
        | r :: _ ->
            if r.Presence = 2uy then None
            else
                match contentOf c r.Serial with
                | None -> raise (VsnException(MissingRef))
                | Some v -> Some v

    let limitCleanup (c: Container) (fid: FileId) (limit: uint32) : uint32 list =
        if c.Closed then raise (VsnException(InvalidState))
        // The frozen Library contract rejects limit 0 with 0x000C.
        if limit < 1u then raise (VsnException(BadLimit))
        if not (c.Files |> Seq.exists (fun f -> f.Id = fid.Id)) then raise (VsnException(MissingRef))
        let rids = c.Revisions |> Seq.filter (fun r -> r.Used && r.File.Id = fid.Id) |> Seq.map (fun r -> r.RevId) |> Seq.toList
        if rids.Length <= int limit then []
        else
            let sorted = rids |> List.sort
            let keepStart = rids.Length - int limit
            let removed = sorted.[0..(keepStart - 1)]
            for rid in removed do
                for i in 0..(c.Revisions.Count - 1) do
                    let r = c.Revisions.[i]
                    if r.Used && r.RevId = rid then c.Revisions.[i] <- { r with Used = false }
            removed

    let commit (c: Container) : byte[] =
        if c.Closed then raise (VsnException(InvalidState))
        c.Generation <- c.Generation + 1u
        let bytes = Encoder.encode c
        let tmp = Container(M.MODERN)
        Parser.parse bytes bytes.Length tmp
        c.Files.Clear(); c.Files.AddRange tmp.Files
        c.Revisions.Clear(); c.Revisions.AddRange tmp.Revisions
        c.Objects.Clear(); c.Objects.AddRange tmp.Objects
        c.NextRevId <- tmp.NextRevId; c.NextSerial <- tmp.NextSerial
        c.Generation <- tmp.Generation; c.Mode <- tmp.Mode; c.Closed <- false
        bytes

    let reopen (c: Container) (data: byte[]) =
        if c.Closed then raise (VsnException(InvalidState))
        Parser.parse data data.Length c
        ()

    let listObjects (c: Container) : (uint32 * uint32) list =
        c.Objects |> Seq.filter (fun o -> o.Used) |> Seq.map (fun o -> (o.Serial, o.Len)) |> Seq.toList

// --- Materialize (DIRECT-1 + EXTENTS-1, cycle-guarded) ---
module Materialize =
    let findObj (c: Container) (serial: uint32) : (byte[] * uint32) option =
        match c.Objects |> Seq.tryFind (fun o -> o.Used && o.Serial = serial) with
        | None -> None
        // Callers treat the second item as the descriptor-extent length;
        // it must be the full `Data` length, not the declared logical size.
        | Some o -> Some (o.Data, uint32 o.Data.Length)

    let readOperand (d: byte[]) (dlen: int) (pos: int) : (int * uint64 * byte[] * int * int) =
        let (k, nb) = Primitives.readUvarint d pos
        let p1 = pos + nb
        let kind = int k
        if k = 0UL then
            let (l, nb2) = Primitives.readUvarint d p1
            let p2 = p1 + nb2
            if l > uint64 (dlen - p2) then raise (VsnException(Truncated))
            let lit = if int l = 0 then [| |] else d.[p2..(p2 + int l - 1)]
            (kind, 0UL, lit, int l, p2 + int l)
        elif k = 1UL || k = 2UL then
            let (v, nb2) = Primitives.readUvarint d p1
            (kind, v, [| |], 0, p1 + nb2)
        else raise (VsnException(InvalidState))

    let rec extentsBody (c: Container) (d: byte[]) (dlen: int) (pos: int) (self: uint32) (depth: int) : byte[] =
        if depth > 64 then raise (VsnException(InvalidState))
        let (opcount, nb) = Primitives.readUvarint d pos
        let mutable p = pos + nb
        let acc = ResizeArray<byte>()
        for _ in 0..(int opcount - 1) do
            // An operation is a NESTED collection of operands (VR-23, DR-3):
            //   uvarint OP_NESTED, uvarint operand count, then that many operands.
            let (kind, klen) = Primitives.readUvarint d p
            p <- p + klen
            if kind <> 3UL then raise (VsnException(InvalidState))
            let (n, nlen) = Primitives.readUvarint d p
            p <- p + nlen
            if n = 0UL then raise (VsnException(InvalidState))
            let operands = ResizeArray<int * uint64 * byte[] * int>()
            for _ in 0..(int n - 1) do
                let (okind, oval, olit, olen, p2) = readOperand d dlen p
                p <- p2
                operands.Add((okind, oval, olit, olen))
            // COPY(source, offset, length) = [src, num, num]
            // LITERAL(bytes)              = [lit, num(0)]
            let (hk, hnum, hlit, _) = operands.[0]
            if hk = 1 then
                if operands.Count <> 3 then raise (VsnException(InvalidState))
                let (k2, v2, _, _) = operands.[1]
                let (k3, v3, _, _) = operands.[2]
                if k2 <> 2 || k3 <> 2 then raise (VsnException(InvalidState))
                if hnum = uint64 self then raise (VsnException(InvalidState))
                let off = int v2
                let clen = int v3
                let tmp = materializeImpl c (uint32 hnum) (depth + 1)
                if off < 0 || clen < 0 || off > tmp.Length || clen > tmp.Length - off then
                    raise (VsnException(InvalidState))
                acc.AddRange(tmp.[off..(off + clen - 1)])
            elif hk = 0 then
                acc.AddRange hlit
            else
                raise (VsnException(InvalidState))
        // No trailing bytes are permitted after the operation collection.
        if p <> dlen then raise (VsnException(InvalidState))
        acc.ToArray()

    and materializeImpl (c: Container) (serial: uint32) (depth: int) : byte[] =
        match findObj c serial with
        | None -> raise (VsnException(MissingObject))
        | Some (d, dlen) ->
            if dlen < 3u then raise (VsnException(MissingObject))
            let rep = uint64 (int d.[0] <<< 8 ||| int d.[1])
            let (ver, nb) = Primitives.readUvarint d 2
            let pos = 2 + nb
            if rep = uint64 M.DIRECT_1 && ver = 1UL then
                let clen = int dlen - pos
                if clen <= 0 then [| |] else d.[pos..(int dlen - 1)]
            elif rep = uint64 M.EXTENTS_1 && ver = 1UL then
                extentsBody c d (int dlen) pos serial depth
            else raise (VsnException(InvalidState))

    let materialize (c: Container) (serial: uint32) : byte[] = materializeImpl c serial 0

// --- Validation (Structural | Semantic | Recovery | Content | Full) ---
module Validate =
    let level (data: byte[]) (len: int) (lvl: string) : bool =
        let c = Container(M.MODERN)
        Parser.parse data len c
        let lv = if String.IsNullOrEmpty lvl || lvl = "Basic" then "Structural" else lvl
        if lv = "Structural" then true
        elif c.Mode <> M.MODERN && c.Mode <> M.ENTERPRISE then false
        else
            let noExtents =
                c.Mode <> M.ENTERPRISE
                || (c.Objects |> Seq.filter (fun o -> o.Used) |> Seq.forall (fun o ->
                        o.Data.Length >= 3 && (int o.Data.[0] <<< 8 ||| int o.Data.[1]) <> int M.EXTENTS_1))
            let allKnown =
                c.Revisions |> Seq.filter (fun r -> r.Used) |> Seq.forall (fun r -> c.Files |> Seq.exists (fun f -> f.Id = r.File.Id))
            if not noExtents || not allKnown then false
            elif lv = "Semantic" then true
            elif c.Generation = 0u then false
            elif lv = "Recovery" then true
            else
                c.Objects |> Seq.filter (fun o -> o.Used) |> Seq.forall (fun o ->
                    try let _ = Materialize.materialize c o.Serial in true
                    with VsnException _ -> false)

    let validate (data: byte[]) (lvl: string) : bool = level data data.Length lvl

// --- Transactions (stage -> commit) ---
type TxOp = Create of string | Update of FileId | Delete of FileId

type Transaction() =
    let mutable ops = ResizeArray<TxOp>()
    let mutable committed = false
    member _.Staged() = ops.Count
    member x.StageCreate(path: string) = if x.Committed || ops.Count >= 64 then raise (VsnException(InvalidState)) else ops.Add(Create path); ()
    member x.StageUpdate(fid: FileId) = if x.Committed || ops.Count >= 64 then raise (VsnException(InvalidState)) else ops.Add(Update fid); ()
    member x.StageDelete(fid: FileId) = if x.Committed || ops.Count >= 64 then raise (VsnException(InvalidState)) else ops.Add(Delete fid); ()
    member x.Rollback() = ops.Clear()
    member x.Commit(c: Container) =
        if x.Committed then raise (VsnException(InvalidState))
        for op in ops do
            match op with
            | Create p -> ignore (Store.createFile c p [| |])
            | Update f -> Store.writeFile c f [| 117uy; 100uy; 100uy |]
            | Delete f -> Store.deleteFile c f
        x.Committed <- true
        ()
    member _.Committed with get() = committed and set(v: bool) = committed <- v

// --- Diff (derived, never canonical) ---
module Diff =
    let bytesEqual (a: byte[]) (b: byte[]) = a.Length = b.Length && (a.Length = 0 || Seq.forall2 (fun x y -> x = y) a b)
    let headPath (c: Container) (fid: FileId) : string option =
        let revs = c.Revisions |> Seq.filter (fun r -> r.Used && r.File.Id = fid.Id) |> Seq.toList
        if revs = [] then None else (revs |> List.maxBy (fun r -> r.RevId)).Path |> Some
    let content (c: Container) (fid: FileId) : byte[] option =
        try Store.readFile c fid with VsnException _ -> None
    let fileDiff (a: Container) (b: Container) : FileDiff =
        let mutable added = 0
        let mutable modified = 0
        let mutable deleted = 0
        let mutable unchanged = 0
        let aMap = a.Files |> Seq.choose (fun f -> match headPath a f with None -> None | Some p -> Some (p, content a f)) |> Map.ofSeq
        let bMap = b.Files |> Seq.choose (fun f -> match headPath b f with None -> None | Some p -> Some (p, content b f)) |> Map.ofSeq
        for (p, ca) in (aMap |> Map.toList) do
            if bMap.ContainsKey p then
                if ca = bMap.[p] then unchanged <- unchanged + 1 else modified <- modified + 1
            else deleted <- deleted + 1
        for p in bMap.Keys do
            if not (aMap.ContainsKey p) then added <- added + 1
        let r = {Added = added; Modified = modified; Deleted = deleted; Unchanged = unchanged}
        r
    let revisionDiff (c: Container) (fid: FileId) (ra: uint32) (rb: uint32) : (bool * int32) =
        let ca = Store.checkoutRevision c fid ra |> Option.get
        let cb = Store.checkoutRevision c fid rb |> Option.get
        let ch = not (bytesEqual ca cb)
        (ch, int32 cb.Length - int32 ca.Length)

// --- Three-way merge (conflict detection) ---
module Merge =
    let content (c: Container) (path: string) : byte[] option =
        c.Files |> Seq.tryFind (fun f -> (Diff.headPath c f) = Some path) |> Option.map (fun f -> Diff.content c f |> Option.get)
    let threeWay (base_: Container) (ours: Container) (theirs: Container) : ThreeWayResult =
        let mutable conflicts = 0
        for f in base_.Files do
            match Diff.headPath base_ f with
            | None -> ()
            | Some pb ->
                let b_ = content base_ pb
                let o = content ours pb
                let t = content theirs pb
                let eq (x: byte[] option) (y: byte[] option) =
                    match x, y with
                    | Some a, Some b -> Diff.bytesEqual a b
                    | None, None -> true
                    | _ -> false
                let ochanged = not (eq o b_)
                let tchanged = not (eq t b_)
                if ochanged && tchanged && not (eq o t) then conflicts <- conflicts + 1
        let r = {Conflicts = conflicts; HasContent = conflicts = 0}
        r

// --- Import / Export (binary-safe) ---
module Io =
    let import (c: Container) (path: string) (content: byte[]) : FileId = Store.createFile c path content
    let export (c: Container) (fid: FileId) : byte[] option = Store.readFile c fid

// --- Streaming (chunked, callback-driven) ---
module Streaming =
    let exportStream (c: Container) (fid: FileId) (chunkSize: int) (sink: byte[] -> int) =
        let full = Store.readFile c fid |> Option.get
        let mutable off = 0
        while off < full.Length do
            let n = min chunkSize (full.Length - off)
            let r = sink (full.[off..(off + n - 1)])
            if r <> 0 then raise (VsnException(InvalidState))
            off <- off + n
        ()
    let importStream (c: Container) (path: string) (pull: int -> byte[]) : FileId =
        let acc = ResizeArray<byte>()
        let mutable i = 0
        while i < 1000000 do
            let chunk = pull 512
            if chunk.Length = 0 then i <- 1000000
            else
                acc.AddRange chunk
                i <- i + 1
        Store.createFile c path (acc.ToArray())

// --- Diagnostics (structured error output) ---
module Diagnostics =
    let name (code: ErrorCode) : string =
        match code with
        | BadMagic -> "BadMagic"
        | BadCfv -> "BadCfv"
        | BadEv -> "BadEv"
        | Truncated -> "Truncated"
        | Malformed -> "Malformed"
        | MissingRef -> "MissingReference"
        | Prim -> "PrimError"
        | Cap -> "Capacity"
        | InvalidState -> "InvalidState"
        | _ -> "Error"
    let message (code: ErrorCode) : string =
        match code with
        | BadMagic -> "Invalid container magic"
        | BadCfv -> "Unsupported container format version"
        | BadEv -> "Unsupported evolution version"
        | Truncated -> "Truncated container"
        | Malformed -> "Malformed container"
        | MissingRef -> "Dangling reference"
        | Prim -> "Invalid primitive encoding"
        | Cap -> "Capacity exceeded"
        | InvalidState -> "Invalid semantic state"
        | _ -> "Validation failed"
    type Diagnostic = {Code: ErrorCode; Name: string; Message: string}
    let describe (data: byte[]) (lvl: string) : Diagnostic list =
        try
            ignore (Validate.level data data.Length lvl)
            []
        with VsnException(e) -> [{Code = e; Name = name e; Message = message e}]

// --- Integrity (reparse + re-encode stability) ---
module Integrity =
    let verify (data: byte[]) : (bool * bool) =  // (ok, stable)
        let c = Container(M.MODERN)
        Parser.parse data data.Length c
        let re = Encoder.encode c
        let stable = re.Length = data.Length && (re |> Array.forall2 (fun x y -> x = y) data)
        (true, stable)

// --- Storage management (derived statistics) ---
module Storage =
    type Stats = {RecordCount:int; ObjectCount:int; FileCount:int; RevisionCount:int}
    let stats (c: Container) : Stats =
        {RecordCount = c.Files.Count + c.Revisions.Count + c.Objects.Count + 1 + (if c.Generation > 0u then 1 else 0) + 1
         ObjectCount = c.Objects.Count
         FileCount = c.Files.Count
         RevisionCount = c.Revisions.Count}

// --- Builder API (high-level construction) ---
module Builder =
    type VsnBuilder(mode: int) =
        let mode = if mode = M.ENTERPRISE then M.ENTERPRISE else M.MODERN
        let entries = ResizeArray<(string * byte[])>()
        member _.Add(path: string, content: byte[]) = entries.Add(path, content)
        member _.Build() : Container =
            let c = Container(mode)
            for (p, ct) in entries do ignore (Store.createFile c p ct)
            c
    let buildDirect1 (content: byte[]) : byte[] =
        let b = Array.zeroCreate (3 + content.Length)
        b.[0] <- 0x00uy; b.[1] <- 0x01uy; b.[2] <- 1uy
        Array.Copy(content, 0, b, 3, content.Length)
        b

// --- Recovery (marker-based; best-effort truncation repair) ---
module Recovery =
    type RecoveryResult = {
        AcceptedGeneration : uint32
        Recovered : bool
        TailPresent : bool
        Status : string
        Message : string
    }
    let recover (data: byte[]) : byte[] =
        try
            let tmp = Container(M.MODERN)
            Parser.parse data data.Length tmp
            Encoder.encode tmp
        with _ ->
            let mutable found : byte[] = [| |]
            let mutable ok = false
            let mutable tryLen = data.Length
            while not ok && tryLen > 10 do
                try
                    let tmp = Container(M.MODERN)
                    Parser.parse data tryLen tmp
                    found <- Encoder.encode tmp
                    ok <- true
                with _ -> ()
                tryLen <- tryLen - 1
            if not ok then raise (VsnException(Truncated))
            found
    let analyze (data: byte[]) : RecoveryResult =
        let mk (ag : uint32) (recov : bool) (tail : bool) (status : string) (msg : string) : RecoveryResult =
            { AcceptedGeneration = ag; Recovered = recov; TailPresent = tail; Status = status; Message = msg }
        try
            let tmp = Container(M.MODERN)
            Parser.parse data data.Length tmp
            let gen = tmp.Generation
            mk gen true false "RECOVERED" (sprintf "accepted generation %d" (int gen))
        with
            | VsnException(Truncated) -> mk 0u false true "TRUNCATED" "physical end reached mid-unit"
            | VsnException _ -> mk 0u false false "MALFORMED" "malformed container"