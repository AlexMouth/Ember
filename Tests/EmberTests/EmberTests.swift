import CryptoKit
import Foundation
import Testing

@testable import Ember

@Suite struct PricingTests {
    @Test func knownModelHasPrice() {
        let r = UsageRecord(provider: "claude", model: "claude-sonnet-4-5", project: "", day: "2026-01-01",
                            input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0)
        #expect(Pricing.shared.cost(r) > 0)
    }

    @Test func costScalesWithTokens() {
        func cost(_ n: Int) -> Double {
            Pricing.shared.cost(UsageRecord(provider: "claude", model: "claude-sonnet-4-5", project: "", day: "",
                                            input: n, output: n, cacheRead: n, cacheWrite: n))
        }
        #expect(abs(cost(2_000) - 2 * cost(1_000)) < 1e-9)
    }

    @Test func dateSuffixIsIgnored() {
        #expect(Pricing.shared.lookup("claude-sonnet-4-5-20250929") != nil)
    }

    @Test func unknownModelIsFree() {
        let r = UsageRecord(provider: "x", model: "totally-unknown-model", project: "", day: "", input: 5_000, output: 5_000, cacheRead: 0, cacheWrite: 0)
        #expect(Pricing.shared.cost(r) == 0)
        #expect(Pricing.shared.lookup("<synthetic>") == nil)
    }
}

@Suite struct QuotaTests {
    private func info(used: Double, hoursElapsed: Double, window: String = "5 h") -> QuotaInfo {
        let mins = Double(QuotaMath.minutes(window))
        let reset = Date().addingTimeInterval(mins * 60 - hoursElapsed * 3600)
        return QuotaInfo(q: QuotaWindow(provider: "claude", label: window, usedPercent: used, resetsAt: reset, source: "live"), samples: [])
    }

    @Test func labelMinutes() {
        #expect(QuotaMath.minutes("5 h") == 300)
        #expect(QuotaMath.minutes("7 j") == 10_080)
        #expect(QuotaMath.label(minutes: 300) == "5 h")
    }

    @Test func evenBurnIsOnPace() {
        let i = info(used: 50, hoursElapsed: 2.5)
        #expect(abs(i.ahead) < 1)
        #expect(!i.willRunOut)
    }

    @Test func fastBurnRunsOut() {
        let i = info(used: 80, hoursElapsed: 2)
        #expect(i.willRunOut)
        #expect((i.projected ?? 0) < 0)
    }

    @Test func slowBurnIsAhead() {
        #expect(info(used: 10, hoursElapsed: 3).ahead > 0)
    }
}

@Suite struct ParsingTests {
    @Test func claudeLogDedupesStreamedMessages() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ember-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func line(_ out: Int) -> String {
            #"{"type":"assistant","timestamp":"2026-05-01T10:00:00.000Z","sessionId":"s1","cwd":"/Users/me/work/demo","requestId":"r1","message":{"id":"m1","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":\#(out),"cache_read_input_tokens":5,"cache_creation_input_tokens":2}}}"#
        }
        let user = #"{"type":"user","timestamp":"2026-05-01T10:00:01.000Z"}"#
        let f = dir.appendingPathComponent("a.jsonl")
        try [line(3), user, line(40)].joined(separator: "\n").write(to: f, atomically: true, encoding: .utf8)
        let es = ClaudeCode().parse(f.path)
        #expect(es.count == 1)
        #expect(es[0].output == 40)
        #expect(es[0].session == "s1")
        #expect(es[0].project == "demo")
    }

    @Test func latestSessionPicksNewestAndSums() {
        func e(_ ts: Double, _ s: String) -> Entry {
            Entry(key: "\(ts)\(s)", ts: ts, model: "claude-sonnet-4-5", project: "p", input: 100, output: 100, cacheRead: 0, cacheWrite: 0, session: s)
        }
        let s = SessionInfo.latest(from: [e(10, "a"), e(20, "b"), e(30, "b"), e(5, "a")])
        #expect(s?.messages == 2)
        #expect(s?.tokens == 400)
        #expect(s?.duration == 10)
        #expect(SessionInfo.latest(from: []) == nil)
    }

    @Test func versionComparison() {
        #expect(Updater.newer("0.4.0", than: "0.3.1"))
        #expect(!Updater.newer("0.3.1", than: "0.3.1"))
        #expect(Updater.newer("1.0", than: "0.9.9"))
    }
}

// MARK: - Helpers

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ember-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func lines(_ s: String) -> [Substring] { s.split(separator: "\n") }

// MARK: - Updater

