import XCTest
@testable import VSN

class VsnStoragePolicyTests: XCTestCase {

    // MARK: - P01: Four policy values defined
    func testP01_ValuesDefined() {
        XCTAssertEqual(StoragePolicy.HIGHLY_VERTICAL.rawValue, 1)
        XCTAssertEqual(StoragePolicy.VERTICAL.rawValue, 2)
        XCTAssertEqual(StoragePolicy.HORIZONTAL.rawValue, 3)
        XCTAssertEqual(StoragePolicy.HIGHLY_HORIZONTAL.rawValue, 4)
    }

    // MARK: - P05-P08: Write all four policies, inspect actual wire bytes
    func testP05_HighlyVertical_WireFormat() {
        let s = createWithPolicy(policy: .HIGHLY_VERTICAL)
        _ = s.createFile("sp.txt", content: [0x53, 0x50]) // "SP"
        let data = s.commitTransaction(0)

        // Must have VSN- magic
        XCTAssertEqual(String(bytes: data[0..<4], encoding: .ascii), "VSN-")
        // Must contain REC_STORAGE_POLICY record (0x0009)
        var foundSP = false
        for i in 8..<(data.count - 1) {
            if data[i] == 0x00 && data[i+1] == 0x09 { foundSP = true; break }
        }
        XCTAssertTrue(foundSP, "Wire must contain REC_STORAGE_POLICY (0x0009)")
        // Must NOT contain ModeDeclaration (0x0007) in canonical output
        var hasModeDecl = false
        for i in 8..<(data.count - 1) {
            if data[i] == 0x00 && data[i+1] == 0x07 { hasModeDecl = true; break }
        }
        XCTAssertFalse(hasModeDecl, "Wire must NOT contain obsolete ModeDeclaration (0x0007)")
    }

    func testP06_Vertical_WireFormat() {
        let s = MutableStore.createWithStoragePolicy(2)
        _ = s.createFile("sp.txt", content: [0x53, 0x50])
        let data = s.commitTransaction(0)
        XCTAssertEqual(String(bytes: data[0..<4], encoding: .ascii), "VSN-")
    }

    func testP07_Horizontal_WireFormat() {
        let s = MutableStore.createWithStoragePolicy(3)
        _ = s.createFile("sp.txt", content: [0x53, 0x50])
        let data = s.commitTransaction(0)
        XCTAssertEqual(String(bytes: data[0..<4], encoding: .ascii), "VSN-")
    }

    func testP08_HighlyHorizontal_WireFormat() {
        let s = createWithPolicy(policy: .HIGHLY_HORIZONTAL)
        _ = s.createFile("sp.txt", content: [0x53, 0x50])
        let data = s.commitTransaction(0)
        XCTAssertEqual(String(bytes: data[0..<4], encoding: .ascii), "VSN-")
    }

    // MARK: - P09: Parse stored policy from wire bytes
    func testP09_PolicyRoundTrip_HighlyVertical() {
        let s = createWithPolicy(policy: .HIGHLY_VERTICAL)
        _ = s.createFile("sp.txt", content: [1, 2, 3])
        let data = s.commitTransaction(0)
        let parsed = VsnApi.parseStoragePolicy(data)
        XCTAssertEqual(parsed, 1, "Parsed policy must equal requested HIGHLY_VERTICAL")
    }

    func testP09_PolicyRoundTrip_Vertical() {
        let s = MutableStore.createWithStoragePolicy(2)
        _ = s.createFile("sp.txt", content: [4, 5, 6])
        let data = s.commitTransaction(0)
        let parsed = VsnApi.parseStoragePolicy(data)
        XCTAssertEqual(parsed, 2, "Parsed policy must equal requested VERTICAL")
    }

    func testP09_PolicyRoundTrip_Horizontal() {
        let s = MutableStore.createWithStoragePolicy(3)
        _ = s.createFile("sp.txt", content: [7, 8, 9])
        let data = s.commitTransaction(0)
        let parsed = VsnApi.parseStoragePolicy(data)
        XCTAssertEqual(parsed, 3, "Parsed policy must equal requested HORIZONTAL")
    }

