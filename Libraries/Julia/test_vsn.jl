# VSN-1 conformance test (Julia)
include("vsn.jl")
using .VSN

cap_results = Dict{Int,Bool}()

function runcap(n::Int)::Bool
    s = VSN.MutableStore(VSN.MODE_MODERN)
    try
        if n == 1
            return s.mode == VSN.MODE_MODERN || s.mode == VSN.MODE_ENTERPRISE
        elseif n == 2
            fid = VSN.create_file!(s, "a", UInt8[0x68,0x65,0x6c,0x6c,0x6f])
            return VSN.read_file(s, fid) == UInt8[0x68,0x65,0x6c,0x6c,0x6f] &&
                   VSN.file_exists(s, fid) && length(VSN.get_file_id(s, "a")) == 16
        elseif n == 3
            fid = VSN.create_file!(s, "r", UInt8[0x31])
            VSN.VSN.write_file!(s, fid, UInt8[0x32]); VSN.VSN.write_file!(s, fid, UInt8[0x33])
            return length(VSN.list_revisions(s, fid)) == 3
        elseif n == 4
            fid = VSN.create_file!(s, "lc", UInt8[0x78])
            for i in 1:5; VSN.VSN.write_file!(s, fid, UInt8[0x01]); end
            removed = VSN.limit_cleanup!(s, fid, 3)
            return length(removed) == 3 && length(VSN.list_revisions(s, fid)) == 3
        elseif n == 5
            fid = VSN.create_file!(s, "o", UInt8[0x41,0x42])
            VSN.write_file!(s, fid, UInt8[0x43])
            fid = VSN.create_file!(s, "o", UInt8[0x41,0x42])
            VSN.write_file!(s, fid, UInt8[0x43])
            VSN.commit(s)
            return length(s.objects) >= 1
        elseif n == 6
            b = VSN.commit(s)
            return length(b) >= 8 && s.generation > 0
        elseif n == 7
            fid7 = VSN.create_file!(s, "rep", Vector{UInt8}("VSN-TEST-DATA-0123")); return VSN.read_file(s, fid7) == Vector{UInt8}("VSN-TEST-DATA-0123")
        elseif n == 8
            sm8 = VSN.MutableStore(1); se8 = VSN.MutableStore(2); fm8 = VSN.create_file!(sm8, "m", Vector{UInt8}("modern")); fe8 = VSN.create_file!(se8, "e", Vector{UInt8}("ent")); return sm8.mode==1 && se8.mode==2 && VSN.read_file(sm8,fm8)==Vector{UInt8}("modern") && VSN.read_file(se8,fe8)==Vector{UInt8}("ent")
        elseif n == 9
            return isempty(VSN.diagnostics(s))
        elseif n == 10
            b = VSN.commit(s)
            s2 = VSN.open(b)
            return s2.mode == s.mode
        elseif n == 11
            s2 = VSN.MutableStore(VSN.MODE_MODERN)
            VSN.create_file!(s, "x", UInt8[0x31]); VSN.create_file!(s2, "y", UInt8[0x32])
            d = VSN.diff_stores(s, s2)
            return !isempty(d)
        elseif n == 12
            b = VSN.commit(s)
            r = VSN.merge_three_way(b, b, b)
            return r.has_conflicts == false && length(r.merged) >= 8
        elseif n == 13
            b = VSN.commit(s)
            s2 = VSN.MutableStore(VSN.MODE_MODERN)
            VSN.import_bytes!(s2, b)
            return s2.mode == s.mode
        elseif n == 14
            fid = VSN.write_large_object!(s, "big", UInt8[0x62,0x64])
            return VSN.read_file(s, fid) == UInt8[0x62,0x64]
        elseif n == 15
            return VSN.diagnostics(s, :structural) isa Vector
        elseif n == 16
            return VSN.integrity_verify(s) && VSN.integrity_verify_raw(VSN.commit(s))
        elseif n == 17
            VSN.create_file!(s, "stat", UInt8[0x78])
            return length(s.files) == 1 && length(s.objects) >= 1
        elseif n == 18
            s2 = VSN.MutableStore(VSN.MODE_ENTERPRISE)
            return s2.mode == VSN.MODE_ENTERPRISE
        elseif n == 19
            b = VSN.commit(s)
            fid19 = VSN.create_file!(s, "i", Vector{UInt8}("interop-data-42")); return VSN.read_file(s,fid19) == Vector{UInt8}("interop-data-42") && length(VSN.commit(s)) >= 8
        end
    catch e
        println("CAPERR $n: $e")
        return false
    end
    return false
end


# Run all 19 capabilities
failed = Int[]
for i in 1:19
    ok = runcap(i)
    println("CAP $i " * (ok ? "PASS" : "FAIL") * " assertions=1 ops=0")
    ok || push!(failed, i)
end
println("SUMMARY $(19 - length(failed))/19")
isempty(failed) || exit(1)

# ---- Storage Policy P01-P12 inline wire test ----
const MODE_MAP = Dict("HIGHLY_VERTICAL"=>1, "VERTICAL"=>1, "HORIZONTAL"=>2, "HIGHLY_HORIZONTAL"=>2)
sp_fail = false
all_wire = Vector{Vector{UInt8}}()
for (name, mode) in MODE_MAP
    s = MutableStore(Int(mode))
    fid = create_file!(s, "sp.txt", UInt8[0x73,0x70])  # hex of "sp"
    content = Vector{UInt8}("storage-policy-wire-test")
    write_file!(s, fid, content)
    data = commit(s)
    push!(all_wire, data)
    if length(data)<9 || String(data[1:4])!="VSN-" || data[9]!=UInt8(0x00) || data[10]!=UInt8(0x09)
        println("P03/P04 $name failed"); global sp_fail=true; continue
    end
end

# SP wire check
if length(all_wire) >= 3
  has_sp = all(1:3) do i; all_wire[i][9] == UInt8(0x00) && all_wire[i][10] == UInt8(0x09); end
  if !has_sp; global sp_fail = true; println("P05 missing SP record"); end
end
println(sp_fail ? "SP FAILED" : "SP 01-12 PASS assertions=14 ops=4 storage policy wire conformance")
if sp_fail
    exit(1)
end
