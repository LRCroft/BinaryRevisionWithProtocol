# VSN-1 independent consumer (Julia) -- Storage Policy round-trip.
# Uses the library's VSN.encode (wire-out) + VSN.parse (wire-in).
include("../../Julia/vsn.jl")

function sig(b)
    for i in 0:max(0, length(b) - 7)
        if i >= 0 && b[i + 1] == 0x00 && b[i + 2] == 0x09 && b[i + 3] == 0x04 &&
           b[i + 4] == 0x09 && b[i + 5] == 0x01 && b[i + 6] == 0x01
            return true
        end
    end
    return false
end

bad = false
for p in 1:4
    b = VSN.encode(1, 0, p)
    c = VSN.parse(b)
    if !sig(b)
        global bad = true
        println("FAIL p=$p wire-out")
    end
    if c.storage_policy != p
        global bad = true
        println("FAIL p=$p got=$(c.storage_policy)")
    end
end

println(bad ? "CONSUMER JULIA FAIL" : "CONSUMER JULIA PASS")
exit(bad ? 1 : 0)
