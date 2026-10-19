import Foundation
import SwiftUI
import UserNotifications

enum Range: String, CaseIterable, Identifiable {
    case today = "Aujourd'hui", week = "7 jours", month = "30 jours", all = "Tout"
    var id: String { rawValue }
    var days: Int? {
        switch self { case .today: 1; case .week: 7; case .month: 30; case .all: nil }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var records: [UsageRecord] = []
    @Published var hours: [HourBucket] = []
    @Published var quotas: [QuotaWindow] = []
    @Published var providers: [ProviderInfo] = []
    @Published var lastRefresh: Date?
    @Published var refreshing = false
    @Published var liveStatus = ""

    @AppStorage("monthlyBudget") var monthlyBudget: Double = 0
    @AppStorage("liveClaude") var liveClaude = true
    @AppStorage("refreshMinutes") var refreshMinutes = 2
    @AppStorage("lastAlertLevel") private var lastAlertLevel = ""
    @AppStorage("menuMode") var menuMode = "auto"          // auto | quota | cost | icon
    @AppStorage("menuProvider") var menuProvider = "claude"
    @AppStorage("quotaAlert") var quotaAlert = 0            // 0 = off, else % remaining threshold
    @AppStorage("alertedQuotas") private var alertedQuotas = ""

    private let cache = FileCache()
    private var timer: Timer?
    private var lastLive = Date.distantPast
    private var index: [String: QuotaSample] = [:]
    private var claudeCosts: [(ts: Double, cost: Double)] = []

    init() {
        providers = Discovery.providers().map {
            ProviderInfo(id: $0.id, name: $0.name, symbol: $0.symbol,
                         status: $0.installed() ? .detectedNoData(reason: "Analyse…") : .notInstalled, paths: $0.paths)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.lastRefresh ?? .distantPast) > 20 else { return }
            self.refresh()
        }
        for x in QuotaDisk.load() { index[x.key] = x }
        rebuildQuotas()
        refresh()
        schedule()
    }

