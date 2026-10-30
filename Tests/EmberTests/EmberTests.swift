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
