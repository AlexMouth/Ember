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

/// A titled glass card used by every settings tab.
struct SCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).card(radius: 12)
        }
    }
}

func note(_ t: String) -> some View { Text(t).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }

/// ImageRenderer cannot draw ScrollViews, so `--snapshot` flips this.
enum SnapshotMode { nonisolated(unsafe) static var on = false }

struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        let body = VStack(alignment: .leading, spacing: 18) { content }.padding(20)
        Group { if SnapshotMode.on { body } else { ScrollView { body } } }
            .background(AmbientBackground(strength: 0.7))
    }
}

final class SettingsFlags: ObservableObject { @Published var confirmReset = false }

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @StateObject private var login = LoginState()
    @StateObject private var flags = SettingsFlags()

    var quotaProviders: [ProviderInfo] {
        let ids = Set(store.quotas.map(\.provider)).union(["claude", "codex"])
        return store.providers.filter { ids.contains($0.id) }
    }

    /// Renders a single tab without the TabView (used by `--snapshot`).
    var only: String? = nil

    var body: some View {
        if let only {
            Group { only == "alerts" ? AnyView(alerts) : AnyView(general) }
        } else { tabs }
    }

    var tabs: some View {
        TabView {
            general.tabItem { Label("Général", systemImage: "gearshape") }
            alerts.tabItem { Label("Alertes", systemImage: "bell.badge") }
            quota.tabItem { Label("Quotas", systemImage: "gauge.with.dots.needle.67percent") }
            data.tabItem { Label("Données", systemImage: "externaldrive") }
            SourcesView().tabItem { Label("Sources", systemImage: "square.stack.3d.up") }
            about.tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 600, height: 500)
    }

    var general: some View {
        SettingsPane {
            SCard(title: "Démarrage") {
                Toggle("Lancer Ember à l'ouverture de session", isOn: $login.enabled)
            }
            SCard(title: "Barre des menus") {
                Picker("Afficher", selection: store.$menuMode) {
                    Text("Quota si dispo, sinon dépense du jour").tag("auto")
                    Text("Quota restant").tag("quota")
                    Text("Dépense du jour").tag("cost")
                    Text("Icône seule").tag("icon")
                }
                if store.menuMode == "auto" || store.menuMode == "quota" {
                    Picker("Quota de", selection: store.$menuProvider) {
                        ForEach(quotaProviders) { p in Text(p.name).tag(p.id) }
                    }
                }
            }
            SCard(title: "Actualisation") {
                Stepper("Toutes les \(store.refreshMinutes) min", value: store.$refreshMinutes, in: 1...30)
                    .onChange(of: store.refreshMinutes) { _, _ in store.schedule() }
                Text("Ember actualise aussi chaque fois que tu reviens sur l'app.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var alerts: some View {
        SettingsPane {
            SCard(title: "Budget mensuel") {
                HStack {
                    Text("Budget (USD)")
                    Spacer()
                    TextField("0 = désactivé", value: store.$monthlyBudget, format: .number).frame(width: 110).multilineTextAlignment(.trailing)
                }
                note("Notification à 80 % puis à 100 % du budget. Prévision de fin de mois : \(money(store.monthProjection)).")
            }
            SCard(title: "Quotas") {
                Picker("Prévenir sous", selection: store.$quotaAlert) {
                    Text("Jamais").tag(0)
                    Text("30 % restants").tag(30)
                    Text("20 % restants").tag(20)
                    Text("10 % restants").tag(10)
                    Text("5 % restants").tag(5)
                }
                Toggle("Prévenir aussi quand la limite est atteinte (100 %)", isOn: store.$quotaAlertFull)
                note("Une seule notification par fenêtre (5 h, hebdomadaire…) et par seuil.")
            }
            SCard(title: "Test") {
                Button("Envoyer une notification de test") {
                    store.notify("Ember", "Les notifications fonctionnent.", id: "test-" + UUID().uuidString)
                }
            }
        }
    }

    var quota: some View {
        SettingsPane {
            SCard(title: "Quota Claude en direct (optionnel)") {
                Toggle("Lire le quota réel depuis le compte Claude", isOn: store.$liveClaude)
                note("Activé par défaut. Ember lit le jeton de Claude Code dans ton trousseau (lecture seule, macOS peut demander l'autorisation la première fois) et interroge api.anthropic.com. Il ne renouvelle jamais le jeton et n'écrit jamais dans le trousseau. Le quota n'est connu que pour le présent : la courbe du début de la fenêtre en cours est reconstituée à partir de ta consommation Claude Code et mise à l'échelle sur le niveau réel.")
                if !store.liveStatus.isEmpty { Label(store.liveStatus, systemImage: "info.circle").font(.caption) }
            }
        }
    }

    var data: some View {
        SettingsPane {
            SCard(title: "Fichiers") {
                Button("Ouvrir le dossier de données") { NSWorkspace.shared.open(URL(fileURLWithPath: Paths.support)) }
                Button("Modifier les prix des modèles…") {
                    let f = Paths.support + "/pricing-overrides.json"
                    if !FileManager.default.fileExists(atPath: f) {
                        try? "{\n  \"mon-modele\": [3.0, 15.0, 0.3, 3.75]\n}\n".write(toFile: f, atomically: true, encoding: .utf8)
                    }
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)])
                }
                note("Prix en USD par million de tokens : [entrée, sortie, cache lu, cache écrit]. Pris en compte au prochain lancement.")
            }
            SCard(title: "Export") {
                Button("Exporter tout en CSV…") {
                    if let u = store.exportCSV() { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                }
            }
            SCard(title: "Réinitialiser") {
                Button("Effacer l'historique de quota et le cache…", role: .destructive) { flags.confirmReset = true }
                note("Les journaux des IA ne sont jamais touchés : Ember reconstruit tout au prochain scan.")
            }
        }
        .confirmationDialog("Effacer l'historique de quota d'Ember ?", isPresented: $flags.confirmReset) {
            Button("Effacer", role: .destructive) { store.resetHistory() }
        }
    }

    var about: some View {
        VStack(spacing: 10) {
            Image(systemName: "flame.fill").font(.system(size: 44)).foregroundStyle(.orange)
            Text("Ember").font(.title.weight(.bold))
            Text("Suivi local de la consommation de tes IA").foregroundStyle(.secondary)
            Divider().frame(width: 200)
            Text("Tout est calculé sur ton Mac. Aucune donnée n'est envoyée, sauf l'appel Anthropic si tu actives le quota Claude en direct.")
                .font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
            Text("Prix des modèles : models.dev").font(.caption).foregroundStyle(.tertiary)
            Divider().frame(width: 200)
            UpdateRow().frame(maxWidth: 380)
        }.padding()
    }
}
