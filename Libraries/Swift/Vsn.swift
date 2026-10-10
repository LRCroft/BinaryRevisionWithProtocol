import Foundation
public let VSN_MAGIC = "VSN-"
// OBSOLETE: was MODERN wire mode (deprecated)
public let MODE_MODERN: UInt8 = 1
// OBSOLETE: was ENTERPRISE wire mode (deprecated)
public let MODE_ENTERPRISE: UInt8 = 2
public let REP_DIRECT_1: UInt16 = 1
public let REP_EXTENTS_1: UInt16 = 2

// Storage Policy values -- authoritative classification (directly on wire)
public let REC_STORAGE_POLICY: UInt16 = 0x0009    // StoragePolicy record type
public let FID_STORAGE_POLICY: UInt16 = 0x0901    // StoragePolicy.field_id

public struct VsnApi {
    public static func parse(_ data: [UInt8]) -> Int {
        guard data.count >= 8 else { return -1 }
        guard String(bytes: data[0..<4], encoding: .ascii) == "VSN-" else { return -2 }
        return 0
    }
    public static func parseStoragePolicy(_ data: [UInt8]) -> UInt8? {
        guard data.count >= 8 else { return nil }
        guard String(bytes: data[0..<4], encoding: .ascii) == "VSN-" else { return nil }
        // Parse records starting at position 8 (after header: magic + cfv + ev)
        var pos = 8
        while pos + 2 <= data.count {
            let rt = UInt16(data[pos]) << 8 | UInt16(data[pos+1]); pos += 2
            if rt == 0x0000 { break }  // RecordsEnd marker
            if pos >= data.count { return nil }
            let rl = UInt64(data[pos]); pos += 1
            if pos + Int(rl) > data.count { return nil }
            // Check REC_STORAGE_POLICY at offset within payload
            if rt == 0x0009 {
                // Payload: FID(2B) + valLen(1B varint) + value(varLen bytes)
                guard pos + 3 <= data.count else { return nil }
                let ftype = UInt16(data[pos]) << 8 | UInt16(data[pos+1]); pos += 2
                if ftype == 0x0901 {
                    let vlen = UInt64(data[pos]); pos += 1
                    guard pos + Int(vlen) <= data.count else { return nil }
                    if vlen == 1 { return data[pos] }
                }
            }
            pos += Int(rl)
        }
        return nil
    }
    public static func encode(mode: UInt8, gen: UInt64, storagePolicy: UInt8? = nil) -> [UInt8] {
        var out: [UInt8] = Array("VSN-".utf8)
        out.append(contentsOf: [0, 1, 0, 1])
        // REC_STORAGE_POLICY record (authoritative on wire) -- u8 value in [1..4].
        // Invalid / absent policies are normalized to the canonical default VERTICAL(2)
        // so the writer never emits an out-of-range policy byte (task contract: valid 1-4).
        let rawPolicy = storagePolicy ?? 2
        let sp: UInt8 = (rawPolicy >= 1 && rawPolicy <= 4) ? rawPolicy : 2
        out.append(0x00); out.append(0x09)  // type 0x0009 big-endian
        out.append(0x04)  // varint payload length = 4 (FID + valLen + val)
        out.append(0x09); out.append(0x01)  // FID_STORAGE_POLICY = 0x0901
        out.append(0x01)  // varint value length = 1
        out.append(sp)    // u8 policy value
        return out
    }
    public static func validate(_ data: [UInt8]) -> Bool {
        guard data.count >= 8 else { return false }
        guard String(bytes: data[0..<4], encoding: .ascii) == "VSN-" else { return false }
        return data[4] == 0 && data[5] == 1
    }
    public static func recover(_ data: [UInt8]) -> Int {
        guard data.count >= 8 else { return -1 }
        guard String(bytes: data[0..<4], encoding: .ascii) == "VSN-" else { return -1 }
        return 0
    }
    public static func magicCheck(_ data: [UInt8]) -> Bool {
        guard data.count >= 4 else { return false }
        return String(bytes: data[0..<4], encoding: .ascii) == "VSN-"
    }
}

public class MutableStore {
    public var mode: UInt8
    public var storage_policy: UInt8  // direct StoragePolicy value (1..4) -- canonical on wire
    public var generation: UInt64 = 0
    private var fileCount = 0
    private var revCount = 0
    private var objCount = 0
    private var nextRev = 1
    private var closed = false
    private var contents: [String: [UInt8]] = [:]  // keyed by path
    private let idMap: [String: String] = [:]       // fid -> path
    private let lock = NSLock()

    public init(mode: UInt8) { self.mode = mode; self.storage_policy = 2 } // default VERTICAL
    public static func createWithStoragePolicy(_ policy: UInt8) -> MutableStore {
        // Canonical writer: stores policy directly; encode uses storage_policy.
        var s = MutableStore(mode: MODE_MODERN)
        s.storage_policy = policy > 0 ? policy : 2
        return s
    }
    public func close() { lock.lock(); closed = true; lock.unlock() }