@Suite struct UpdaterTests {
    @Test func prereleaseOrdering() {
        #expect(Updater.newer("1.0", than: "1.0-beta"))
        #expect(!Updater.newer("1.0-beta", than: "1.0"))
        #expect(Updater.newer("1.0-beta.2", than: "1.0-beta.1"))
        #expect(Updater.newer("1.0-beta.10", than: "1.0-beta.9"))   // numeric, not lexical
        #expect(Updater.newer("1.0-rc", than: "1.0-beta"))
        #expect(Updater.newer("1.0-alpha.1", than: "1.0-alpha"))   // more identifiers wins
        #expect(Updater.newer("1.0-alpha", than: "1.0-1"))         // text sorts after numbers
    }

    @Test func prefixesAndBuildMetadata() {
        #expect(!Updater.newer("v0.4.2", than: "0.4.2"))
        #expect(Updater.newer("v0.4.3", than: "0.4.2"))
        #expect(!Updater.newer("0.4.2+42", than: "0.4.2+7"))
        #expect(!Updater.newer("1.0.0", than: "1"))
        #expect(Updater.newer("0.10.0", than: "0.9.9"))
    }

    @Test func menuBarAlertLevel() {
        #expect(AppDelegate.alertLevel(used: nil) == 0)
        #expect(AppDelegate.alertLevel(used: 79.9) == 0)
        #expect(AppDelegate.alertLevel(used: 80) == 1)
        #expect(AppDelegate.alertLevel(used: 94.9) == 1)
        #expect(AppDelegate.alertLevel(used: 95) == 2)
        #expect(AppDelegate.alertLevel(used: 120) == 2)
    }

    @Test func signatureVerification() throws {
        let key = Curve25519.Signing.PrivateKey()
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        let data = Data("Ember.zip contents".utf8)
        let sig = try key.signature(for: data).base64EncodedString()
        #expect(Updater.isSigned(data, signature: sig, key: pub))
        #expect(Updater.isSigned(data, signature: sig + "\n", key: pub))           // trailing newline tolerated
        #expect(!Updater.isSigned(Data("tampered".utf8), signature: sig, key: pub))   // modified archive
        let other = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        #expect(!Updater.isSigned(data, signature: sig, key: other))                 // signed by someone else
        #expect(!Updater.isSigned(data, signature: "pas du base64", key: pub))
        #expect(!Updater.isSigned(data, signature: sig))                             // not the release key
    }
}

// MARK: - CSV

@Suite struct CSVTests {
    @Test func plainFieldsUntouched() {
        #expect(Store.csvField("claude-sonnet-4-5") == "claude-sonnet-4-5")
        #expect(Store.csvField("") == "")
        #expect(Store.csvField("-12.5") == "-12.5")   // negative numbers stay numbers
    }

    @Test func quotingRules() {
        #expect(Store.csvField("a,b") == "\"a,b\"")
        #expect(Store.csvField("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(Store.csvField("two\nlines") == "\"two\nlines\"")
        #expect(Store.csvField("cr\rhere") == "\"cr\rhere\"")
    }

    @Test func formulaInjectionNeutralised() {
        #expect(Store.csvField("=SUM(A1)") == "'=SUM(A1)")
        #expect(Store.csvField("+cmd") == "'+cmd")
        #expect(Store.csvField("@x") == "'@x")
        #expect(Store.csvField("=a,b") == "\"'=a,b\"")
    }

    @Test func rowUsesCRLF() {
        #expect(Store.csvRow(["a", "b,c", "1"]) == "a,\"b,c\",1\r\n")
    }
}

// MARK: - Pricing (isolated instances)

@Suite struct PricingFallbackTests {
    private func pricing(overrides: String?) throws -> (Pricing, URL) {
        let dir = try tempDir()
        let f = dir.appendingPathComponent("overrides.json")
        if let overrides { try Data(overrides.utf8).write(to: f) }
        return (Pricing(overridesPath: f.path), dir)
    }

    private func cost(_ p: Pricing, _ model: String, input: Int = 1_000_000, output: Int = 0) -> Double {
        p.cost(UsageRecord(provider: "t", model: model, project: "", day: "", input: input, output: output))
    }

