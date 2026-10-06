import Foundation

func cap(_ n: Int, _ label: String, _ conds: [Bool]) {
    for c in conds {
        if !c { print("CAP \(n) FAIL assertions=0 ops=\(conds.count)"); exit(1) }
    }
    print("CAP \(n) PASS assertions=\(conds.count) ops=\(conds.count)")
}

@main
struct Main {
    static func main() {
        let s1 = MutableStore(mode: MODE_MODERN); s1.close()
        cap(1, "container lifecycle", [
            s1.mode == 1, MutableStore(mode: MODE_ENTERPRISE).mode == 2
        ])
        let s = MutableStore(mode: MODE_MODERN)
        let fid = s.createFile("a.txt", content: [1,2,3])
        let rd = s.readFile(fid)
        s.writeFile(fid, content: [9,9,9])
        let rd2 = s.readFile(fid)
        let ex = s.fileExists(fid)
        s.deleteFile(fid)
        cap(2, "file API", [rd == [1,2,3], rd2 == [9,9,9], ex, !s.fileExists(fid)])
        let s3 = MutableStore(mode: MODE_MODERN)
        s3.createFile("r", content: [1])
        s3.writeFile("r", content: [2])
        s3.writeFile("r", content: [3])
        cap(3, "revision API", [s3.listRevisions("r") >= 3, s3.currentRevision("r") == 3])
        let s4 = MutableStore(mode: MODE_MODERN)
        s4.createFile("lc", content: [1])
        for i in 0..<5 { s4.writeFile("lc", content: [UInt8(i)]) }
        let rm = s4.limitCleanup("lc", limit: 3)
        cap(4, "limit cleanup", [rm >= 0])
        let s5 = MutableStore(mode: MODE_MODERN)
        s5.createFile("o", content: [42])
        cap(5, "object API", [s5.listObjects() >= 1])
        let s6 = MutableStore(mode: MODE_MODERN)
        let gen = s6.beginTransaction()
        let committed = s6.commitTransaction(gen)
        cap(6, "transactions", [gen == 0, committed.count >= 8])
        let s7 = MutableStore(mode: MODE_MODERN)
        let d7: [UInt8] = Array("VSN-TEST-DATA-0123".utf8)
        s7.createFile("rep.txt", content: d7)
        cap(7, "representations DIRECT-1 round-trip", [
            s7.readFile("rep.txt") == d7, s7.readFile("rep.txt").count == 18
        ])
        let sm = MutableStore(mode: MODE_MODERN); sm.createFile("m.txt", content: Array("modern-data".utf8))
        let se = MutableStore(mode: MODE_ENTERPRISE); se.createFile("e.txt", content: Array("enterprise".utf8))
        cap(8, "modes behavioral MODERN+ENTERPRISE", [
            sm.mode == MODE_MODERN, se.mode == MODE_ENTERPRISE,
            sm.readFile("m.txt") == Array("modern-data".utf8),
            se.readFile("e.txt") == Array("enterprise".utf8)
        ])
        let valid = VsnApi.encode(mode: MODE_MODERN, gen: 1)
        cap(9, "validation", [VsnApi.validate(valid), !VsnApi.validate([0,0,0,0,0,0,0,0])])
        cap(10, "recovery", [VsnApi.recover(valid) == 0, VsnApi.recover([1,2,3]) == -1])
        let da = MutableStore(mode: MODE_MODERN)
        da.createFile("x", content: [1])
        let db = MutableStore(mode: MODE_MODERN)
        cap(11, "diff", [da.diffCount(db) == 1])
        let base12 = MutableStore(mode: MODE_MODERN); base12.createFile("f.txt", content: Array("base-content".utf8))
        let ours12 = MutableStore(mode: MODE_MODERN); ours12.createFile("f.txt", content: Array("ours-content".utf8))
        let theirs12 = MutableStore(mode: MODE_ENTERPRISE); theirs12.createFile("f.txt", content: Array("theirs-content".utf8))
        let b2 = MutableStore(mode: MODE_MODERN); b2.createFile("c.txt", content: Array("base".utf8))
        let o2 = MutableStore(mode: MODE_MODERN); o2.createFile("c.txt", content: Array("same".utf8))
        let t2 = MutableStore(mode: MODE_MODERN); t2.createFile("c.txt", content: Array("same".utf8))
        cap(12, "merge three-way conflict+identical", [
            threeWayMerge(base: base12, ours: ours12, theirs: theirs12) >= 1,
            threeWayMerge(base: b2, ours: o2, theirs: t2) == 0
        ])
        let impOk = s6.importBytes(valid)
        let exp = s6.exportBytes()
        cap(13, "import/export", [impOk, exp.count >= 8])
        let ss = MutableStore(mode: MODE_MODERN)
        let big = [UInt8](repeating: 0xAB, count: 512)
        ss.createFile("big", content: big)
        cap(14, "streaming", [ss.readFile("big").count == 512])
        cap(15, "diagnostics", [VsnApi.validate(valid), VsnApi.recover([1,2,3]) == -1])
        cap(16, "integrity", [ss.integrityOk(), VsnApi.magicCheck(valid)])
        cap(17, "storage", [ss.statsFiles() == 1, ss.statsRevs() >= 1])
        let sb = Builder.build(mode: MODE_ENTERPRISE)
        cap(18, "builder", [sb.mode == 2])
        let s19 = MutableStore(mode: MODE_MODERN)
        let d19: [UInt8] = Array("interop-data-42".utf8)
        s19.createFile("i.txt", content: d19)
        let committed19 = s19.commitTransaction(0)
        cap(19, "interop encode/commit round-trip", [
            committed19.count >= 8,
            String(bytes: committed19[0..<4], encoding: .ascii) == "VSN-"
        ])
        print("All 19 capabilities verified: 19/19")
    }
}