    func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(max(1, refreshMinutes)) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: refresh

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let cache = self.cache
        Task.detached(priority: .utility) {
            var outputs: [(UsageProvider, ScanOutput)] = []
            let lock = NSLock()
            let all = Discovery.providers()
            DispatchQueue.concurrentPerform(iterations: all.count) { i in
                let p = all[i]
                guard p.installed() else { return }
                let o = p.scan(cache: cache)
                lock.lock(); outputs.append((p, o)); lock.unlock()
            }
            cache.save()
            let (recs, hrs) = Store.aggregate(outputs)
            let samples = outputs.flatMap { $0.1.quotaSamples }
            let costs: [(ts: Double, cost: Double)] = outputs.filter { $0.0.id == "claude" }.flatMap { $0.1.entries }
                .map { e in (e.ts, Pricing.shared.cost(UsageRecord(provider: "claude", model: e.model, project: "", day: "",
                    input: e.input, output: e.output, cacheRead: e.cacheRead, cacheWrite: e.cacheWrite))) }
                .sorted { $0.0 < $1.0 }
            let infos: [ProviderInfo] = all.map { p in
                let n = recs.filter { $0.provider == p.id }.count
                let status: ProviderStatus
                if !p.installed() { status = .notInstalled }
                else if let d = p as? Detected { status = .detectedNoData(reason: d.reason) }
                else if n > 0 { status = .active(records: n) }
                else { status = .detectedNoData(reason: "Aucune donnée d'usage trouvée.") }
                return ProviderInfo(id: p.id, name: p.name, symbol: p.symbol, status: status, paths: p.paths)
            }
            await MainActor.run {
                self.records = recs; self.hours = hrs; self.providers = infos; self.claudeCosts = costs
                self.merge(samples)
                self.lastRefresh = Date(); self.refreshing = false
                self.checkBudget()
                self.checkQuotas()
            }
            await self.refreshLive()
        }
    }

    nonisolated static func aggregate(_ outputs: [(UsageProvider, ScanOutput)]) -> ([UsageRecord], [HourBucket]) {
        var recs: [String: UsageRecord] = [:]
        var hrs: [String: HourBucket] = [:]
        for (p, o) in outputs {
            for e in o.entries {
                let date = Date(timeIntervalSince1970: e.ts)
                var r = UsageRecord(provider: p.id, model: e.model, project: e.project, day: Day.string(date),
                                    input: e.input, output: e.output, cacheRead: e.cacheRead, cacheWrite: e.cacheWrite,
                                    messages: 1, estimated: e.estimated)
                if var old = recs[r.id] { old.add(r); r = old }
                recs[r.id] = r
                let h = Int(e.ts / 3600)
                let k = "\(p.id)|\(h)"
                var b = hrs[k] ?? HourBucket(provider: p.id, hour: h, tokens: 0, cost: 0)
                b.tokens += e.input + e.output + e.cacheRead + e.cacheWrite
                b.cost += Pricing.shared.cost(UsageRecord(provider: p.id, model: e.model, project: "", day: "",
                                                          input: e.input, output: e.output, cacheRead: e.cacheRead, cacheWrite: e.cacheWrite))
                hrs[k] = b
            }
        }
        return (Array(recs.values), Array(hrs.values))
    }

    // MARK: quota history

    func merge(_ new: [QuotaSample]) {
        var changed = false
        for x in new where index[x.key] == nil { index[x.key] = x; changed = true }
        if changed {
            let cutoff = Date().timeIntervalSince1970 - 35 * 86400
            index = index.filter { $0.value.t >= cutoff }
            let all = Array(index.values)
            Task.detached(priority: .utility) { QuotaDisk.save(all) }
        }
        rebuildQuotas()
    }

    /// Current windows: the newest reading of each series whose window has not yet reset.
    func rebuildQuotas() {
        let now = Date().timeIntervalSince1970
        var latest: [String: QuotaSample] = [:]
        for x in index.values where x.resets > now {
            let k = x.provider + "|" + x.label
            if latest[k] == nil || x.t > latest[k]!.t { latest[k] = x }
        }
        quotas = latest.values.map {
            QuotaWindow(provider: $0.provider, label: $0.label, usedPercent: $0.used,
                        resetsAt: Date(timeIntervalSince1970: $0.resets), source: $0.src)
        }.sorted { ($0.provider, $0.windowMinutes) < ($1.provider, $1.windowMinutes) }
    }

    func info(_ q: QuotaWindow) -> QuotaInfo {
        let r = q.resetsAt?.timeIntervalSince1970 ?? 0
        let s = index.values.filter { $0.provider == q.provider && $0.label == q.label && abs($0.resets - r) < 600 }
        return QuotaInfo(q: q, samples: s)
    }

    func quotas(for provider: String) -> [QuotaWindow] { quotas.filter { $0.provider == provider } }

    // MARK: queries

    func cost(_ r: UsageRecord) -> Double { Pricing.shared.cost(r) }

    func filtered(_ range: Range, provider: String? = nil) -> [UsageRecord] {
        let cutoff = range.days.map { Day.string(Calendar.current.date(byAdding: .day, value: -($0 - 1), to: Date())!) }
        return records.filter { r in
            (cutoff == nil || r.day >= cutoff!) && (provider == nil || r.provider == provider)
        }
    }

    func totalCost(_ rs: [UsageRecord]) -> Double { rs.reduce(0) { $0 + cost($1) } }
    func totalTokens(_ rs: [UsageRecord]) -> Int { rs.reduce(0) { $0 + $1.totalTokens } }

    var monthRecords: [UsageRecord] {
        let prefix = String(Day.string(Date()).prefix(7))
        return records.filter { $0.day.hasPrefix(prefix) }
    }
    var monthCost: Double { totalCost(monthRecords) }
    var todayCost: Double { totalCost(records.filter { $0.day == Day.string(Date()) }) }

    /// Linear projection of this month's spend from the average of days elapsed.
    var monthProjection: Double {
        let cal = Calendar.current
        let day = Double(cal.component(.day, from: Date()))
        let n = Double(cal.range(of: .day, in: .month, for: Date())?.count ?? 30)
        return monthCost / max(day, 1) * n
    }

    /// Spend over the trailing N hours, from hourly buckets (works offline, no account needed).
    func rolling(hours n: Int, provider: String? = nil) -> (tokens: Int, cost: Double) {
        let now = Int(Date().timeIntervalSince1970 / 3600)
        let hs = hours.filter { $0.hour > now - n && (provider == nil || $0.provider == provider) }
        return (hs.reduce(0) { $0 + $1.tokens }, hs.reduce(0) { $0 + $1.cost })
    }

    /// $/hour over the last 3 active-hour window.
    var burnRate: Double { rolling(hours: 3).cost / 3 }

    func providerName(_ id: String) -> String { providers.first { $0.id == id }?.name ?? id }

    // MARK: live Claude quota (opt-in, read-only: never refreshes or rewrites the token)

    nonisolated func refreshLive() async {
        let on = await MainActor.run { self.liveClaude }
        let last = await MainActor.run { self.lastLive }
        guard on, Date().timeIntervalSince(last) > 300 else { return }
        let result = await LiveClaude.fetch()
        await MainActor.run {
            self.lastLive = Date()
            switch result {
            case .success(let q):
                self.liveStatus = "OK"
                let now = Date().timeIntervalSince1970
                self.merge(q.compactMap { w in
                    w.resetsAt.map { QuotaSample(provider: w.provider, label: w.label, t: now, used: w.usedPercent,
                                                 resets: $0.timeIntervalSince1970, src: "live") }
                })
                self.backfillClaude()
            case .failure(let e): self.liveStatus = e.message
            }
        }
    }

    /// The quota API only reports the current level. To draw the curve of a window that began before
    /// Ember was running, the level is spread over the Claude Code spend recorded since the window opened
    /// (cumulative cost scaled so it ends on the real reading). Runs once per window, before the first real reading.
    func backfillClaude() {
        guard !claudeCosts.isEmpty else { return }
        var added: [QuotaSample] = []
        for label in ["5 h", "7 j"] {
            let real = index.values.filter { $0.provider == "claude" && $0.label == label && $0.src != "reconstitué" && $0.resets > Date().timeIntervalSince1970 }
            guard let first = real.min(by: { $0.t < $1.t }), let last = real.max(by: { $0.t < $1.t }) else { continue }
            let win = Double(QuotaMath.minutes(label)) * 60, start = first.resets - win
            guard !index.values.contains(where: { $0.src == "reconstitué" && $0.label == label && $0.resets == first.resets }) else { continue }
            let inWin = claudeCosts.filter { $0.ts >= start && $0.ts <= last.t }
            let total = inWin.reduce(0) { $0 + $1.cost }
            guard total > 0, last.used > 0 else { continue }
            let step: Double = label == "5 h" ? 300 : 3600
            var t = (start / step).rounded(.up) * step, cum = 0.0, i = 0
            while t < first.t {
                while i < inWin.count, inWin[i].ts <= t { cum += inWin[i].cost; i += 1 }
                added.append(QuotaSample(provider: "claude", label: label, t: t, used: min(100, last.used * cum / total),
                                         resets: first.resets, src: "reconstitué"))
                t += step
            }
        }
        if !added.isEmpty { merge(added) }
    }

    // MARK: budget alert

    private func checkBudget() {
        guard monthlyBudget > 0 else { return }
        let ratio = monthCost / monthlyBudget
        let level = ratio >= 1 ? "100" : ratio >= 0.8 ? "80" : ""
        let key = String(Day.string(Date()).prefix(7)) + level
        guard !level.isEmpty, key != lastAlertLevel else { return }
        lastAlertLevel = key
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = "Ember — budget \(level) %"
            c.body = String(format: "Dépense du mois : $%.2f sur $%.0f.", self.monthCost, self.monthlyBudget)
            center.add(UNNotificationRequest(identifier: key, content: c, trigger: nil))
        }
    }

    func notify(_ title: String, _ body: String, id: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body
            center.add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
        }
    }

    /// One notification per quota window, the first time it drops under the chosen threshold.
    private func checkQuotas() {
        guard quotaAlert > 0 else { return }
        var seen = alertedQuotas.split(separator: ",").map(String.init)
        for q in quotas {
            guard let r = q.resetsAt, 100 - q.usedPercent <= Double(quotaAlert) else { continue }
            let key = q.id + "@" + String(Int(r.timeIntervalSince1970 / 60))
            guard !seen.contains(key) else { continue }
            seen.append(key)
            notify("Ember — \(providerName(q.provider)) : \(q.title)",
                   String(format: "Il reste %.0f %% de quota. %@", 100 - q.usedPercent, resetText(r)), id: key)
        }
        alertedQuotas = seen.suffix(30).joined(separator: ",")
    }

    func resetHistory() {
        index = [:]
        for f in ["/quota-history.json", "/scan-cache.json"] { try? FileManager.default.removeItem(atPath: Paths.support + f) }
        rebuildQuotas()
        refresh()
    }

    // MARK: export

    func exportCSV() -> URL? {
        var s = "day,provider,model,project,input,output,cache_read,cache_write,messages,cost_usd,estimated\n"
        for r in records.sorted(by: { $0.day < $1.day }) {
            s += "\(r.day),\(r.provider),\(r.model),\"\(r.project)\",\(r.input),\(r.output),\(r.cacheRead),\(r.cacheWrite),\(r.messages),\(String(format: "%.4f", cost(r))),\(r.estimated)\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ember-export.csv")
        try? s.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Live Claude usage (read-only)

struct LiveError: Error { var message: String }

enum LiveClaude {
    static func fetch() async -> Result<[QuotaWindow], LiveError> {
        guard let token = readToken() else { return .failure(LiveError(message: "Jeton Claude Code introuvable ou expiré. Ouvrez Claude Code pour le renouveler.")) }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { return .failure(LiveError(message: "Réponse HTTP \(code)")) }
            guard let d = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure(LiveError(message: "Format inattendu")) }
            var out: [QuotaWindow] = []
            for (key, label) in [("five_hour", "5 h"), ("seven_day", "7 j")] {
                if let w = d[key] as? [String: Any], let u = w["utilization"] as? Double {
                    out.append(QuotaWindow(provider: "claude", label: label, usedPercent: u,
                                           resetsAt: (w["resets_at"] as? String).flatMap(Day.parse), source: "live"))
                }
            }
            return .success(out)
        } catch { return .failure(LiveError(message: error.localizedDescription)) }
    }

    /// Reads the access token only. Never writes to the Keychain and never calls the refresh endpoint.
    private static func readToken() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
            let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let oauth = o["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String
        else { return nil }
        if let exp = oauth["expiresAt"] as? Double, exp < Date().timeIntervalSince1970 * 1000 { return nil }
        return token
    }
}
