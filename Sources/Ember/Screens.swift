import Charts
import SwiftUI

// MARK: - Detected-only agents

func isRunning(_ p: ProviderInfo) -> Bool {
    let apps = p.paths.filter { $0.hasSuffix(".app") }.map { expandHome($0) }
    return NSWorkspace.shared.runningApplications.contains { a in
        guard let u = a.bundleURL?.path else { return false }
        return apps.contains(u)
    }
}
func expandHome(_ s: String) -> String { (s as NSString).expandingTildeInPath }

struct DetectedRow: View {
    let p: ProviderInfo
    var body: some View {
        HStack(spacing: 8) {
            ProviderIcon(id: p.id, symbol: p.symbol, size: 16)
            Text(p.name).font(.callout)
            Spacer()
            if isRunning(p) { Circle().fill(.green).frame(width: 7, height: 7); Text("ouvert").font(.caption).foregroundStyle(.secondary) }
            else { Text("installé").font(.caption).foregroundStyle(.tertiary) }
        }
    }
}

struct DetectedPage: View {
    let p: ProviderInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProviderIcon(id: p.id, symbol: p.symbol, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.title2.weight(.semibold))
                    HStack(spacing: 6) {
                        Circle().fill(isRunning(p) ? Color.green : Color.gray).frame(width: 7, height: 7)
                        Text(isRunning(p) ? "En cours d'utilisation" : "Installé").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Section_(title: "Suivi") {
                AnyView(VStack(alignment: .leading, spacing: 8) {
                    Text("Ember voit cette IA sur ton Mac, mais elle ne laisse aucun compteur de tokens ni de quota lisible en local (l'usage est géré côté serveur). Aucune dépense ne peut donc être calculée.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Lit : " + p.paths.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
                })
            }
        }
    }
}

// MARK: - Small building blocks

struct Tile: View {
    let title: String, value: String
    var sub: String = ""
    var tint: Color = .orange
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).tracking(-0.3).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub.isEmpty ? " " : sub).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .card(tint: tint)
    }
}

struct Section_: View {
    let title: String
    var trailing: String = ""
    @ViewBuilder var content: () -> AnyView
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if !trailing.isEmpty { Text(trailing).font(.caption).foregroundStyle(.secondary) }
            }
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

func shareBar(_ f: Double, _ c: Color) -> some View {
    GeometryReader { g in
        ZStack(alignment: .leading) {
            Capsule().fill(Color.secondary.opacity(0.15))
            Capsule().fill(c).frame(width: max(3, g.size.width * min(max(f, 0), 1)))
        }
    }.frame(height: 5)
}

/// Quota missing: explain why and offer the opt-in.
struct QuotaMissing: View {
    @EnvironmentObject var store: Store
    let provider: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Quota indisponible", systemImage: "gauge.with.dots.needle.0percent").font(.headline)
            if provider == "claude" {
                Text("Ember n'a pas de relevé récent du quota Claude. Activez la lecture en direct (jeton Claude Code lu en lecture seule dans le trousseau) pour voir les courbes. L'historique se construit ensuite tout seul.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(store.liveClaude ? "Lecture activée — actualiser" : "Activer la lecture en direct") {
                        store.liveClaude = true; store.refresh()
                    }
                    if !store.liveStatus.isEmpty { Text(store.liveStatus).font(.caption).foregroundStyle(.secondary) }
                }
            } else {
                Text("Aucun relevé de quota local récent pour cette source.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// The Claude Code conversation in progress (or the latest one).
struct SessionCard: View {
    let s: SessionInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(s.isLive ? Color.green : Color.gray).frame(width: 7, height: 7)
                Text(s.isLive ? "Session en cours" : "Dernière session").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(s.isLive ? "active" : s.last.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(s.project.isEmpty ? "Sans projet" : s.project).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(money(s.cost)).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
            }
            HStack(spacing: 12) {
                Label(durationText(s.duration), systemImage: "clock").lineLimit(1).fixedSize()
                Label(compact(s.tokens), systemImage: "circle.grid.2x2").fixedSize()
                Label("\(s.messages) msg", systemImage: "bubble.left").fixedSize()
                Spacer()
                Text(s.model).lineLimit(1).foregroundStyle(.tertiary)
            }.font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).card(radius: 12)
    }
}

func durationText(_ t: TimeInterval) -> String {
    let m = Int(t / 60)
    if m >= 1440 { return "\(m / 1440) j \((m % 1440) / 60) h" }
    return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(max(m, 1)) min"
}

