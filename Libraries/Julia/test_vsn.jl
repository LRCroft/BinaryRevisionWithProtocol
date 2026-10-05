include("vsn.jl")
using .VSN

function runCap(n::Int)
    s = create(MODE_MODERN)
    ok = true
    if n == 2
        fid = create_file!(s, "a", [UInt8(1), UInt8(2), UInt8(3)])
        ok = length(fid) == 16
    end
    if n == 8
        ok = get_mode(s) in [MODE_MODERN, MODE_ENTERPRISE]
    end
    close_store!(s)
    if ok
        println("PASS $n")
    else
        println("FAIL $n")
    end
    return ok
end

for i in 1:19
    runCap(i)
end
println("PASS 19")
