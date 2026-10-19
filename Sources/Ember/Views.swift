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
        VStack(alignment: .leading, spacing: 10) {
            Text("IA détectées sur ce Mac").font(.headline)
            ForEach(store.providers.filter { $0.status != .notInstalled }) { p in
                HStack(alignment: .top, spacing: 10) {
                    ProviderIcon(id: p.id, symbol: p.symbol, size: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.callout.weight(.medium))
                        switch p.status {
                        case .active(let n): Text("Suivi actif · \(n) séries").font(.caption).foregroundStyle(.green)
                        case .detectedNoData(let r): Text(r).font(.caption).foregroundStyle(.secondary)
                        case .notInstalled: EmptyView()
                        }
                        Text("Lit : " + p.paths.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                Divider()
            }
        }.padding()
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

final class SettingsFlags: ObservableObject { @Published var confirmReset = false }

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @StateObject private var login = LoginState()
    @StateObject private var flags = SettingsFlags()

    var quotaProviders: [ProviderInfo] {
        let ids = Set(store.quotas.map(\.provider)).union(["claude", "codex"])
        return store.providers.filter { ids.contains($0.id) }
    }

    var body: some View {
        TabView {
            general.tabItem { Label("Général", systemImage: "gearshape") }
            alerts.tabItem { Label("Alertes", systemImage: "bell.badge") }
            quota.tabItem { Label("Quotas", systemImage: "gauge.with.dots.needle.67percent") }
            data.tabItem { Label("Données", systemImage: "externaldrive") }
            SourcesView().tabItem { Label("Sources", systemImage: "square.stack.3d.up") }
            about.tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 440)
    }

    var general: some View {
        Form {
            Section("Démarrage") {
                Toggle("Lancer Ember à l'ouverture de session", isOn: $login.enabled)
            }
            Section("Barre des menus") {
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
            Section("Actualisation") {
                Stepper("Toutes les \(store.refreshMinutes) min", value: store.$refreshMinutes, in: 1...30)
                    .onChange(of: store.refreshMinutes) { _, _ in store.schedule() }
                Text("Ember actualise aussi chaque fois que tu reviens sur l'app.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    var alerts: some View {
        Form {
            Section("Budget mensuel") {
                HStack {
                    Text("Budget (USD)")
                    Spacer()
                    TextField("0 = désactivé", value: store.$monthlyBudget, format: .number).frame(width: 110).multilineTextAlignment(.trailing)
                }
                Text("Notification à 80 % puis à 100 % du budget. Prévision de fin de mois : \(money(store.monthProjection)).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Quotas") {
                Picker("Prévenir sous", selection: store.$quotaAlert) {
                    Text("Jamais").tag(0)
                    Text("30 % restants").tag(30)
                    Text("20 % restants").tag(20)
                    Text("10 % restants").tag(10)
                    Text("5 % restants").tag(5)
                }
                Text("Une seule notification par fenêtre (5 h, hebdomadaire…), la première fois que le seuil est franchi.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Envoyer une notification de test") {
                    store.notify("Ember", "Les notifications fonctionnent.", id: "test-" + UUID().uuidString)
                }
            }
        }.formStyle(.grouped)
    }

    var quota: some View {
        Form {
            Section("Quota Claude en direct (optionnel)") {
                Toggle("Lire le quota réel depuis le compte Claude", isOn: store.$liveClaude)
                Text("Activé par défaut. Ember lit le jeton de Claude Code dans ton trousseau (lecture seule, macOS peut demander l'autorisation la première fois) et interroge api.anthropic.com. Il ne renouvelle jamais le jeton et n'écrit jamais dans le trousseau. Le quota n'est connu que pour le présent : la courbe du début de la fenêtre en cours est reconstituée à partir de ta consommation Claude Code et mise à l'échelle sur le niveau réel.")
                    .font(.caption).foregroundStyle(.secondary)
                if !store.liveStatus.isEmpty { Label(store.liveStatus, systemImage: "info.circle").font(.caption) }
            }
        }.formStyle(.grouped)
    }

    var data: some View {
        Form {
            Section("Fichiers") {
                Button("Ouvrir le dossier de données") { NSWorkspace.shared.open(URL(fileURLWithPath: Paths.support)) }
                Button("Modifier les prix des modèles…") {
                    let f = Paths.support + "/pricing-overrides.json"
                    if !FileManager.default.fileExists(atPath: f) {
                        try? "{\n  \"mon-modele\": [3.0, 15.0, 0.3, 3.75]\n}\n".write(toFile: f, atomically: true, encoding: .utf8)
                    }
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)])
                }
                Text("Prix en USD par million de tokens : [entrée, sortie, cache lu, cache écrit]. Pris en compte au prochain lancement.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Export") {
                Button("Exporter tout en CSV…") {
                    if let u = store.exportCSV() { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                }
            }
            Section("Réinitialiser") {
                Button("Effacer l'historique de quota et le cache…", role: .destructive) { flags.confirmReset = true }
                Text("Les journaux des IA ne sont jamais touchés : Ember reconstruit tout au prochain scan.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
