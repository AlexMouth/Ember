import Charts
import ServiceManagement
import SwiftUI

func money(_ v: Double) -> String {
    v >= 100 ? String(format: "$%.0f", v) : String(format: "$%.2f", v)
}

func compact(_ n: Int) -> String {
    let d = Double(n)
    if d >= 1e9 { return String(format: "%.1fG", d / 1e9) }
    if d >= 1e6 { return String(format: "%.1fM", d / 1e6) }
    if d >= 1e3 { return String(format: "%.0fk", d / 1e3) }
    return "\(n)"
}

func resetText(_ d: Date?) -> String {
    guard let d else { return "" }
    let s = d.timeIntervalSinceNow
    if s <= 0 { return "réinitialisé" }
    let h = Int(s / 3600), m = Int(s.truncatingRemainder(dividingBy: 3600) / 60)
    return h >= 24 ? "reset dans \(h / 24) j \(h % 24) h" : "reset dans \(h) h \(m) min"
}

// MARK: - Shared

struct SourcesView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let list = VStack(alignment: .leading, spacing: 10) {
                Text("IA détectées sur ce Mac").font(.title3.weight(.semibold))
                ForEach(store.providers.filter { $0.status != .notInstalled }) { p in
                    HStack(alignment: .top, spacing: 12) {
                        ProviderIcon(id: p.id, symbol: p.symbol, size: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name).font(.callout.weight(.semibold))
                            switch p.status {
                            case .active(let n):
                                HStack(spacing: 5) { Circle().fill(.green).frame(width: 6, height: 6); Text("Suivi actif · \(n) série\(n > 1 ? "s" : "")") }
                                    .font(.caption).foregroundStyle(.green)
                            case .detectedNoData(let r): Text(r).font(.caption).foregroundStyle(.secondary)
                            case .notInstalled: EmptyView()
                            }
                            Text("Lit : " + p.paths.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).card(radius: 12)
                }
        }.padding(20)
        return (SnapshotMode.on ? AnyView(list) : AnyView(ScrollView { list })).background(AmbientBackground(strength: 0.7))
    }
}

// MARK: - Settings

final class LoginState: ObservableObject {
    @Published var enabled = SMAppService.mainApp.status == .enabled {
        didSet {
            guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
            do { try enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
            catch { enabled = SMAppService.mainApp.status == .enabled }
        }
    }
}

/// ImageRenderer cannot draw ScrollViews, so `--snapshot` flips this.
enum SnapshotMode { nonisolated(unsafe) static var on = false }

final class SettingsFlags: ObservableObject {
    @Published var confirmReset = false
    /// `--settings-pane <name>` opens a given pane (used for screenshots).
    @Published var pane: SettingsPage? = CommandLine.arguments.firstIndex(of: "--settings-pane")
        .flatMap { $0 + 1 < CommandLine.arguments.count ? SettingsPage(rawValue: CommandLine.arguments[$0 + 1]) : nil } ?? .general
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, menuBar, alerts, claude, data, sources, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "Général"
        case .menuBar: "Barre des menus"
        case .alerts: "Notifications"
        case .claude: "Compte Claude"
        case .data: "Données"
        case .sources: "Sources"
        case .about: "À propos"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .menuBar: "menubar.rectangle"
        case .alerts: "bell.badge.fill"
        case .claude: "key.fill"
        case .data: "externaldrive.fill"
        case .sources: "square.stack.3d.up.fill"
        case .about: "info.circle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .general: .gray
        case .menuBar: .blue
        case .alerts: .red
        case .claude: .orange
        case .data: .indigo
        case .sources: .green
        case .about: .gray
        }
    }
}