    @Test func overrideWinsAndIsCaseInsensitive() throws {
        let (p, dir) = try pricing(overrides: #"{"My-Custom-Model": [2, 8, 0.5, 0], "claude-sonnet-4-5": [100, 0, 0, 0]}"#)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(abs(cost(p, "my-custom-model") - 2) < 1e-9)
        #expect(abs(cost(p, "my-custom-model", input: 0, output: 1_000_000) - 8) < 1e-9)
        #expect(p.isApproximate("my-custom-model") == false)
        #expect(abs(cost(p, "claude-sonnet-4-5") - 100) < 1e-9)
    }

    @Test func malformedOverridesAreIgnored() throws {
        let (p, dir) = try pricing(overrides: #"{"bad": [1, 2], "worse": "x"}"#)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(p.lookup("bad") == nil)
        #expect(cost(p, "claude-sonnet-4-5") > 0)   // bundled table still loads
    }

    @Test func familyFallbackIsApproximate() throws {
        let (p, dir) = try pricing(overrides: nil)
        defer { try? FileManager.default.removeItem(at: dir) }
        let future = "claude-sonnet-99-preview"
        #expect(cost(p, future) > 0)
        #expect(p.isApproximate(future))
        #expect(!p.isApproximate("claude-sonnet-4-5"))
    }

    @Test func lookupsAreStable() throws {
        let (p, dir) = try pricing(overrides: nil)
        defer { try? FileManager.default.removeItem(at: dir) }
        for m in ["gpt-5", "claude-opus-4-1-20250805", "gemini-2.5-pro", "nope-model"] {
            let a = p.lookup(m), b = p.lookup(m), fresh = Pricing(overridesPath: dir.appendingPathComponent("none").path).lookup(m)
            #expect(a?.price == b?.price && a?.approximate == b?.approximate)
            #expect(a?.price == fresh?.price)   // deterministic across instances
        }
    }
}

// MARK: - Parser fixtures

@Suite struct ParserFixtureTests {
    @Test func claudeLinesSkipNoiseAndSynthetic() {
        let ok = #"{"type":"assistant","timestamp":"2026-05-01T10:00:00Z","cwd":"/a/b/proj","requestId":"r","message":{"id":"m","model":"claude-opus-4-1","usage":{"input_tokens":1,"output_tokens":2}}}"#
        let synthetic = #"{"type":"assistant","timestamp":"2026-05-01T10:00:00Z","message":{"id":"s","model":"<synthetic>","usage":{"input_tokens":1}}}"#
        let broken = #"{"type":"assistant","usage" "#
        let es = ClaudeCode.parse(lines: lines([broken, synthetic, ok, "", "not json"].joined(separator: "\n")))
        #expect(es.count == 1)
        #expect(es.first?.model == "claude-opus-4-1")
        #expect(es.first?.project == "proj")
    }

    @Test func codexTotalsAndQuota() {
        let path = "/x/rollout-2026-05-01T10-00-00-0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b.jsonl.zst"
        let fixture = [
            #"{"timestamp":"2026-05-01T10:00:00Z","type":"session_meta","payload":{"cwd":"/w/codexproj"}}"#,
            #"{"timestamp":"2026-05-01T10:00:01Z","type":"turn_context","payload":{"model":"gpt-5-codex"}}"#,
            #"{"timestamp":"2026-05-01T10:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":7}}}}"#,
            #"{"timestamp":"2026-05-01T10:05:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":100,"output_tokens":20}},"rate_limits":{"primary":{"used_percent":12,"window_minutes":300},"secondary":{"used_percent":3.5,"window_minutes":10080}}}}"#,
        ].joined(separator: "\n")
        let es = Codex.parse(lines: lines(fixture), path: path)
        let usage = es.first { $0.key.hasPrefix("codex|") }
        #expect(usage?.key == "codex|0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b")
        #expect(usage?.model == "gpt-5-codex")
        #expect(usage?.project == "codexproj")
        #expect(usage?.input == 200 && usage?.cacheRead == 100 && usage?.output == 20)   // last cumulative total wins
        #expect(es.contains { $0.key.hasPrefix("quota|") })   // integer used_percent accepted
        #expect(Codex.parse(lines: lines(#"{"type":"session_meta","payload":{}}"#), path: path).isEmpty)
    }

    @Test func geminiKeysAreStableWithoutIds() {
        let json = #"""
        {"sessionId":"sess-1","messages":[
          {"type":"user","timestamp":"2026-05-01T10:00:00Z"},
          {"type":"gemini","timestamp":"2026-05-01T10:00:01Z","model":"gemini-2.5-pro","tokens":{"input":50,"cached":10,"output":5,"thoughts":3,"tool":1}},
          {"type":"gemini","id":"abc","timestamp":"2026-05-01T10:00:02Z","tokens":{"input":1,"output":1}}
        ]}
        """#
        let path = "/u/.gemini/tmp/myproj/chats/session-1.json"
        let a = GeminiCLI.parse(data: Data(json.utf8), path: path)
        let b = GeminiCLI.parse(data: Data(json.utf8), path: path)
        #expect(a.count == 2)
        #expect(a.map(\.key) == b.map(\.key))
        #expect(a[0].key == "gemini|sess-1#1@2026-05-01T10:00:01Z")
        #expect(a[1].key == "gemini|abc")
        #expect(a[0].input == 40 && a[0].cacheRead == 10 && a[0].output == 9)
        #expect(a[0].project == "myproj")
        #expect(GeminiCLI.parse(data: Data("[]".utf8), path: path).isEmpty)
    }

    @Test func kiroTurnCounting() {
        #expect(KiroCLI.turns(#"{"history":[{"user":{"content":"a"},"assistant":{}},{"user":{"content":"b"},"assistant":{}}]}"#) == 2)
        #expect(KiroCLI.turns(#"{"history":[[{"content":"hi"},{"x":1}],[{"y":2}]]}"#) == 1)
        #expect(KiroCLI.turns(#"{"history":[]}"#) == 0)
        #expect(KiroCLI.turns(#"not json "user":{ and "user":{"#) == 2)   // text fallback
        #expect(KiroCLI.turns("") == 0)
    }

    @Test func lineSplitting() {
        var got: [String] = []
        forEachLine(in: Data("a\n\nb\nlast".utf8)) { got.append(String($0)) }
        #expect(got == ["a", "b", "last"])
    }

    @Test func streamLinesReadsProcessOutput() {
        var got: [String] = []
        #expect(streamLines("/usr/bin/printf", ["one\\ntwo\\n"]) { got.append(String($0)) })
        #expect(got == ["one", "two"])
        #expect(!streamLines("/usr/bin/false", []) { _ in })
    }
}

// MARK: - FileCache

@Suite struct FileCacheTests {
    private func entry(_ k: String) -> Entry {
        Entry(key: k, ts: 0, model: "m", project: "p", input: 1, output: 1, cacheRead: 0, cacheWrite: 0)
    }

    @Test func hitsMissesPruneAndSave() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = dir.appendingPathComponent("logs"), cacheURL = dir.appendingPathComponent("cache.json")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let a = data.appendingPathComponent("a.jsonl").path, b = data.appendingPathComponent("b.jsonl").path
        try "x".write(toFile: a, atomically: true, encoding: .utf8)
        try "y".write(toFile: b, atomically: true, encoding: .utf8)

        let c = FileCache(url: cacheURL)
        #expect(!c.isDirty)
        var parses = 0
        _ = c.entries(for: a) { parses += 1; return [entry("a")] }
        _ = c.entries(for: b) { parses += 1; return [entry("b")] }
        _ = c.entries(for: a) { parses += 1; return [] }
        #expect(parses == 2)            // second read of `a` is a hit
        #expect(c.isDirty)
        c.save()
        #expect(!c.isDirty)
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))

        // Nothing changed: save must not rewrite the file.
        try FileManager.default.removeItem(at: cacheURL)
        c.save()
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path))

        // Reload from disk, then prune a file that disappeared.
        c.prune(keeping: [a, b], prefix: data.path)
        #expect(!c.isDirty)
        c.prune(keeping: [a], prefix: data.path + "/")
        #expect(c.isDirty && c.count == 1)
        c.save()
        let reloaded = FileCache(url: cacheURL)
        #expect(reloaded.count == 1)
        var reparsed = false
        #expect(reloaded.entries(for: a) { reparsed = true; return [] }.first?.key == "a")
        #expect(!reparsed)

        // A modified file is parsed again.
        try "changed!".write(toFile: a, atomically: true, encoding: .utf8)
        #expect(reloaded.entries(for: a) { [entry("a2")] }.first?.key == "a2")
    }

    @Test func pruneIgnoresSiblingPrefixes() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let c = FileCache(url: dir.appendingPathComponent("c.json"))
        let other = dir.appendingPathComponent("logs-other/x.jsonl").path
        _ = c.entries(for: other) { [entry("o")] }
        c.save()
        c.prune(keeping: [], prefix: dir.appendingPathComponent("logs").path)
        #expect(c.count == 1 && !c.isDirty)   // "/logs" must not match "/logs-other"
    }
}

// MARK: - Aggregates

@Suite struct BreakdownTests {
    @Test func groupsSumsAndSorts() {
        func r(_ m: String, _ p: String, _ n: Int) -> UsageRecord {
            UsageRecord(provider: "x", model: m, project: p, day: "2026-05-01", input: n)
        }
        let rs = [r("a", "p1", 10), r("b", "p1", 30), r("a", "p2", 25), r("c", "p3", 5), r("d", "p3", 5)]
        let byModel = Store.breakdown(rs, by: \.model) { Double($0.input) }
        #expect(byModel.map(\.name) == ["a", "b", "c", "d"])   // ties broken by name
        #expect(byModel[0].cost == 35 && byModel[0].tokens == 35)
        let byProject = Store.breakdown(rs, by: \.project) { Double($0.input) }
        #expect(byProject.map(\.name) == ["p1", "p2", "p3"])
        #expect(Store.breakdown([], by: \.model) { _ in 1 }.isEmpty)
    }
}
