import Foundation

/// USD per million tokens.
struct Price: Codable, Equatable, Sendable {
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheWrite: Double
}

/// Where a price comes from, in priority order.
enum PriceSource: String, Sendable {
    /// `pricing-overrides.json` in Application Support: the user's own corrections.
    case custom
    /// `pricing.json`, bundled, generated from models.dev.
    case modelsDev
    /// `builtin` block of `pricing-fallbacks.json`, for models models.dev does not list.
    case builtin
}

struct PriceResult: Sendable {
    var price: Price
    /// True when the exact model is unknown and a family fallback was used.
    var approximate: Bool
    var source: PriceSource = .modelsDev
    /// Table entry the price was read from (e.g. "anthropic/claude-sonnet-4-5").
    var key: String = ""
}

final class Pricing: @unchecked Sendable {
    static let shared = Pricing()

    private struct Tables {
        var prices: [String: Price] = [:]
        var origin: [String: PriceSource] = [:]
        /// Family fallbacks for model names newer than the bundled table (from pricing-fallbacks.json).
        var families: [(match: String, ref: String)] = []
    }

    private let bundle: Bundle
    let overridesPath: String?
    private var tables = Tables()
    /// Memoized lookups: the same few model names are priced thousands of times per refresh.
    private var memo: [String: PriceResult?] = [:]
    private let lock = NSLock()

    init(bundle: Bundle? = nil, overridesPath: String? = Paths.support + "/pricing-overrides.json") {
        self.bundle = bundle ?? Bundle.module
        self.overridesPath = overridesPath
        tables = Self.build(bundle: self.bundle, overridesPath: overridesPath)
    }

    /// Re-reads the three files (after the user edited `pricing-overrides.json`).
    func reload() {
        let t = Self.build(bundle: bundle, overridesPath: overridesPath)
        lock.lock(); tables = t; memo.removeAll(); lock.unlock()
    }

    /// Number of models in each source, for the Settings legend.
    var counts: [PriceSource: Int] {
        lock.lock(); defer { lock.unlock() }
        return tables.origin.values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private static func build(bundle: Bundle, overridesPath: String?) -> Tables {
        var t = Tables()
        if let url = bundle.url(forResource: "pricing-fallbacks", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for pair in raw["families"] as? [[String]] ?? [] where pair.count == 2 { t.families.append((pair[0], pair[1])) }
            load(raw["builtin"], into: &t, source: .builtin)
        }
        if let url = bundle.url(forResource: "pricing", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            load(try? JSONSerialization.jsonObject(with: data), into: &t, source: .modelsDev)
        }
        if let overridesPath, let data = FileManager.default.contents(atPath: overridesPath) {
            load(try? JSONSerialization.jsonObject(with: data), into: &t, source: .custom)
        }
        return t
    }

    private static func load(_ raw: Any?, into t: inout Tables, source: PriceSource) {
        guard let raw = raw as? [String: [Double]] else { return }
        for (k, v) in raw where v.count == 4 {
            let key = source == .custom ? k.lowercased() : k
            t.prices[key] = Price(input: v[0], output: v[1], cacheRead: v[2], cacheWrite: v[3])
            t.origin[key] = source
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
        let t = tables
        lock.unlock()
        let r = resolve(model, in: t)
        lock.lock(); memo[model] = .some(r); lock.unlock()
        return r
    }

    private func resolve(_ model: String, in t: Tables) -> PriceResult? {
        let m = normalize(model)
        if m.isEmpty || m == "<synthetic>" { return nil }
        func hit(_ k: String, approximate: Bool = false) -> PriceResult {
            PriceResult(price: t.prices[k]!, approximate: approximate, source: t.origin[k] ?? .modelsDev, key: k)
        }
        let dotted = m.replacingOccurrences(of: "-", with: ".")
        let candidates = [m, "anthropic/\(m)", "openai/\(m)", "google/\(m)", "anthropic-\(m)", "openrouter/\(m)", dotted]
        for c in candidates where t.prices[c] != nil { return hit(c) }
        // Same name after the vendor prefix (sorted so the pick is deterministic).
        if let k = t.prices.keys.filter({ $0.hasSuffix("/" + m) || $0.hasSuffix("--" + m) }).min() { return hit(k) }
        for f in t.families where m.contains(f.match) {
            if let k = t.prices[f.ref] != nil ? f.ref : t.prices.keys.filter({ $0.contains(f.match) }).min() {
                return hit(k, approximate: true)
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

    /// Creates `pricing-overrides.json` with an example entry if it does not exist yet.
    @discardableResult
    func ensureOverridesFile() -> URL? {
        guard let f = overridesPath else { return nil }
        if !FileManager.default.fileExists(atPath: f) {
            try? "{\n  \"mon-modele\": [3.0, 15.0, 0.3, 3.75]\n}\n".write(toFile: f, atomically: true, encoding: .utf8)
        }
        return URL(fileURLWithPath: f)
    }
}

enum Paths {
    /// ~/Library/Application Support/Ember, created once.
    static let support: String = {
        let p = home + "/Library/Application Support/Ember"
        try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        return p
    }()
}