/// System Settings–style icon: white glyph on a small rounded colour tile.
struct SettingsIcon: View {
    let page: SettingsPage
    var body: some View {
        Image(systemName: page.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(page.tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Settings window: sidebar of panes, native grouped forms on the right (System Settings layout).
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @StateObject private var login = LoginState()
    @StateObject private var flags = SettingsFlags()

    var quotaProviders: [ProviderInfo] {
        let ids = Set(store.quotas.map(\.provider)).union(["claude", "codex"])
        return store.providers.filter { ids.contains($0.id) }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsPage.allCases, selection: $flags.pane) { p in
                Label { Text(p.title) } icon: { SettingsIcon(page: p) }.tag(p)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .padding(.top, 28)
            .frame(width: 210)
            .background(.regularMaterial)
            Divider()
            let p = flags.pane ?? .general
            VStack(alignment: .leading, spacing: 0) {
                Text(p.title).font(.title2.weight(.semibold))
                    .padding(.horizontal, 20).padding(.top, 34)
                page(p).formStyle(.grouped)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .frame(minWidth: 700, idealWidth: 720, minHeight: 500, idealHeight: 540)
        .confirmationDialog("Effacer l'historique de quota d'Ember ?", isPresented: $flags.confirmReset) {
            Button("Effacer", role: .destructive) { store.resetHistory() }
        } message: {
            Text("Les journaux de tes IA ne sont jamais touchés : Ember reconstruit tout au prochain scan.")
        }
    }

    @ViewBuilder func page(_ p: SettingsPage) -> some View {
        switch p {
        case .general: general
        case .menuBar: menuBar
        case .alerts: alerts
        case .claude: claude
        case .data: data
        case .sources: sources
        case .about: about
        }
    }

    // MARK: panes

    var general: some View {
        Form {
            Section {
                Toggle("Ouvrir Ember à l'ouverture de session", isOn: $login.enabled)
            }
            Section {
                Picker("Actualiser", selection: store.$refreshMinutes) {
                    ForEach([1, 2, 5, 10, 15, 30], id: \.self) { Text("Toutes les \($0) min").tag($0) }
                }
                .onChange(of: store.refreshMinutes) { _, _ in store.schedule() }
            } footer: {
                Text("Ember actualise aussi à chaque ouverture du menu.").foregroundStyle(.secondary)
            }
        }
    }

    var menuBar: some View {
        Form {
            Section {
                LabeledContent("Aperçu") { MenuBarPreview() }
            }
            Section {
                Picker("Texte", selection: store.$menuMode) {
                    Text("Quota restant, sinon dépense").tag("auto")
                    Text("Quota restant").tag("quota")
                    Text("Dépense du jour").tag("cost")
                    Text("Aucun (icône seule)").tag("icon")
                }
                if store.menuMode == "auto" || store.menuMode == "quota" {
                    Picker("Quota suivi", selection: store.$menuProvider) {
                        ForEach(quotaProviders) { p in Text(p.name).tag(p.id) }
                    }
                }
            }
            Section {
                Toggle("Flamme colorée selon le quota", isOn: store.$menuTint)
                Toggle("Mini-jauge du quota restant", isOn: store.$menuGauge)
            } footer: {
                Text("Verte tant que le quota va bien, orange dès 80 % utilisés, rouge dès 95 %.").foregroundStyle(.secondary)
            }
        }
    }

    var alerts: some View {
        Form {
            Section {
                LabeledContent("Budget mensuel") {
                    TextField("Aucun", value: store.$monthlyBudget, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .labelsHidden().multilineTextAlignment(.trailing).frame(width: 100)
                }
                LabeledContent("Projection du mois", value: money(store.monthProjection))
            } header: { Text("Budget") } footer: {
                Text("Notification à 80 % puis à 100 % du budget. 0 désactive l'alerte.").foregroundStyle(.secondary)
            }
            Section {
                Picker("Prévenir quand il reste", selection: store.$quotaAlert) {
                    Text("Jamais").tag(0)
                    ForEach([30, 20, 10, 5], id: \.self) { Text("\($0) %").tag($0) }
                }
                Toggle("Prévenir quand la limite est atteinte", isOn: store.$quotaAlertFull)
            } header: { Text("Quotas") } footer: {
                Text("Une seule notification par fenêtre (5 h, hebdomadaire…) et par seuil.").foregroundStyle(.secondary)
            }
            Section {
                Button("Envoyer une notification de test") {
                    store.notify("Ember", "Les notifications fonctionnent.", id: "test-" + UUID().uuidString)
                }
            }
        }
    }

    var claude: some View {
        Form {
            Section {
                Toggle("Lire le quota réel du compte Claude", isOn: store.$liveClaude)
                if store.liveClaude {
                    LabeledContent("État") { ClaudeLinkStatus() }
                    if let e = store.liveTokenExpiry {
                        LabeledContent(e < Date() ? "Jeton expiré" : "Jeton valide jusqu'à",
                                       value: e.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            } footer: {
                Text("Ember lit le jeton de Claude Code dans le trousseau, en lecture seule, et interroge api.anthropic.com. Il ne renouvelle jamais ce jeton : c'est Claude Code qui le fait quand il tourne.")
                    .foregroundStyle(.secondary)
            }
            if store.liveClaude, let k = store.liveProblem {
                Section {
                    Text(store.liveStatus).foregroundStyle(.secondary)
                    HStack {
                        if k == .signedOut {
                            Button("Se reconnecter (/login)") { ClaudeLink.open(login: true) }
                        } else {
                            Button("Lancer Claude Code") { ClaudeLink.open(login: false) }
                        }
                        Button("Réessayer") { store.refresh() }
                    }
                } header: { Text("Pourquoi") }
            }
        }
    }

    var data: some View {
        Form {
            Section {
                LabeledContent("Dossier de données") {
                    Button("Afficher dans le Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: Paths.support)) }
                }
                LabeledContent("Prix des modèles") {
                    Button("Modifier…") {
                        let f = Paths.support + "/pricing-overrides.json"
                        if !FileManager.default.fileExists(atPath: f) {
                            try? "{\n  \"mon-modele\": [3.0, 15.0, 0.3, 3.75]\n}\n".write(toFile: f, atomically: true, encoding: .utf8)
                        }
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)])
                    }
                }
                LabeledContent("Toute la consommation") {
                    Button("Exporter en CSV…") {
                        if let u = store.exportCSV() { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                    }
                }
            } footer: {
                Text("Prix en USD par million de tokens : [entrée, sortie, cache lu, cache écrit], pris en compte au prochain lancement.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Historique de quota et cache") {
                    Button("Effacer…", role: .destructive) { flags.confirmReset = true }
                }
            }
        }
    }

    var sources: some View {
        Form {
            Section {
                ForEach(store.providers.filter { $0.status != .notInstalled }) { p in
                    HStack(spacing: 10) {
                        ProviderIcon(id: p.id, symbol: p.symbol, size: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                            Text(p.paths.joined(separator: " · ")).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        switch p.status {
                        case .active: Text("Suivie").font(.callout).foregroundStyle(.green)
                        case .detectedNoData: Text("Sans données").font(.callout).foregroundStyle(.secondary)
                        case .notInstalled: EmptyView()
                        }
                    }
                    .help({ if case .detectedNoData(let r) = p.status { return r } else { return "" } }())
                }
            } footer: {
                Text("Les IA « sans données » sont installées mais ne laissent aucun compteur lisible sur le Mac.").foregroundStyle(.secondary)
            }
        }
    }

    var about: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ember").font(.title2.weight(.semibold))
                        Text("Suivi local de la consommation de tes IA").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                UpdateRow()
            } footer: {
                Text("Tout est calculé sur ton Mac. Seul le quota Claude en direct contacte api.anthropic.com. Prix des modèles : models.dev.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Live preview of the menu-bar item with the current settings.
struct MenuBarPreview: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let used = primaryQuota(store.quotas(for: store.menuProvider))?.usedPercent
        let level = store.menuTint && used != nil ? AppDelegate.alertLevel(used: used) : nil
        let gauge = store.menuGauge ? used.map { (100 - min(max($0, 0), 100)) / 100 } : nil
        HStack(spacing: 4) {
            if let img = AppDelegate.flame(level: level, remaining: gauge) {
                Image(nsImage: img).renderingMode(level == nil ? .template : .original)
            }
            let t = AppDelegate.current?.menuLabel ?? ""
            if !t.isEmpty { Text(t).monospacedDigit() }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Connection state of the live Claude quota, as a coloured dot and a short word.
struct ClaudeLinkStatus: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let (c, t): (Color, String) = switch store.liveProblem {
        case nil: store.liveStatus == "OK" ? (.green, "Connecté") : (.gray, "En attente")
        case .expired: (.orange, "Jeton expiré")
        case .signedOut: (.red, "Déconnecté")
        case .other: (.orange, "Injoignable")
        }
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t)
        }
    }
}
