import Foundation

/// USD per million tokens.
struct Price: Codable, Equatable, Sendable {
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheWrite: Double
}

struct PriceResult: Sendable {
    var price: Price
    /// True when the exact model is unknown and a family fallback was used.
    var approximate: Bool
}

final class Pricing: @unchecked Sendable {
    static let shared = Pricing()
    /// Immutable after init.
    private var table: [String: Price] = [:]
    /// Family fallbacks for model names newer than the bundled table (from pricing-fallbacks.json).
    /// Edit `~/Library/Application Support/Ember/pricing-overrides.json` to correct any of them.
    private var families: [(match: String, ref: String)] = []
    /// Memoized lookups: the same few model names are priced thousands of times per refresh.
    private var memo: [String: PriceResult?] = [:]
    private let lock = NSLock()

    init(bundle: Bundle? = nil, overridesPath: String? = Paths.support + "/pricing-overrides.json") {
        let bundle = bundle ?? Bundle.module
        if let url = bundle.url(forResource: "pricing-fallbacks", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for pair in raw["families"] as? [[String]] ?? [] where pair.count == 2 { families.append((pair[0], pair[1])) }
            Self.load(raw["builtin"], into: &table, lowercase: false)
        }
        if let url = bundle.url(forResource: "pricing", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            Self.load(try? JSONSerialization.jsonObject(with: data), into: &table, lowercase: false)
        }
        if let overridesPath, let data = FileManager.default.contents(atPath: overridesPath) {
            Self.load(try? JSONSerialization.jsonObject(with: data), into: &table, lowercase: true)
        }
    }

    private static func load(_ raw: Any?, into table: inout [String: Price], lowercase: Bool) {
        guard let raw = raw as? [String: [Double]] else { return }
        for (k, v) in raw where v.count == 4 {
            table[lowercase ? k.lowercased() : k] = Price(input: v[0], output: v[1], cacheRead: v[2], cacheWrite: v[3])
        }
    }

    private func normalize(_ s: String) -> String {
        var m = s.lowercased()
        if let r = m.range(of: "-20[0-9]{6}$", options: .regularExpression) { m.removeSubrange(r) }
        return m.replacingOccurrences(of: "[1m]", with: "")
    }

    func lookup(_ model: String) -> PriceResult? {
        lock.lock()
        if let hit = memo[model] { lock.unlock(); return hit }
        lock.unlock()
        let r = resolve(model)
        lock.lock(); memo[model] = .some(r); lock.unlock()
        return r
    }

    private func resolve(_ model: String) -> PriceResult? {
        let m = normalize(model)
        if m.isEmpty || m == "<synthetic>" { return nil }
        let dotted = m.replacingOccurrences(of: "-", with: ".")
        let candidates = [m, "anthropic/\(m)", "openai/\(m)", "google/\(m)", "anthropic-\(m)", "openrouter/\(m)", dotted]
        for c in candidates { if let p = table[c] { return PriceResult(price: p, approximate: false) } }
        // Same name after the vendor prefix (sorted so the pick is deterministic).
        if let k = table.keys.filter({ $0.hasSuffix("/" + m) || $0.hasSuffix("--" + m) }).min() {
            return PriceResult(price: table[k]!, approximate: false)
        }
        for f in families where m.contains(f.match) {
            if let p = table[f.ref] ?? table.keys.filter({ $0.contains(f.match) }).min().flatMap({ table[$0] }) {
                return PriceResult(price: p, approximate: true)
            }
        }
        return nil
    }

    func cost(_ r: UsageRecord) -> Double {
        // Subscription / local models without a price list count as 0.
        guard let res = lookup(r.model) else { return 0 }
        let p = res.price
        return (Double(r.input) * p.input + Double(r.output) * p.output
            + Double(r.cacheRead) * p.cacheRead + Double(r.cacheWrite) * p.cacheWrite) / 1_000_000
    }

    func isApproximate(_ model: String) -> Bool { lookup(model)?.approximate ?? false }
}

enum Paths {
    /// ~/Library/Application Support/Ember, created once.
    static let support: String = {
        let p = home + "/Library/Application Support/Ember"
        try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        return p
    }()
}
