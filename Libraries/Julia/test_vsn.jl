include("vsn.jl")
using .VSN

function runCap(n::Int)
    s = create(MODE_MODERN)
    ok = false
    if n == 1
        ok = get_mode(s) == MODE_MODERN
    elseif n == 2
        fid = create_file!(s, "a", [UInt8(1), UInt8(2), UInt8(3)])
        ok = length(fid) == 16
    elseif n == 3
        fid = create_file!(s, "r", [UInt8(1)])
        write_file!(s, fid, [UInt8(2)])
        write_file!(s, fid, [UInt8(3)])
        ok = length(list_revisions(s, fid)) >= 3
    elseif n == 4
        fid = create_file!(s, "lc", [UInt8(1)])
        for i in 1:5; write_file!(s, fid, [UInt8(i)]); end
        removed = limit_cleanup!(s, fid, 3)
        ok = length(removed) == 2
    elseif n == 5
        create_file!(s, "o", [UInt8(1), UInt8(2)])
        ok = length(list_objects(s)) >= 1
    elseif n == 6
        tx = s; stage_add(tx, "t", [UInt8(1)])
        out_bytes = commit(s); ok = length(out_bytes) >= 8
    elseif n == 7
        ok = REP_DIRECT_1 == 1 && REP_EXTENTS_1 == 2
    elseif n == 8
        ok = get_mode(s) in [MODE_MODERN, MODE_ENTERPRISE]
    elseif n == 9
        ok = validate_structural(s)
    elseif n == 10
        ok = recover(encode(1, 1)) == 0
    elseif n == 11
        s2 = create(MODE_MODERN); create_file!(s, "x", [UInt8(1)]); d = diff_stores(s, s2)
        ok = !isempty(getfield(d, :added))
    elseif n == 12
        base=create(MODE_MODERN); ours=create(MODE_MODERN); theirs=create(MODE_MODERN)
        m = merge_three_way(base, ours, theirs); ok = !isnothing(m)
    elseif n == 13
        bytes = export_bytes(s); s2 = open(bytes); ok = get_mode(s2) == MODE_MODERN
    elseif n == 14
        fid = create_file!(s, "big", [UInt8(1), UInt8(2), UInt8(3)]); content = read_file(s, fid)
        ok = length(content) == 3
    elseif n == 15
        bytes = export_bytes(s); diags = diagnostics(s, "Full"); ok = isa(diags, Vector)
    elseif n == 16
        bytes = export_bytes(s); ok = integrity_verify(bytes)
    elseif n == 17
        create_file!(s, "stat", [UInt8(1)]); stats = get_stats(s); ok = getfield(stats, :files) >= 1
    elseif n == 18
        b = new_builder(MODE_ENTERPRISE); ok = get_mode(b) in [MODE_MODERN, MODE_ENTERPRISE]
    elseif n == 19
        bytes = encode(1, 1); ok = check_magic_bytes(bytes)
    end
    close_store!(s)
    if ok
        println("PASS $n")
    else
        println("FAIL $n")
    end
    return ok
end

passed = 0
for i in 1:19
    if runCap(i); passed += 1; end
end
println("PASS $passed")
if passed < 19; exit(1); end
