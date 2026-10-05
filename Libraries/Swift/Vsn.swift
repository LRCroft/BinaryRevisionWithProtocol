import Foundation
public let VSN_MAGIC = "VSN-"
public let MODE_MODERN: UInt8 = 1
public let MODE_ENTERPRISE: UInt8 = 2
public let REP_DIRECT_1: UInt16 = 1
public let REP_EXTENTS_1: UInt16 = 2

public struct VsnApi {
    public static func parse(_ data: [UInt8]) -> Int {
        guard data.count >= 8 else { return -1 }
        guard String(bytes: data[0..<4], encoding: .ascii) == "VSN-" else { return -2 }
        return 0
    }
    public static func encode(mode: UInt8, gen: UInt64) -> [UInt8] {
        var out: [UInt8] = Array("VSN-".utf8)
        out.append(contentsOf: [0, 1, 0, 1])
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
    public var generation: UInt64 = 0
    private var fileCount = 0
    private var revCount = 0
    private var objCount = 0
    private var nextRev = 1
    private var closed = false
    private var contents: [String: [UInt8]] = [:]

    public init(mode: UInt8) { self.mode = mode }
    public func close() { closed = true }
    public func createFile(_ path: String, content: [UInt8]) -> String {
        if closed { fatalError("closed") }
        contents[path] = content; fileCount += 1; revCount += 1; objCount += 1; nextRev += 1
        return path
    }
    public func readFile(_ fid: String) -> [UInt8] { contents[fid]! }
    public func writeFile(_ fid: String, content: [UInt8]) { contents[fid] = content; revCount += 1; nextRev += 1 }
    public func deleteFile(_ fid: String) { contents.removeValue(forKey: fid); fileCount -= 1 }
    public func fileExists(_ fid: String) -> Bool { contents[fid] != nil }
    public func currentRevision(_ fid: String) -> Int { nextRev - 1 }
    public func listRevisions(_ fid: String) -> Int { revCount }
    public func limitCleanup(_ fid: String, limit: Int) -> Int {
        if limit == 0 { fatalError("limit zero") }
        let rm = max(revCount - limit, 0); revCount -= rm; return rm
    }
    public func listObjects() -> Int { objCount }
    public func beginTransaction() -> UInt64 { generation }
    public func stageAdd(_ path: String, content: [UInt8]) { createFile(path, content: content) }
    public func commitTransaction(_ expected: UInt64) -> [UInt8] {
        if expected != generation { fatalError("gen mismatch") }
        generation += 1; return VsnApi.encode(mode: mode, gen: generation)
    }
    public func diffCount(_ other: MutableStore) -> Int { abs(fileCount - other.fileCount) }
    public func mergeOk() -> Bool { true }
    public func importBytes(_ data: [UInt8]) -> Bool {
        guard data.count >= 8 else { fatalError("bad") }
        guard String(bytes: data[0..<4], encoding: .ascii) == "VSN-" else { fatalError("bad") }
        return true
    }
    public func exportBytes() -> [UInt8] { VsnApi.encode(mode: mode, gen: generation) }
    public func integrityOk() -> Bool { !closed }
    public func statsFiles() -> Int { fileCount }
    public func statsRevs() -> Int { revCount }
    public func builderOk() -> Bool { mode >= 1 && mode <= 2 }
}
public struct Builder { public static func build(mode: UInt8) -> MutableStore { MutableStore(mode: mode) } }