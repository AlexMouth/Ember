import Foundation

/// One observation of a quota window (percent used) at a point in time.
struct QuotaSample: Codable, Hashable {
    var provider: String
    var label: String  // "5 h", "7 j", "30 j"
    var t: Double  // unix seconds
    var used: Double
    var resets: Double  // unix seconds
    var src: String

    var key: String { "\(provider)|\(label)|\(Int(t))" }
}

extension QuotaWindow {
    var windowMinutes: Int { QuotaMath.minutes(label) }

    var title: String {
        switch label {
        case "5 h": "Session 5 h"
        case "7 j": "Hebdomadaire"
        default: "Fenêtre \(label)"
        }
    }
}

enum QuotaMath {
    static func minutes(_ label: String) -> Int {
        let p = label.split(separator: " ")
        guard p.count == 2, let n = Int(p[0]) else { return 0 }
        return p[1] == "h" ? n * 60 : n * 1440
    }
    static func label(minutes m: Int) -> String { m >= 1440 ? "\(m / 1440) j" : "\(m / 60) h" }
}

/// Derived numbers for one quota window: pace, margin and projection.
struct QuotaInfo {
    let q: QuotaWindow
    let samples: [QuotaSample]
    let now = Date()

    var end: Date { q.resetsAt ?? now }
    var start: Date { end.addingTimeInterval(-Double(q.windowMinutes) * 60) }
    var remaining: Double { max(0, 100 - q.usedPercent) }
    var elapsed: Double {
        let span = end.timeIntervalSince(start)
        return span > 0 ? min(1, max(0, now.timeIntervalSince(start) / span)) : 0
    }
    var expectedRemaining: Double { 100 * (1 - elapsed) }
    /// Points of quota left beyond an even burn down to the reset.
    var ahead: Double { remaining - expectedRemaining }
    /// Remaining % at reset if the burn rate so far continues.
    var projected: Double? { elapsed > 0.02 ? 100 - q.usedPercent / elapsed : nil }
    var willRunOut: Bool { (projected ?? 1) < 0 }

    func pace(at d: Date) -> Double {
        let span = end.timeIntervalSince(start)
        return span > 0 ? 100 * (1 - d.timeIntervalSince(start) / span) : 0
    }

    /// Remaining-% series for this window instance, starting at 100 % and ending now.
    var series: [(Date, Double)] {
        let s = start.timeIntervalSince1970, e = end.timeIntervalSince1970
        var pts: [(Date, Double)] = [(start, 100)]
        for x in samples.sorted(by: { $0.t < $1.t }) where x.t >= s && x.t <= e && x.t <= now.timeIntervalSince1970 {
            pts.append((Date(timeIntervalSince1970: x.t), max(0, 100 - x.used)))
        }
        pts.append((now, remaining))
        return pts
    }
}

enum QuotaDisk {
    static var url: URL { URL(fileURLWithPath: Paths.support + "/quota-history.json") }
    static func load() -> [QuotaSample] {
        guard let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode([QuotaSample].self, from: d) else { return [] }
        return s
    }
    static func save(_ s: [QuotaSample]) {
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: url, options: .atomic) }
    }
}