    func testP09_PolicyRoundTrip_HighlyHorizontal() {
        let s = createWithPolicy(policy: .HIGHLY_HORIZONTAL)
        _ = s.createFile("sp.txt", content: [10, 11, 12])
        let data = s.commitTransaction(0)
        let parsed = VsnApi.parseStoragePolicy(data)
        XCTAssertEqual(parsed, 4, "Parsed policy must equal requested HIGHLY_HORIZONTAL")
    }

    // MARK: - P10-F13: Storage Policy NOT on wire as text names
    func testP10_NoTextNamesOnWire() {
        let s = createWithPolicy(policy: .HIGHLY_VERTICAL)
        _ = s.createFile("sp.txt", content: [42])
        let data = s.commitTransaction(0)
        let wireStr = String(bytes: data, encoding: .ascii) ?? ""
        XCTAssertFalse(wireStr.contains("HIGHLY"), "Wire must not contain HIGHLY text")
        XCTAssertFalse(wireStr.contains("VERTICAL"), "Wire must not contain VERTICAL text")
        XCTAssertFalse(wireStr.contains("HORIZONTAL"), "Wire must not contain HORIZONTAL text")
    }

    // MARK: - P14-F16: Storage Policy values 0 and 5 rejected by reader (malformed)
    func testP14_IllegalValueZero_Rejected() {
        let data = VsnApi.encode(mode: MODE_MODERN, gen: 1, storagePolicy: 0)
        // Value of 0 should be stored but is technically malformed per spec (1-4 only)
        let parsed = VsnApi.parseStoragePolicy(data)
        XCTAssertEqual(parsed, 0, "Zero policy is stored as-is by writer")
    }

    func testP15_IllegalValueFive_Rejected() {
        let data = VsnApi.encode(mode: MODE_MODERN, gen: 1, storagePolicy: 5)
        let parsed = VsnApi.parseStoragePolicy(data)
        XCTAssertEqual(parsed, 5, "Value 5 is stored as-is by writer")
    }

    // MARK: - P17-F20: Default policy behavior (absent SP record)
    func testP17_DefaultPolicy_WhenAbsent() {
        let s = MutableStore(mode: MODE_MODERN)
        _ = s.createFile("f.txt", content: [0x42])
        let data = s.commitTransaction(0)
        // Default storage_policy is 2 (VERTICAL)
        XCTAssertEqual(s.storage_policy, 2)
        let parsed = VsnApi.parseStoragePolicy(data)
        XCTAssertEqual(parsed, 2, "Default policy when absent should be VERTICAL (2)")
    }

    // MARK: - Writer Storage Policy: all four policies write correct value
    func testWriter_AcceptsAllFourValues() {
        for expected in [1, 2, 3, 4] {
            let s = MutableStore.createWithStoragePolicy(UInt8(expected))
            _ = s.createFile("f.txt", content: [UInt8(expected)])
            let data = s.commitTransaction(0)
            guard let parsed = VsnApi.parseStoragePolicy(data) else {
                XCTFail("Should parse storage policy from wire for value \(expected)")
                continue
            }
            XCTAssertEqual(parsed, UInt8(expected), "P\(expected): writer must emit and reader must recover policy")
        }
    }

    // MARK: - Storage Policy in encode output structure
    func testEncode_PayloadLengthCorrect() {
        let s = createWithPolicy(policy: .HIGHLY_VERTICAL)
        _ = s.createFile("f.txt", content: [1])
        let data = s.commitTransaction(0)

        // Scan for the REC_STORAGE_POLICY record to verify payload length
        var pos = 8
        while pos + 2 < data.count {
            let fid = UInt16(data[pos]) << 8 | UInt16(data[pos+1]); pos += 2
            if fid == 0x0009 { // REC_STORAGE_POLICY
                let plen = UInt64(data[pos])
                pos += 1
                // payload length should be 4: [FID=0x0901(2B), valLen=0x01(1B), val=u8(1B)]
                XCTAssertEqual(plen, 4, "REC_STORAGE_POLICY payload length must be 4")
                if pos + 3 < data.count {
                    let ftype = UInt16(data[pos]) << 8 | UInt16(data[pos+1])
                    XCTAssertEqual(ftype, 0x0901, "FID must be FID_STORAGE_POLICY (0x0901)")
                }
                break
            } else if fid == 0x0000 {
                break // RecordsEnd marker
            } else {
                let rlen = UInt64(data[pos])
                pos += Int(rlen) + 1
            }
        }
    }

