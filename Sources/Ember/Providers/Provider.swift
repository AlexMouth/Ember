import Foundation
import SQLite3

/// A single usage event, before aggregation.
struct Entry: Codable, Hashable {
    var key: String  // dedupe key
    var ts: Double  // unix seconds
    var model: String
    var project: String
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var estimated: Bool = false
}

/// A quota window read from a local file or a live endpoint.
struct QuotaWindow: Codable, Hashable, Identifiable {
    var provider: String
    var label: String  // "5 h", "7 j"
    var usedPercent: Double
    var resetsAt: Date?
    var source: String  // "local log" | "live"
    var id: String { provider + label }
}

struct ScanOutput {
    var entries: [Entry] = []
    var quotas: [QuotaWindow] = []
    var quotaSamples: [QuotaSample] = []
}

protocol UsageProvider {
    var id: String { get }
    var name: String { get }
    var symbol: String { get }
    var paths: [String] { get }
    func installed() -> Bool
    func scan(cache: FileCache) -> ScanOutput
}

/// Per-file parse cache keyed by path + mtime + size, so rescans only touch changed files.
final class FileCache {
    private var store: [String: CachedFile] = [:]
    private let url = URL(fileURLWithPath: Paths.support + "/scan-cache.json")
    struct CachedFile: Codable { var sig: String; var entries: [Entry] }
    private let lock = NSLock()

    init() {
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode([String: CachedFile].self, from: d) {
            store = s
        }
    }

    func entries(for path: String, parse: () -> [Entry]) -> [Entry] {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let sig = "\((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\(attrs?[.size] ?? 0)"
        lock.lock()
        if let c = store[path], c.sig == sig { lock.unlock(); return c.entries }
        lock.unlock()
        let parsed = parse()
        lock.lock(); store[path] = CachedFile(sig: sig, entries: parsed); lock.unlock()
        return parsed
    }

    func prune(keeping paths: Set<String>, prefix: String) {
        lock.lock(); defer { lock.unlock() }
        for k in store.keys where k.hasPrefix(prefix) && !paths.contains(k) { store[k] = nil }
    }

    func save() {
        lock.lock(); defer { lock.unlock() }
        if let d = try? JSONEncoder().encode(store) { try? d.write(to: url, options: .atomic) }
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
    guard let data = FileManager.default.contents(atPath: path),
        let text = String(data: data, encoding: .utf8)
    else { return }
    text.split(separator: "\n", omittingEmptySubsequences: true).forEach(body)
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
