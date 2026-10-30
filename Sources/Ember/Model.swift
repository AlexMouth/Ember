import Foundation

/// One aggregated bucket: a provider + model + project on a given local day.
struct UsageRecord: Codable, Hashable, Identifiable {
    var provider: String
    var model: String
    var project: String
    var day: String  // yyyy-MM-dd, local time
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheWrite: Int = 0
    var messages: Int = 0
    /// True when the token split is unknown and the cost uses a blended rate.
    var estimated: Bool = false
    var id: String { "\(provider)|\(model)|\(project)|\(day)" }
    var totalTokens: Int { input + output + cacheRead + cacheWrite }

    mutating func add(_ o: UsageRecord) {
        input += o.input; output += o.output
        cacheRead += o.cacheRead; cacheWrite += o.cacheWrite
        messages += o.messages
        estimated = estimated || o.estimated
    }
}

/// An hourly event, kept so rolling windows (5 h) can be computed offline.
struct HourBucket: Codable, Hashable {
    var provider: String
    var hour: Int  // unix seconds / 3600
    var tokens: Int
    var cost: Double
}

enum ProviderStatus: Equatable {
    case active(records: Int)
    case detectedNoData(reason: String)
    case notInstalled
}

struct ProviderInfo: Identifiable, Equatable {
    var id: String
    var name: String
    var symbol: String
    var status: ProviderStatus
    var paths: [String]  // what the app reads, shown in the privacy pane
}

enum Day {
    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    static func string(_ d: Date) -> String { fmt.string(from: d) }
    static func date(_ s: String) -> Date? { fmt.date(from: s) }
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoPlain = ISO8601DateFormatter()
    static func parse(_ s: String) -> Date? { iso.date(from: s) ?? isoPlain.date(from: s) }
}

let home = FileManager.default.homeDirectoryForCurrentUser.path

func expand(_ p: String) -> String {
    p.hasPrefix("~") ? home + p.dropFirst() : p
}

func exists(_ p: String) -> Bool { FileManager.default.fileExists(atPath: expand(p)) }

func shortProject(_ cwd: String) -> String {
    if cwd.isEmpty { return "—" }
    if cwd == home { return "~" }
    return (cwd as NSString).lastPathComponent
}

/// The Claude Code conversation that produced the most recent activity.
struct SessionInfo: Equatable {
    var project: String
    var model: String
    var start: Date
    var last: Date
    var messages: Int
    var tokens: Int
    var cost: Double

    /// Live while the last message is under ten minutes old.
    var isLive: Bool { Date().timeIntervalSince(last) < 600 }
    var duration: TimeInterval { last.timeIntervalSince(start) }

    static func latest(from entries: [Entry]) -> SessionInfo? {
        guard let newest = entries.filter({ $0.session != nil }).max(by: { $0.ts < $1.ts }), let id = newest.session
        else { return nil }
        let mine = entries.filter { $0.session == id }
        let cost = mine.reduce(0.0) {
            $0 + Pricing.shared.cost(UsageRecord(provider: "claude", model: $1.model, project: "", day: "", input: $1.input,
                                                 output: $1.output, cacheRead: $1.cacheRead, cacheWrite: $1.cacheWrite))
        }
        return SessionInfo(
            project: newest.project, model: newest.model,
            start: Date(timeIntervalSince1970: mine.map(\.ts).min() ?? newest.ts),
            last: Date(timeIntervalSince1970: newest.ts), messages: mine.count,
            tokens: mine.reduce(0) { $0 + $1.input + $1.output + $1.cacheRead + $1.cacheWrite }, cost: cost)
    }
}