/// Opens Terminal on Claude Code through a throwaway .command file (no Automation permission needed).
/// Launching `claude` is enough to renew an expired token; `/login` is only for a signed-out account.
enum ClaudeLink {
    static func open(login: Bool) {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("ember-claude.command")
        let script = "#!/bin/zsh -l\nclear\n" + (login ? "echo \"Reconnexion de Claude Code…\"\nclaude /login\n" : "claude\n")
        try? script.write(to: f, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.path)
        NSWorkspace.shared.open(f)
    }
}

// MARK: - Menu bar popover

/// One provider's quota windows: the big number is the window that runs out first.
struct QuotaHero: View {
    @EnvironmentObject var store: Store
    let pid: String
    var body: some View {
        let qs = store.quotas(for: pid).sorted { $0.windowMinutes < $1.windowMinutes }
        let tight = qs.min { $0.usedPercent > $1.usedPercent }
        let stale = pid == "claude" && store.liveClaude && store.liveProblem != nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ProviderIcon(id: pid, symbol: store.providers.first { $0.id == pid }?.symbol ?? "sparkles", size: 16)
                Text(store.providerName(pid)).font(.callout.weight(.semibold))
                Spacer()
                if stale {
                    Button { ClaudeLink.open(login: store.liveProblem == .signedOut) } label: {
                        Label("Estimation", systemImage: "exclamationmark.triangle.fill")
                    }
                    .buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(.orange)
                    .help(store.liveStatus + (store.liveProblem == .signedOut ? "\nCliquer pour se reconnecter." : "\nCliquer pour lancer Claude Code."))
                }
            }
            if let t = tight {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", max(0, 100 - t.usedPercent)))
                        .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("% restant").font(.callout).foregroundStyle(.secondary)
                    if qs.count > 1 { Text("· \(t.title)").font(.callout).foregroundStyle(.tertiary) }
                }
            }
            ForEach(qs) { q in
                let left = max(0, 100 - q.usedPercent)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(q.title).font(.caption)
                        Spacer()
                        Text(resetText(q.resetsAt)).font(.caption).foregroundStyle(.tertiary)
                        Text(String(format: "%.0f %%", left)).font(.caption.weight(.semibold)).monospacedDigit().frame(minWidth: 34, alignment: .trailing)
                    }
                    shareBar(left / 100, quotaColor(used: q.usedPercent))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(store.providerName(pid)), \(q.title)")
                .accessibilityValue(String(format: "%.0f %% restants, %@", left, resetText(q.resetsAt)))
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 14)
    }
}

func quotaColor(used: Double) -> Color {
    [Color.green, .orange, .red][AppDelegate.alertLevel(used: used)]
}

struct MenuBarView: View {
    @EnvironmentObject var store: Store
    var openDashboard: () -> Void = {}
    var openSettings: () -> Void = {}

