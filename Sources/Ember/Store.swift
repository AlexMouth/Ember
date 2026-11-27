import Foundation
import SwiftUI
import UserNotifications
import Security

enum Range: String, CaseIterable, Identifiable {
    case today = "Aujourd'hui", week = "7 jours", month = "30 jours", all = "Tout"
    var id: String { rawValue }
    var days: Int? {
        switch self { case .today: 1; case .week: 7; case .month: 30; case .all: nil }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var records: [UsageRecord] = [] { didSet { filterCache.removeAll(); costCache.removeAll() } }
    @Published var hours: [HourBucket] = []
    @Published var quotas: [QuotaWindow] = []
    @Published var providers: [ProviderInfo] = []
    @Published var lastRefresh: Date?
    @Published var refreshing = false
    @Published var liveStatus = ""
    /// Why the live Claude quota cannot be read, nil when it can (or when the reading is off).
    @Published var liveProblem: LiveError.Kind?
    /// Expiry of the newest Claude Code access token seen in the Keychain.
    @Published var liveTokenExpiry: Date?
    @Published var session: SessionInfo?

    @AppStorage("monthlyBudget") var monthlyBudget: Double = 0
    @AppStorage("liveClaude") var liveClaude = true
    @AppStorage("refreshMinutes") var refreshMinutes = 5
    @AppStorage("lastAlertLevel") private var lastAlertLevel = ""
    @AppStorage("menuMode") var menuMode = "auto"          // auto | quota | cost | icon
    @AppStorage("menuProvider") var menuProvider = "claude"
    @AppStorage("menuTint") var menuTint = true             // flame green / orange / red by quota
    @AppStorage("menuGauge") var menuGauge = false          // small gauge of the remaining quota next to the flame
    @AppStorage("quotaAlert") var quotaAlert = 0            // 0 = off, else % remaining threshold
    @AppStorage("quotaAlertFull") var quotaAlertFull = true  // also notify when a window is exhausted
    @AppStorage("alertedQuotas") private var alertedQuotas = ""

    private let cache = FileCache()
    private var timer: Timer?
    private var lastLive = Date.distantPast
    private var index: [String: QuotaSample] = [:] { didSet { seriesDirty = true } }
    private var seriesDirty = true
    private var seriesCache: [String: [QuotaSample]] = [:]
    private var lastSave = Date.distantPast
    private var unsaved = false
    private var claudeCosts: [(ts: Double, cost: Double)] = []
    /// Memoised aggregates, dropped whenever `records` changes. Views call these many times per render.
    private var filterCache: [String: [UsageRecord]] = [:]
    private var costCache: [String: Double] = [:]

    init() {
        providers = Discovery.providers().map {
            ProviderInfo(id: $0.id, name: $0.name, symbol: $0.symbol,
                         status: $0.installed() ? .detectedNoData(reason: "Analyse…") : .notInstalled, paths: $0.paths)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Date().timeIntervalSince(self.lastRefresh ?? .distantPast) > 20 else { return }
                self.refresh()
            }
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
        timer?.tolerance = Double(max(1, refreshMinutes)) * 12  // 20 %: lets macOS coalesce wake-ups
    }

    // MARK: refresh

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let cache = self.cache
        Task.detached(priority: .utility) {
            let all = Discovery.providers()
            let installed = all.map { $0.installed() }
            let slots = ScanSlots(count: all.count)
            DispatchQueue.concurrentPerform(iterations: all.count) { i in
                guard installed[i] else { return }
                slots.set(i, all[i].scan(cache: cache))
            }
            let outputs: [(UsageProvider, ScanOutput)] = slots.values.enumerated().compactMap { i, o in o.map { (all[i], $0) } }
            cache.save()
            let (recs, hrs) = Store.aggregate(outputs)
            let samples = outputs.flatMap { $0.1.quotaSamples }
            let costs: [(ts: Double, cost: Double)] = outputs.filter { $0.0.id == "claude" }.flatMap { $0.1.entries }
                .map { e in (e.ts, Pricing.shared.cost(UsageRecord(provider: "claude", model: e.model, project: "", day: "",
                    input: e.input, output: e.output, cacheRead: e.cacheRead, cacheWrite: e.cacheWrite))) }
                .sorted { $0.0 < $1.0 }
            let session = SessionInfo.latest(from: outputs.filter { $0.0.id == "claude" }.flatMap { $0.1.entries })
            let infos: [ProviderInfo] = all.enumerated().map { i, p in
                let n = recs.filter { $0.provider == p.id }.count
                let status: ProviderStatus
                if !installed[i] { status = .notInstalled }
                else if let d = p as? Detected { status = .detectedNoData(reason: d.reason) }
                else if n > 0 { status = .active(records: n) }
                else { status = .detectedNoData(reason: "Aucune donnée d'usage trouvée.") }
                return ProviderInfo(id: p.id, name: p.name, symbol: p.symbol, status: status, paths: p.paths)
            }
            await MainActor.run {
                self.records = recs; self.hours = hrs; self.providers = infos; self.claudeCosts = costs; self.session = session
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
            unsaved = true
            if Date().timeIntervalSince(lastSave) > 600 { flush() }
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

    /// Writes the quota history, at most every 10 min (and on quit) instead of on every new sample.
    func flush() {
        guard unsaved else { return }
        unsaved = false; lastSave = Date()
        let all = Array(index.values)
        Task.detached(priority: .utility) { QuotaDisk.save(all) }
    }

    func info(_ q: QuotaWindow) -> QuotaInfo {
        if seriesDirty {
            seriesCache = Dictionary(grouping: index.values) { $0.provider + "|" + $0.label }
            seriesDirty = false
        }
        let r = q.resetsAt?.timeIntervalSince1970 ?? 0
        let s = (seriesCache[q.provider + "|" + q.label] ?? []).filter { abs($0.resets - r) < 600 }
        return QuotaInfo(q: q, samples: s)
    }

    func quotas(for provider: String) -> [QuotaWindow] { quotas.filter { $0.provider == provider } }

    // MARK: queries

    /// Re-reads the price files and recomputes every cost.
    func reloadPrices() {
        Pricing.shared.reload()
        costCache.removeAll()
        objectWillChange.send()
        refresh()  // hourly buckets and the live session carry costs computed at scan time
    }

    func cost(_ r: UsageRecord) -> Double {
        if let c = costCache[r.id] { return c }
        let c = Pricing.shared.cost(r)
        costCache[r.id] = c
        return c
    }

    func filtered(_ range: Range, provider: String? = nil) -> [UsageRecord] {
        let cutoff = range.days.map { Day.string(Calendar.current.date(byAdding: .day, value: -($0 - 1), to: Date())!) }
        return memo("r|\(cutoff ?? "*")|\(provider ?? "*")") {
            records.filter { r in (cutoff == nil || r.day >= cutoff!) && (provider == nil || r.provider == provider) }
        }
    }

    func totalCost(_ rs: [UsageRecord]) -> Double { rs.reduce(0) { $0 + cost($1) } }
    func totalTokens(_ rs: [UsageRecord]) -> Int { rs.reduce(0) { $0 + $1.totalTokens } }

    var monthRecords: [UsageRecord] {
        let prefix = String(Day.string(Date()).prefix(7))
        return memo("m|\(prefix)") { records.filter { $0.day.hasPrefix(prefix) } }
    }
    var monthCost: Double { totalCost(monthRecords) }
    var todayCost: Double {
        let today = Day.string(Date())
        return totalCost(memo("d|\(today)") { records.filter { $0.day == today } })
    }

    func breakdown(_ rs: [UsageRecord], by key: KeyPath<UsageRecord, String>) -> [Breakdown] {
        Store.breakdown(rs, by: key, cost: cost)
    }

    /// Groups records by a field and totals each group once, sorted by cost, then tokens, then name.
    nonisolated static func breakdown(_ rs: [UsageRecord], by key: KeyPath<UsageRecord, String>,
                                      cost: (UsageRecord) -> Double) -> [Breakdown] {
        var acc: [String: Breakdown] = [:]
        for r in rs {
            let k = r[keyPath: key]
            var b = acc[k] ?? Breakdown(name: k)
            b.cost += cost(r)
            b.tokens += r.totalTokens
            acc[k] = b
        }
        return acc.values.sorted { ($0.cost, $0.tokens, $1.name) > ($1.cost, $1.tokens, $0.name) }
    }

    /// Keys embed the cutoff day, so a cached entry can never outlive midnight.
    private func memo(_ key: String, _ make: () -> [UsageRecord]) -> [UsageRecord] {
        if let hit = filterCache[key] { return hit }
        let v = make()
        filterCache[key] = v
        return v
    }

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
        // While failing, retry every minute: Claude Code may have renewed its token in the meantime.
        let failing = await MainActor.run { self.liveProblem != nil }
        guard on, Date().timeIntervalSince(last) > (failing ? 55 : 300) else { return }
        let (result, expiry) = await LiveClaude.fetch()
        await MainActor.run {
            self.lastLive = Date()
            self.liveTokenExpiry = expiry
            switch result {
            case .success(let q):
                self.liveStatus = "OK"
                self.liveProblem = nil
                let now = Date().timeIntervalSince1970
                self.merge(q.compactMap { w in
                    w.resetsAt.map { QuotaSample(provider: w.provider, label: w.label, t: now, used: w.usedPercent,
                                                 resets: $0.timeIntervalSince1970, src: "live") }
                })
                self.backfillClaude()
            case .failure(let e): self.liveStatus = e.message; self.liveProblem = e.kind
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
        let spent = monthCost, budget = monthlyBudget
        let ratio = spent / budget
        let level = ratio >= 1 ? "100" : ratio >= 0.8 ? "80" : ""
        let key = String(Day.string(Date()).prefix(7)) + level
        guard !level.isEmpty, key != lastAlertLevel else { return }
        lastAlertLevel = key
        notify("Ember — budget \(level) %", String(format: "Dépense du mois : $%.2f sur $%.0f.", spent, budget), id: key)
    }

    /// Posts a local notification. Authorization is requested once per launch, not on every alert.
    func notify(_ title: String, _ body: String, id: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        Notifier.post(title: title, body: body, id: id)
    }

    /// One notification per quota window, the first time it drops under the chosen threshold.
    private func checkQuotas() {
        guard quotaAlert > 0 || quotaAlertFull else { return }
        var seen = alertedQuotas.split(separator: ",").map(String.init)
        for q in quotas {
            guard let r = q.resetsAt else { continue }
            let win = q.id + "@" + String(Int(r.timeIntervalSince1970 / 60))
            let left = 100 - q.usedPercent
            if quotaAlertFull, left <= 0.5, !seen.contains(win + "!") {
                seen.append(win + "!")
                notify("Ember — \(providerName(q.provider)) : \(q.title)",
                       "Limite atteinte. \(resetText(r))", id: win + "!")
            } else if quotaAlert > 0, left <= Double(quotaAlert), left > 0.5, !seen.contains(win) {
                seen.append(win)
                notify("Ember — \(providerName(q.provider)) : \(q.title)",
                       String(format: "Il reste %.0f %% de quota. %@", left, resetText(r)), id: win)
            }
        }
        alertedQuotas = seen.suffix(40).joined(separator: ",")
    }

    func resetHistory() {
        index = [:]
        for f in ["/quota-history.json", "/scan-cache.json"] { try? FileManager.default.removeItem(atPath: Paths.support + f) }
        rebuildQuotas()
        refresh()
    }

    // MARK: export

    /// RFC 4180: a field is quoted when it holds a comma, quote, CR or LF; inner quotes are doubled.
    /// Fields starting with = + - @ are prefixed with ' so spreadsheets don't run them as formulas.
    nonisolated static func csvField(_ v: String) -> String {
        var v = v
        if let f = v.first, "=+-@".contains(f), Double(v) == nil { v = "'" + v }
        guard v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return v }
        return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    nonisolated static func csvRow(_ fields: [String]) -> String { fields.map(csvField).joined(separator: ",") + "\r\n" }

    func exportCSV() -> URL? {
        var s = Store.csvRow(["day", "provider", "model", "project", "input", "output", "cache_read", "cache_write",
                              "messages", "cost_usd", "estimated"])
        for r in records.sorted(by: { $0.day < $1.day }) {
            s += Store.csvRow([r.day, r.provider, r.model, r.project, String(r.input), String(r.output),
                               String(r.cacheRead), String(r.cacheWrite), String(r.messages),
                               String(format: "%.4f", cost(r)), String(r.estimated)])
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ember-export.csv")
        try? s.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Live Claude usage (read-only)

struct LiveError: Error {
    enum Kind: Equatable {
        /// A token exists but its validity ran out: Claude Code renews it on its next launch.
        case expired
        /// No token, or the server refused it: a new sign-in (`/login`) is needed.
        case signedOut
        /// Network or server trouble: nothing to do on the user's side.
        case other
    }
    var kind: Kind = .other
    var message: String
}

/// Drops every redirect: the request carries a bearer token that must only ever reach api.anthropic.com.
final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}

enum LiveClaude {
    /// Ephemeral: no cookies, no credential store, no disk cache for responses fetched with the token.
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpShouldSetCookies = false
        return URLSession(configuration: c, delegate: RefuseRedirects(), delegateQueue: nil)
    }()
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// The result, plus the expiry of the newest token found (valid or not).
    static func fetch() async -> (Result<[QuotaWindow], LiveError>, Date?) {
        let (tokens, newest) = readTokens()
        return (await fetch(tokens: tokens, newest: newest), newest)
    }

    private static func fetch(tokens: [String], newest: Date?) async -> Result<[QuotaWindow], LiveError> {
        guard !tokens.isEmpty else {
            if let newest {
                return .failure(LiveError(kind: .expired, message: "Jeton Claude Code expiré depuis \(newest.formatted(date: .abbreviated, time: .shortened)). Il se renouvelle tout seul au prochain lancement de Claude Code."))
            }
            return .failure(LiveError(kind: .signedOut, message: "Aucun jeton Claude Code dans le trousseau. Connecte-toi avec `claude` puis /login."))
        }
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 15
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        do {
            var data = Data(), code = 0
            for t in tokens {
                req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
                let (d, resp) = try await session.data(for: req)
                // Refused redirects surface as the 3xx response itself: never treat it as data.
                guard resp.url?.host == endpoint.host else { code = 0; continue }
                data = d; code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200 { break }
            }
            if code == 401 { return .failure(LiveError(kind: .signedOut, message: "Jeton Claude Code refusé par Anthropic. Reconnecte-toi avec `claude` puis /login.")) }
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

    /// Keychain service names Claude Code uses (one per config directory, e.g. "Claude Code-credentials-ab12cd34").
    /// Lists attributes only (never the secret), so it never triggers a Keychain prompt. Cached 10 min.
    nonisolated(unsafe) private static var servicesCache: (names: [String], at: Date)?
    private static let servicesLock = NSLock()

    static func credentialServices() -> [String] {
        servicesLock.lock(); defer { servicesLock.unlock() }
        if let c = servicesCache, Date().timeIntervalSince(c.at) < 600 { return c.names }
        var names = ["Claude Code-credentials"]
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let items = result as? [[String: Any]] {
            for item in items {
                if let svc = item[kSecAttrService as String] as? String,
                   svc.hasPrefix("Claude Code-credentials"), !names.contains(svc) { names.append(svc) }
            }
        }
        servicesCache = (names, Date())
        return names
    }

    /// Reads still-valid access tokens (newest first) and the expiry of the newest token seen, valid or not.
    /// Never writes to the Keychain and never calls the refresh endpoint.
    private static func readTokens() -> (tokens: [String], newest: Date?) {
        var found: [(token: String, exp: Double)] = []
        var newest: Double = 0
        for service in credentialServices() {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            p.arguments = ["find-generic-password", "-s", service, "-w"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { continue }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0,
                let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let oauth = o["claudeAiOauth"] as? [String: Any],
                let token = oauth["accessToken"] as? String, !token.isEmpty
            else { continue }
            let exp = oauth["expiresAt"] as? Double ?? 0
            newest = max(newest, exp)
            if exp > 0, exp < Date().timeIntervalSince1970 * 1000 { continue }
            found.append((token, exp))
        }
        return (found.sorted { $0.exp > $1.exp }.map(\.token), newest > 0 ? Date(timeIntervalSince1970: newest / 1000) : nil)
    }
}

// MARK: - Notifications

/// Asks for notification permission once, then posts. Thread-safe.
enum Notifier {
    nonisolated(unsafe) private static var state: Bool?  // nil = not asked yet
    nonisolated(unsafe) private static var pending: [UNNotificationRequest] = []
    private static let lock = NSLock()

    static func post(title: String, body: String, id: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body
        let req = UNNotificationRequest(identifier: id, content: c, trigger: nil)
        lock.lock()
        switch state {
        case .some(true): lock.unlock(); UNUserNotificationCenter.current().add(req)
        case .some(false): lock.unlock()
        case .none:
            let first = pending.isEmpty
            pending.append(req)
            lock.unlock()
            guard first else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
                lock.lock(); state = ok; let queued = pending; pending = []; lock.unlock()
                if ok { queued.forEach { UNUserNotificationCenter.current().add($0) } }
            }
        }
    }
}

/// Results of a concurrent scan, one slot per provider, in provider order.
struct Breakdown: Hashable {
    var name: String
    var cost: Double = 0
    var tokens: Int = 0
}

final class ScanSlots: @unchecked Sendable {
    private var slots: [ScanOutput?]
    private let lock = NSLock()
    init(count: Int) { slots = Array(repeating: nil, count: count) }
    func set(_ i: Int, _ o: ScanOutput) { lock.lock(); slots[i] = o; lock.unlock() }
    var values: [ScanOutput?] { lock.lock(); defer { lock.unlock() }; return slots }
}
