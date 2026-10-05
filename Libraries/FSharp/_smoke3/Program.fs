module ProbeModule
let marker () : string = "HELLO_FROM_FSHARP_MARKER"

[<EntryPoint>]
let main argv =
    printfn "%s" (marker ())
    0