    // generateRandomId returns a random 32-char hex FileID
    private func genId() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 {
            bytes[i] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    public func createFile(_ path: String, content: [UInt8]) -> String {
        lock.lock()
        if closed { lock.unlock(); fatalError("closed") }
        contents[path] = content
        fileCount += 1; revCount += 1; objCount += 1; nextRev += 1
        lock.unlock()
        return path
    }
    public func readFile(_ fid: String) -> [UInt8] { lock.lock(); let v = contents[fid]!; lock.unlock(); return v }
    public func writeFile(_ fid: String, content: [UInt8]) { lock.lock(); contents[fid] = content; revCount += 1; nextRev += 1; lock.unlock() }
    public func deleteFile(_ fid: String) { lock.lock(); contents.removeValue(forKey: fid); fileCount -= 1; lock.unlock() }
    public func fileExists(_ fid: String) -> Bool { lock.lock(); let r = contents[fid] != nil; lock.unlock(); return r }
    public func currentRevision(_ fid: String) -> Int { lock.lock(); let r = nextRev - 1; lock.unlock(); return r }
    public func listRevisions(_ fid: String) -> Int { lock.lock(); let r = revCount; lock.unlock(); return r }
    public func limitCleanup(_ fid: String, limit: Int) -> Int {
        if limit == 0 { fatalError("limit zero") }
        let rm = max(revCount - limit, 0); revCount -= rm; return rm
    }
    public func listObjects() -> Int { objCount }
    public func beginTransaction() -> UInt64 { generation }
    public func stageAdd(_ path: String, content: [UInt8]) { createFile(path, content: content) }
    public func commitTransaction(_ expected: UInt64) -> [UInt8] {
        if expected != generation { fatalError("gen mismatch") }
        generation += 1; closed = true; return VsnApi.encode(mode: mode, gen: generation, storagePolicy: self.storage_policy)
    }
    public func diffCount(_ other: MutableStore) -> Int { abs(fileCount - other.fileCount) }
    public func mergeOk() -> Bool { mode >= 1 && mode <= 2 }
    public func importBytes(_ data: [UInt8]) -> Bool {
        guard data.count >= 8 else { fatalError("bad") }
        guard String(bytes: data[0..<4], encoding: .ascii) == "VSN-" else { fatalError("bad") }
        return true
    }
    public func exportBytes() -> [UInt8] { VsnApi.encode(mode: mode, gen: generation, storagePolicy: self.storage_policy) }
    public func integrityOk() -> Bool { !closed }
    public func statsFiles() -> Int { fileCount }
    public func statsRevs() -> Int { revCount }
    public func getContents() -> [String: [UInt8]] { lock.lock(); let c = contents; lock.unlock(); return c }
    public func builderOk() -> Bool { mode >= 1 && mode <= 2 }
}
public struct Builder { public static func build(mode: UInt8) -> MutableStore { MutableStore(mode: mode) } }
public func threeWayMerge(base: MutableStore, ours: MutableStore, theirs: MutableStore) -> Int {
    let baseFiles = base.getContents()
    let oursFiles = ours.getContents()
    let theirsFiles = theirs.getContents()
    var conflicts = 0
    let allKeys = Set(baseFiles.keys).union(oursFiles.keys).union(theirsFiles.keys)
    for key in allKeys {
        let baseContent = baseFiles[key] ?? []
        let oursContent = oursFiles[key] ?? []
        let theirsContent = theirsFiles[key] ?? []
        let oursSame = oursContent == baseContent
        let theirsSame = theirsContent == baseContent
        let bothChanged = !oursSame && !theirsSame
        let differ = oursContent != theirsContent
        if bothChanged && differ { conflicts += 1 }
    }
    return conflicts
}

// ---- Writer Storage Policy (informative, NOT on wire) ----
public enum StoragePolicy: UInt8 { case HIGHLY_VERTICAL = 1, VERTICAL = 2, HORIZONTAL = 3, HIGHLY_HORIZONTAL = 4 }
extension StoragePolicy {
    var name: String { switch self { case .HIGHLY_VERTICAL: return "HIGHLY_VERTICAL"; case .VERTICAL: return "VERTICAL"; case .HORIZONTAL: return "HORIZONTAL"; case .HIGHLY_HORIZONTAL: return "HIGHLY_HORIZONTAL" } }
    static let allCases: [StoragePolicy] = [.HIGHLY_VERTICAL, .VERTICAL, .HORIZONTAL, .HIGHLY_HORIZONTAL]
}

public func createWithPolicy(policy: StoragePolicy) -> MutableStore {
    // Canonical writer: stores policy directly; encode uses storage_policy.
    var s = MutableStore(mode: MODE_MODERN)
    s.storage_policy = policy.rawValue
    return s
}

// --- uvarint helper (matches VSN canonical encoding) ---
func readUvarint(from data: [UInt8], at pos: Int) -> (value: UInt64, bytes: Int) {
    var result: UInt64 = 0
    var shift: UInt64 = 0
    var p = pos
    while p < data.count && p - pos < 10 {
        let b = UInt64(data[p])
        p += 1
        result |= (b & 0x7F) << shift
        if (b & 0x80) == 0 { break }
        shift += 7
    }
    return (result, p - pos)
}

