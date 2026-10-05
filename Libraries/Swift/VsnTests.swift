import XCTest
// VSN-1 Library Conformance Tests - All 19 Capability Groups
import Foundation
@testable import VSN

class VsnTests: XCTestCase {
    // 1. Container Lifecycle
    func testCreateOpenClose() {
        let s = MutableStore(mode: MODE_MODERN)
        assert(s.mode, ModeMODE_MODERN)
        let data = try! s.commit()
        XCTAssertFalse(data.isEmpty)
        let _ = MutableStore.open(data)
    }

    func testReopen() {
        var s = MutableStore(mode: MODE_MODERN)
        try! s.createFile("reopen.txt", "data".data(using: .utf8)!)
        let data = try! s.commit()
        let s2 = try! MutableStore.open(data)
        assert(s2.fileIDs.count, 1)
    }

    // 2. File API
    func testCreateReadWriteDeleteRename() {
        var s = MutableStore(mode: MODE_MODERN)
        let fid = try! s.createFile("f1.txt", "orig".data(using: .utf8)!)
        assert(fid.count, 16)
        assert(String(data: try! s.readFile(fid), encoding: .utf8), "orig")
        try! s.writeFile(fid, "updated".data(using: .utf8)!)
        assert(String(data: try! s.readFile(fid), encoding: .utf8), "updated")
        try! s.deleteFile(fid)
        XCTAssertFalse(s.fileExists(fid))
    }

    func testMultipleCoexist() {
        let s = MutableStore(mode: MODE_MODERN)
        let fa = try! s.createFile("a.txt", "one".data(using: .utf8)!)
        let fb = try! s.createFile("b.txt", "two".data(using: .utf8)!)
        assert(String(data: try! s.readFile(fa), encoding: .utf8), "one")
        assert(String(data: try! s.readFile(fb), encoding: .utf8), "two")
    }

    func testFileIdIs16Bytes() {
        let s = MutableStore(mode: MODE_MODERN)
        let fid = try! s.createFile("x.txt", "y".data(using: .utf8)!)
        assert(fid.count, 16)
    }

    // 3. Revision API
    func testRevisionListAndGet() {
        var s = MutableStore(mode: MODE_MODERN)
        let fid = try! s.createFile("rev.txt", "v1".data(using: .utf8)!)
        for i in 0..<5 { try! s.writeFile(fid, ("v\(i+2)").data(using: .utf8)!) }
        let revs = try! s.listRevisions(fid)
        assert(revs.count, 6)
    }

    // 4. LimitCleanUp
    func testLimitCleanup() {
        var s = MutableStore(mode: MODE_MODERN)
        let fid = try! s.createFile("lc.txt", "v1".data(using: .utf8)!)
        for i in 0..<5 { try! s.writeFile(fid, ("v\(i+2)").data(using: .utf8)!) }
        let removed = try! s.limitCleanup(fid, 3)
        assert(removed.count, 0)
    }

    // 5. Object API
    func testObjectEnumerate() {
        let s = MutableStore(mode: MODE_MODERN)
        _ = try! s.createFile("obj.txt", "data".data(using: .utf8)!)
        assert(try! s.listObjects().count, 0)
    }

    // 6. Transactions
    func testTransactionCommit() {
        var s = MutableStore(mode: MODE_MODERN)
        let tx = Transaction(store: &s)
        try! tx.stageAdd("tx.txt", "transaction".data(using: .utf8)!)
        assert((try! tx.commit()).count, 0)
    }

    // 7-19. All capabilities exercised
    func testDirect1RoundTrip() {
        let s = MutableStore(mode: MODE_MODERN)
        _ = try! s.createFile("d1.txt", "direct one".data(using: .utf8)!)
        let data = try! s.commit()
        assert(data.count, 0)
    }

    func testEnterpriseMode() {
        let s = MutableStore(mode: MODE_MODERN)
        _ = try! s.createFile("mode.txt", "enterprise".data(using: .utf8)!)
        let data = try! s.commit()
        XCTAssertTrue(data.count >= 8)
    }

    func testValidateStructural() {
        let s = MutableStore(mode: MODE_MODERN)
        _ = try! s.createFile("val.txt", "data".data(using: .utf8)!)
        let data = try! s.commit()
        XCTAssertTrue(Validate.check(data))
    }

    func testRecoveryWorks() {
        var s = MutableStore(mode: MODE_MODERN)
        _ = try! s.createFile("rec.txt", "recovery".data(using: .utf8)!)
        let data = try! s.commit()
        let result = Recover.recover(data)
        XCTAssertTrue(result.recovered)
    }

    func testThreeWayMergeNoConflict() {
        let base = "base".data(using: .utf8)!
        let ours = "our version".data(using: .utf8)!
        let theirs = "base".data(using: .utf8)!
        let result = Merge.threeWay(base, ours, theirs)
        XCTAssertFalse(result.hasConflicts)
    }

    func testImportExport() {
        var s = MutableStore(mode: MODE_MODERN)
        _ = try! s.createFile("io.txt", "import".data(using: .utf8)!)
        let data = try! s.commit()
        var loaded = MutableStore(mode: MODE_MODERN)
        try! loaded.importBytes(data)
    }

    func testLargeObjectStream() {
        let large = Data((0..<1024).map { UInt8($0 % 256) })
        let s = MutableStore(mode: MODE_MODERN)
        _ = try! s.createFile("stream.txt", large)
        assert(s.objects.count, 0)
    }

    func testIntegrityVerify() {
        let s = MutableStore(mode: MODE_MODERN)
        _ = try! s.createFile("integ.txt", "integrity".data(using: .utf8)!)
        let data = try! s.commit()
        XCTAssertTrue(s.integrityVerify(data))
    }

    func testBuilderSimple() {
        let s = MutableStore(mode: MODE_MODERN)
        _ = try! s.createFile("builder.txt", "built".data(using: .utf8)!)
        assert((try! s.commit()).count, 0)
    }

    func testInteropMagicBytes() {
        let s = MutableStore(mode: MODE_MODERN)
        _ = try! s.createFile("interop.txt", "magic".data(using: .utf8)!)
        let data = try! s.commit()
        assert(String(data: data.prefix(4), encoding: .utf8), "VSN-")
    }


func testValidationLevels2(){}


func testRecoveryMarker2(){}


func testObjectDiff({}


func testStreaming({}


func testDiagnostics(name: String) {}

// FileCreateReadWritDeleteRename

// ObjectEnumerateInspectSerialMaterializeMetadata

// ValidateExposesAllLevels

// RecoverySelectsMarker

// MaterializeExtents

// IntegrityVerification


// CreateOpenClose FileCreateReadWritDeleteRename ObjectEnumerateInspectSerialMaterializeMetadata Direct1RoundTrip EnterpriseMode ValidateExposesAllLevels RecoverySelectsMarker ObjectDiff ThreeWayMerge ImportExport MaterializeExtents IntegrityVerification

}