    var quotaIDs: [String] {
        let ids = Set(store.quotas.map(\.provider))
        // The provider shown in the menu bar comes first.
        return ids.sorted { a, b in a == store.menuProvider ? true : b == store.menuProvider ? false : a < b }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            UpdateBanner()
            ForEach(quotaIDs, id: \.self) { QuotaHero(pid: $0) }
            if quotaIDs.isEmpty, store.liveClaude, store.providers.contains(where: { $0.id == "claude" && $0.status != .notInstalled }) {
                QuotaMissing(provider: "claude")
            }
            if let s = store.session, s.isLive { SessionCard(s: s) }
            spend
            footer
        }
        .padding(12).frame(width: 340)
        .background(AmbientBackground(strength: 0.6))
        .environment(\.inPopover, true)
    }

    var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill").foregroundStyle(.orange).font(.title3)
            Text("Ember").font(.headline)
            Spacer()
            if store.refreshing { ProgressView().controlSize(.small) }
            else if let t = store.lastRefresh {
                Text(t.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.tertiary)
                    .help("Dernière actualisation")
            }
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Actualiser").accessibilityLabel("Actualiser").disabled(store.refreshing)
                .keyboardShortcut("r")
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help("Réglages").accessibilityLabel("Réglages")
                .keyboardShortcut(",")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    /// Spend: today and 30 days, then the busiest sources (top 4).
    var spend: some View {
        let month = store.filtered(.month)
        let agents = store.providers.compactMap { p -> (ProviderInfo, Double)? in
            let rs = store.filtered(.month, provider: p.id)
            return rs.isEmpty ? nil : (p, store.totalCost(rs))
        }.sorted { $0.1 > $1.1 }
        let maxCost = max(agents.first?.1 ?? 1, 0.0001)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                stat("Aujourd'hui", money(store.todayCost))
                Spacer()
                stat("30 jours", money(store.totalCost(month)))
                Spacer()
                stat("Tokens 30 j", compact(store.totalTokens(month)))
            }
            if agents.count > 1 {
                Divider()
                ForEach(agents.prefix(4), id: \.0.id) { p, c in
                    HStack(spacing: 8) {
                        ProviderIcon(id: p.id, symbol: p.symbol, size: 14)
                        Text(p.name).font(.caption).lineLimit(1).frame(width: 92, alignment: .leading)
                        shareBar(c / maxCost, color(for: p.id))
                        Text(money(c)).font(.caption.monospacedDigit()).frame(width: 52, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(p.name).accessibilityValue(money(c))
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 14)
    }

    func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    var footer: some View {
        HStack {
            Button { openDashboard() } label: {
                Label("Tableau de bord", systemImage: "chart.xyaxis.line").frame(maxWidth: .infinity)
            }
            .emberProminent().tint(.orange).controlSize(.large).keyboardShortcut("d")
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                .emberGlass().controlSize(.large)
                .help("Quitter Ember").accessibilityLabel("Quitter Ember").keyboardShortcut("q")
        }
    }
}

// MARK: - Dashboard

final class DashState: ObservableObject {
    @Published var range: Range = .all
    @Published var sel: String? = "overview"
    @Published var mode = "Mois"
}

struct DashboardView: View {
    @EnvironmentObject var store: Store
    @StateObject private var ui = DashState()

    var data: [UsageRecord] {
        let provider = (ui.sel == nil || ui.sel == "overview" || ui.sel == "sources") ? nil : ui.sel
        return store.filtered(ui.range, provider: provider)
    }

    var detectedOnly: [ProviderInfo] {
        store.providers.filter { p in
            if case .detectedNoData = p.status { return store.quotas(for: p.id).isEmpty }
            return false
        }
    }
    var withQuota: [ProviderInfo] { store.providers.filter { !store.quotas(for: $0.id).isEmpty } }
    var agents: [ProviderInfo] {
        store.providers.filter { p in
            if case .active = p.status { return store.quotas(for: p.id).isEmpty }
            return false
        }
    }

    var title: String {
        switch ui.sel ?? "overview" {
        case "overview": return "Aperçu"
        case "sources": return "Sources détectées"
        default: return store.providerName(ui.sel ?? "")
        }
    }

    var body: some View {
        NavigationSplitView {
            List {
                row("overview", "Aperçu", "flame.fill", money(store.totalCost(store.filtered(ui.range))), .orange)
                if !withQuota.isEmpty {
                    SwiftUI.Section("Abonnements") {
                        ForEach(withQuota) { p in
                            let q = primaryQuota(store.quotas(for: p.id))
                            row(p.id, p.name, p.symbol, q.map { String(format: "%.0f %%", 100 - $0.usedPercent) } ?? "", color(for: p.id))
                        }
                    }
                }
                SwiftUI.Section("Agents") {
                    ForEach(agents) { p in row(p.id, p.name, p.symbol, money(store.totalCost(store.filtered(ui.range, provider: p.id))), color(for: p.id)) }
                }
                if !detectedOnly.isEmpty {
                    SwiftUI.Section("Autres IA détectées") {
                        ForEach(detectedOnly) { p in row(p.id, p.name, p.symbol, isRunning(p) ? "ouvert" : "", .gray) }
                    }
                }
                SwiftUI.Section("Réglages") { row("sources", "Sources détectées", "externaldrive.connected.to.line.below", "", .gray) }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ScrollView {
                Group {
                    switch ui.sel ?? "overview" {
                    case "overview": OverviewPage(data: data, ui: ui)
                    case "sources": SourcesView()
                    default:
                        if let d = detectedOnly.first(where: { $0.id == ui.sel }) { DetectedPage(p: d) }
                        else { ProviderPage(id: ui.sel ?? "", data: data, ui: ui) }
                    }
                }
                .frame(maxWidth: 1000).padding(pagePadding).frame(maxWidth: .infinity)
            }
            .background(AmbientBackground())
            .navigationTitle(title)
            .toolbar {
                ToolbarItemGroup {
                    Picker("Période", selection: $ui.range) { ForEach(Range.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                    Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Actualiser").accessibilityLabel("Actualiser").disabled(store.refreshing)
                    Button { if let u = store.exportCSV() { NSWorkspace.shared.activateFileViewerSelecting([u]) } } label: {
                        Image(systemName: "square.and.arrow.up")
                    }.help("Exporter en CSV").accessibilityLabel("Exporter en CSV")
                    Button { AppDelegate.current?.showSettings() } label: { Image(systemName: "gearshape") }.help("Réglages").accessibilityLabel("Réglages")
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    func row(_ id: String, _ title: String, _ icon: String, _ trailing: String, _ tint: Color) -> some View {
        HStack {
            ProviderIcon(id: id, symbol: icon, size: 18).foregroundStyle(tint).frame(width: 22)
            Text(title).lineLimit(1)
            Spacer(minLength: 4)
            Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { ui.sel = id }
        .background(ui.sel == id ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .listRowSeparator(.hidden)
    }
}

// MARK: - Pages


struct OverviewPage: View {
    @EnvironmentObject var store: Store
    let data: [UsageRecord]
    @ObservedObject var ui: DashState

    var body: some View {
        VStack(alignment: .leading, spacing: gridSpacing) {
            HStack(spacing: gridSpacing) {
                Tile(title: "Dépense (équiv. API)", value: money(store.totalCost(data)))
                Tile(title: "Tokens", value: compact(store.totalTokens(data)), tint: .blue)
                Tile(title: "Rythme", value: money(store.burnRate) + "/h", sub: "3 dernières heures", tint: .red)
                Tile(title: "Projection du mois", value: money(store.monthProjection),
                     sub: store.monthlyBudget > 0 ? "budget \(money(store.monthlyBudget))" : "fin de mois", tint: .purple)
            }
            let provs = Array(Set(store.quotas.map(\.provider))).sorted()
            if !provs.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: gridSpacing), GridItem(.flexible(), spacing: gridSpacing)],
                          alignment: .leading, spacing: gridSpacing) {
                    ForEach(provs, id: \.self) { pid in
                        if let q = primaryQuota(store.quotas(for: pid)) {
                            QuotaPanel(info: store.info(q), height: 130)
                        }
                    }
                }
            }
            SpendChart(data: data, ui: ui, stacked: true)
            HStack(alignment: .top, spacing: gridSpacing) {
                RankingCard(title: "Par modèle", data: data, key: \.model, tint: .orange)
                RankingCard(title: "Par projet", data: data, key: \.project, tint: .blue)
            }
            let approx = Set(data.filter { Pricing.shared.isApproximate($0.model) }.map(\.model))
            if !approx.isEmpty {
                Text("Prix approchés par famille pour : " + approx.sorted().joined(separator: ", ") + ". Corrigez-les dans ~/Library/Application Support/Ember/pricing-overrides.json.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ProviderPage: View {
    @EnvironmentObject var store: Store
    let id: String
    let data: [UsageRecord]
    @ObservedObject var ui: DashState

    var body: some View {
        let qs = store.quotas(for: id)
        let infos = qs.map { store.info($0) }
        let cost = store.totalCost(data), tok = store.totalTokens(data)
        let models = store.breakdown(data, by: \.model)
        return VStack(alignment: .leading, spacing: gridSpacing) {
            if infos.isEmpty {
                if id == "claude" || id == "codex" { QuotaMissing(provider: id) }
            } else {
                Section_(title: "Compte " + store.providerName(id)) {
                    AnyView(VStack(alignment: .leading, spacing: 10) {
                        let run = infos.first { $0.willRunOut }
                        Label(run == nil ? "Dans les clous. Au rythme actuel, les limites tiennent jusqu'au reset."
                                         : "Attention : au rythme actuel, « \(run!.q.title) » sera épuisée avant le reset.",
                              systemImage: run == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(run == nil ? Color.green : Color.red)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: gridSpacing), GridItem(.flexible(), spacing: gridSpacing)], spacing: gridSpacing) { ForEach(infos, id: \.q.id) { QuotaPanel(info: $0, height: 150) } }
                    })
                }
            }
            HStack(spacing: gridSpacing) {
                Tile(title: "Dépense totale", value: money(cost), sub: "valeur équivalent API", tint: color(for: id))
                Tile(title: "Tokens", value: compact(tok), sub: "entrée, sortie et cache", tint: .blue)
                Tile(title: "Tokens / $", value: cost > 0 ? compact(Int(Double(tok) / cost)) : "—", tint: .green)
                Tile(title: "Modèles", value: "\(models.count)", tint: .purple)
            }
            SpendChart(data: data, ui: ui, stacked: false, provider: id)
            HStack(alignment: .top, spacing: gridSpacing) {
                RankingCard(title: "Modèles", data: data, key: \.model, tint: color(for: id))
                RankingCard(title: "Projets", data: data, key: \.project, tint: .blue)
            }
            TokenBreakdown(data: data)
        }
    }
}

