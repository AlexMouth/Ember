import Foundation

/// USD per million tokens.
struct Price: Codable, Equatable {
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheWrite: Double
}

struct PriceResult {
    var price: Price
    /// True when the exact model is unknown and a family fallback was used.
    var approximate: Bool
}

final class Pricing {
    static let shared = Pricing()
    private var table: [String: Price] = [:]

    /// Family fallbacks for model names newer than the bundled table.
    /// Edit `~/Library/Application Support/Ember/pricing-overrides.json` to correct any of them.
    private let families: [(match: String, ref: String)] = [
        ("opus", "anthropic/claude-opus-4.8"),
        ("sonnet", "anthropic/claude-sonnet-4"),
        ("haiku", "anthropic/claude-haiku-4.5"),
        ("fable", "anthropic/claude-fable-5"),
        ("gpt-5", "openai/gpt-5"),
        ("codex", "openai/gpt-5"),
        ("flash", "google/gemini-2.5-flash"),
        ("gemini", "google/gemini-2.5-pro"),
        ("kimi", "moonshotai/kimi-k2"),
    ]

    /// Public list prices (USD / M tokens) for providers missing from the bundled table.
    /// Newer model names fall back to these through `families`; they are shown as approximate.
    private let builtin: [String: Price] = [
        "openai/gpt-5": Price(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 1.25),
        "google/gemini-2.5-pro": Price(input: 1.25, output: 10, cacheRead: 0.31, cacheWrite: 1.25),
        "google/gemini-2.5-flash": Price(input: 0.30, output: 2.50, cacheRead: 0.075, cacheWrite: 0.30),
    ]

    init() {
        table = builtin
        if let url = Bundle.module.url(forResource: "pricing", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [Double]]
        {
            for (k, v) in raw where v.count == 4 {
                table[k] = Price(input: v[0], output: v[1], cacheRead: v[2], cacheWrite: v[3])
            }
        }
        let overrides = Paths.support + "/pricing-overrides.json"
        if let data = FileManager.default.contents(atPath: overrides),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [Double]]
        {
            for (k, v) in raw where v.count == 4 {
                table[k.lowercased()] = Price(input: v[0], output: v[1], cacheRead: v[2], cacheWrite: v[3])
            }
        }
    }

    private func normalize(_ s: String) -> String {
        var m = s.lowercased()
        if let r = m.range(of: "-20[0-9]{6}$", options: .regularExpression) { m.removeSubrange(r) }
        return m.replacingOccurrences(of: "[1m]", with: "")
    }

    func lookup(_ model: String) -> PriceResult? {
        let m = normalize(model)
        if m.isEmpty || m == "<synthetic>" { return nil }
        let dotted = m.replacingOccurrences(of: "-", with: ".")
        let candidates = [m, "anthropic/\(m)", "openai/\(m)", "google/\(m)", "anthropic-\(m)", "openrouter/\(m)", dotted]
        for c in candidates { if let p = table[c] { return PriceResult(price: p, approximate: false) } }
        // Same name after the vendor prefix.
        if let hit = table.first(where: { $0.key.hasSuffix("/" + m) || $0.key.hasSuffix("--" + m) }) {
            return PriceResult(price: hit.value, approximate: false)
        }
        for f in families where m.contains(f.match) {
            if let p = table[f.ref] ?? table.first(where: { $0.key.contains(f.match) })?.value {
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

    func isApproximate(_ model: String) -> Bool {
        guard let r = lookup(model) else { return false }
        return r.approximate
    }

    /// Blended rate for providers that only expose a total token count (assumes 85% in / 15% out).
    func blended(_ model: String) -> Price? {
        lookup(model)?.price
    }
}

enum Paths {
    static var support: String {
        let p = home + "/Library/Application Support/Ember"
        try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        return p
    }
}