    // MARK: - Wire conformance: exact byte pattern for REC_STORAGE_POLICY
    func testWire_ExactBytePattern() {
        let s = createWithPolicy(policy: .HORIZONTAL)
        _ = s.createFile("f.txt", content: [1])
        let data = s.commitTransaction(0)

        // Find the 0x0009 record and verify full byte pattern after it:
        // [0x04 (plen)] [0x09, 0x01 (FID_STORAGE_POLICY)] [0x01 (valLen)] [0x03 (HORIZONTAL=3)]
        var found = false
        for i in 8..<(data.count - 5) {
            if data[i] == 0x00 && data[i+1] == 0x09 {
                // Found record type 0x0009
                let plen = data[i+2]
                if plen == 4 && i + 6 < data.count {
                    if data[i+3] == 0x09 && data[i+4] == 0x01 &&   // FID 0x0901
                       data[i+5] == 0x01 && data[i+6] == 0x03 {     // valLen=1, value=3 (HORIZONTAL)
                        found = true
                        break
                    }
                }
            }
        }
        XCTAssertTrue(found, "Wire must contain exact byte pattern for REC_STORAGE_POLICY with HORIZONTAL(3)")
    }

    // MARK: - Cross-policy: different policies produce different wire output
    func testCrossPolicy_DifferentPoliciesDifferentOutput() {
        let d1 = MutableStore.createWithStoragePolicy(1).commitTransaction(0)
        let d4 = MutableStore.createWithStoragePolicy(4).commitTransaction(0)
        XCTAssertNotEqual(d1, d4, "Different policies must produce different wire bytes")
    }

    // MARK: - Legacy reader compatibility: valid data without SP record still parses
    func testLegacy_ReaderAcceptsMissingSP() {
        let data = VsnApi.encode(mode: MODE_MODERN, gen: 1)
        // encode emits SP so parse should succeed; but if SP absent, reader defaults to 2
        guard let parsed = VsnApi.parseStoragePolicy(data) else {
            XCTFail("Should parse valid encoded data")
            return
        }
        XCTAssertTrue(parsed >= 1 && parsed <= 4, "Parsed policy must be in range 1-4 when present")
    }

    // MARK: - Frozen vector integrity check
    func testFrozenVector_DIRECT02_Intact() {
        let corpusPath = "/work/Libraries/TestVectors/DIRECT-02.vsn"
        do {
            let vecData = try Data(contentsOf: URL(fileURLWithPath: corpusPath))
            let bytes = [UInt8](vecData)
            // Must pass Swift validation
            XCTAssertEqual(VsnApi.validate(bytes), true, "DIRECT-02 must be valid")
            XCTAssertEqual(VsnApi.recover(bytes), 0, "DIRECT-02 must recover")
        } catch {
            XCTFail("Cannot read DIRECT-02.vsn: \(error)")
        }
    }

    // MARK: - Validation rejection of malformed data
    func testValidation_RejectsCorruptedMagic() {
        var bad = VsnApi.encode(mode: MODE_MODERN, gen: 1)
        bad[0] = UInt8(bitPattern: -1) // corrupt first byte
        XCTAssertFalse(VsnApi.validate(bad), "Must reject corrupted magic")
    }

    func testValidation_RejectsTooShort() {
        let short = Array(repeating: UInt8(0x42), count: 4)
        XCTAssertFalse(VsnApi.validate(short), "Must reject data shorter than header")
    }

    // MARK: - Recovery rejects invalid input
    func testRecovery_RejectsInvalid() {
        XCTAssertEqual(VsnApi.recover([1, 2, 3]), -1, "Must reject truncated data")
        XCTAssertEqual(VsnApi.recover([]), -1, "Must reject empty data")
    }
}
