import Foundation
import SQLite3

/// A single usage event, before aggregation.
struct Entry: Codable, Hashable, Sendable {
    var key: String  // dedupe key
    var ts: Double  // unix seconds
    var model: String
    var project: String
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var estimated: Bool = false
    var session: String? = nil  // conversation id, when the source exposes one
}

/// A quota window read from a local file or a live endpoint.
struct QuotaWindow: Codable, Hashable, Identifiable, Sendable {
    var provider: String
    var label: String  // "5 h", "7 j"
    var usedPercent: Double
    var resetsAt: Date?
    var source: String  // "local log" | "live"
    var id: String { provider + label }
}

struct ScanOutput: Sendable {
    var entries: [Entry] = []
    var quotas: [QuotaWindow] = []
    var quotaSamples: [QuotaSample] = []
}

protocol UsageProvider: Sendable {
    var id: String { get }
    var name: String { get }
    var symbol: String { get }
    var paths: [String] { get }
    func installed() -> Bool
    func scan(cache: FileCache) -> ScanOutput
}

/// Per-file parse cache keyed by path + mtime + size, so rescans only touch changed files.
/// Thread-safe: providers scan concurrently and share one instance.
final class FileCache: @unchecked Sendable {
    struct CachedFile: Codable { var sig: String; var entries: [Entry] }
    private var store: [String: CachedFile] = [:]
    private var dirty = false
    private let url: URL
    private let lock = NSLock()

    init(url: URL = URL(fileURLWithPath: Paths.support + "/scan-cache.json")) {
        self.url = url
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode([String: CachedFile].self, from: d) {
            store = s
        }
    }

    static func signature(_ path: String) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return "\((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\(attrs?[.size] ?? 0)"
    }

    func entries(for path: String, parse: () -> [Entry]) -> [Entry] {
        let sig = Self.signature(path)
        lock.lock()
        if let c = store[path], c.sig == sig { lock.unlock(); return c.entries }
        lock.unlock()
        let parsed = parse()
        lock.lock(); store[path] = CachedFile(sig: sig, entries: parsed); dirty = true; lock.unlock()
        return parsed
    }

    /// Drops cached files under `prefix` that no longer exist on disk.
    func prune(keeping paths: Set<String>, prefix: String) {
        let root = prefix.hasSuffix("/") ? prefix : prefix + "/"
        lock.lock(); defer { lock.unlock() }
        for k in store.keys where k.hasPrefix(root) && !paths.contains(k) { store[k] = nil; dirty = true }
    }

    var isDirty: Bool { lock.lock(); defer { lock.unlock() }; return dirty }
    var count: Int { lock.lock(); defer { lock.unlock() }; return store.count }

    /// Writes the cache only when something changed; encoding happens outside the lock.
    func save() {
        lock.lock()
        guard dirty else { lock.unlock(); return }
        let snapshot = store
        dirty = false
        lock.unlock()
        guard let d = try? JSONEncoder().encode(snapshot) else { return }
        do { try d.write(to: url, options: .atomic) } catch {
            lock.lock(); dirty = true; lock.unlock()  // retry next refresh
        }
    }
}

// MARK: - helpers

func files(under dir: String, ext: String) -> [String] {
    let root = expand(dir)
    guard let en = FileManager.default.enumerator(atPath: root) else { return [] }
    var out: [String] = []
    for case let f as String in en where f.hasSuffix(ext) { out.append(root + "/" + f) }
    return out
}

func readLines(_ path: String, _ body: (Substring) -> Void) {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { return }
    forEachLine(in: data, body)
}

/// Calls `body` for every non-empty LF-separated line of `data`.
func forEachLine(in data: Data, _ body: (Substring) -> Void) {
    var start = data.startIndex
    while start < data.endIndex {
        let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
        if end > start { body(Substring(String(decoding: data[start..<end], as: UTF8.self))) }
        start = end < data.endIndex ? data.index(after: end) : end
    }
}

/// Streams the stdout of a process line by line, without holding the whole output in memory.
@discardableResult
func streamLines(_ exe: String, _ args: [String], _ body: (Substring) -> Void) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    let h = pipe.fileHandleForReading
    var pending = Data()
    while true {
        let chunk = h.availableData
        if chunk.isEmpty { break }
        pending.append(chunk)
        guard let last = pending.lastIndex(of: 0x0A) else { continue }
        forEachLine(in: pending[pending.startIndex...last], body)
        pending = Data(pending[pending.index(after: last)...])
    }
    if !pending.isEmpty { forEachLine(in: pending, body) }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

func json(_ line: Substring) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
}

func int(_ v: Any?) -> Int {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    return 0
}

/// Minimal read-only SQLite wrapper.
enum SQL {
    static func query(_ path: String, _ sql: String, _ row: (OpaquePointer) -> Void) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { return }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW { row(st) }
    }
    static func text(_ st: OpaquePointer, _ i: Int32) -> String {
        sqlite3_column_text(st, i).map { String(cString: $0) } ?? ""
    }
    static func int(_ st: OpaquePointer, _ i: Int32) -> Int { Int(sqlite3_column_int64(st, i)) }
}
