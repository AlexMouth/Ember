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
