import AppKit
import SwiftUI

// MARK: - Pages

final class SettingsFlags: ObservableObject {
    /// `--settings-confirm-reset` opens the reset sheet at launch (used for screenshots).
    @Published var confirmReset = CommandLine.arguments.contains("--settings-confirm-reset")
    /// `--settings-bottom` scrolls the page to its end at launch (used for screenshots).
    let startAtBottom = CommandLine.arguments.contains("--settings-bottom")
    /// Word typed in the reset sheet; the Erase button stays disabled until it matches.
    @Published var resetTyped = ""
    /// Result of the last reset, shown under the Danger zone (nil = nothing done yet).
    @Published var resetDone: Bool? = nil
    @Published var pricesAllTime = false
    @Published var pricesReloaded = false
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
        case .data: "Données et prix"
        case .sources: "Sources"
        case .about: "À propos"
        }
    }
    var subtitle: String {
        switch self {
        case .general: "Démarrage et fréquence d'actualisation."
        case .menuBar: "Ce qu'Ember affiche à côté de la flamme."
        case .alerts: "Budget mensuel et seuils de quota."
        case .claude: "Lecture du quota réel de ton abonnement Claude."
        case .data: "Prix appliqués à chaque modèle, export et historique."
        case .sources: "Les IA détectées sur ce Mac et les fichiers lus."
        case .about: "Version, mises à jour et confidentialité."
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .menuBar: "menubar.rectangle"
        case .alerts: "bell.badge.fill"
        case .claude: "key.fill"
        case .data: "dollarsign.circle.fill"
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
        case .data: .green
        case .sources: .indigo
        case .about: .gray
        }
    }
}

/// System Settings–style icon: white glyph on a rounded colour tile.
struct SettingsIcon: View {
    let page: SettingsPage
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: page.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(page.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

// MARK: - Building blocks

/// Rounded group of rows separated by hairlines, with an optional title and footnote.
struct SettingsGroup<Content: View, Accessory: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if title != nil || Accessory.self != EmptyView.self {
                HStack(alignment: .firstTextBaseline) {
                    if let title { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
                    Spacer()
                    accessory
                }
                .padding(.horizontal, 4)
            }
            _VariadicView.Tree(Divided()) { content }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    struct Divided: _VariadicView_UnaryViewRoot {
        @MainActor func body(children: _VariadicView.Children) -> some View {
            let last = children.last?.id
            VStack(spacing: 0) {
                ForEach(children) { child in
                    child
                    if child.id != last { Divider().padding(.leading, 14) }
                }
            }
        }
    }
}

extension SettingsGroup where Accessory == EmptyView {
    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, footer: footer, accessory: { EmptyView() }, content: content)
    }
}

/// One line of a group: optional symbol, title, explanation underneath, control on the right.
struct SettingsRow<Control: View>: View {
    var symbol: String? = nil
    var tint: Color = .secondary
    let title: String
    var detail: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(tint).frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}

extension SettingsRow where Control == EmptyView {
    init(symbol: String? = nil, tint: Color = .secondary, title: String, detail: String? = nil) {
        self.init(symbol: symbol, tint: tint, title: title, detail: detail) { EmptyView() }
    }
}

/// Real sidebar material (follows the desktop and the window's active state).
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: - Window

/// Settings window: sidebar of panes and a scrolling page with a header, like System Settings.
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @StateObject private var login = LoginState()
    @StateObject private var flags = SettingsFlags()

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Divider()
            let p = flags.pane ?? .general
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header(p)
                        page(p)
                        Color.clear.frame(height: 0).id("bottom")
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 32).padding(.top, 40).padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                }
                .onAppear {
                    if flags.startAtBottom {
                        for t in [1.5, 3.5, 6.0] {  // the model table fills in late
                            DispatchQueue.main.asyncAfter(deadline: .now() + t) { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                    }
                }
            }
            .id(p)  // back to the top when switching panes
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .frame(minWidth: 780, idealWidth: 880, minHeight: 540, idealHeight: 640)
        .sheet(isPresented: $flags.confirmReset, onDismiss: { flags.resetTyped = "" }) {
            ResetConfirmSheet(flags: flags).environmentObject(store)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ember").font(.headline)
                    Text("Version \(Updater.shared.current)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18).padding(.top, 44).padding(.bottom, 10)
            List(SettingsPage.allCases, selection: $flags.pane) { p in
                Label { Text(p.title) } icon: { SettingsIcon(page: p) }
                    .padding(.vertical, 2)
                    .tag(p)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(SidebarMaterial().ignoresSafeArea())
    }

    private func header(_ p: SettingsPage) -> some View {
        HStack(spacing: 14) {
            SettingsIcon(page: p, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.title).font(.title2.weight(.bold))
                Text(p.subtitle).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func page(_ p: SettingsPage) -> some View {
        switch p {
        case .general: GeneralPane(login: login)
        case .menuBar: MenuBarPane()
        case .alerts: AlertsPane()
        case .claude: ClaudePane()
        case .data: DataPane(flags: flags)
        case .sources: SourcesPane()
        case .about: AboutPane()
        }
    }
}

// MARK: - Général

private struct GeneralPane: View {
    @EnvironmentObject var store: Store
    @ObservedObject var login: LoginState

    var body: some View {
        SettingsGroup("Démarrage") {
            SettingsRow(symbol: "power", title: "Ouvrir Ember à l'ouverture de session",
                        detail: "Ember se lance discrètement dans la barre des menus, sans fenêtre.") {
                Toggle("", isOn: $login.enabled).labelsHidden().toggleStyle(.switch)
            }
        }
        SettingsGroup("Actualisation", footer: "Ember actualise aussi à chaque ouverture du menu (au plus une fois par minute).") {
            SettingsRow(symbol: "arrow.clockwise", title: "Fréquence",
                        detail: "Relit les journaux de tes IA et le quota Claude.") {
                Picker("", selection: store.$refreshMinutes) {
                    ForEach([1, 2, 5, 10, 15, 30], id: \.self) { Text("Toutes les \($0) min").tag($0) }
                }
                .labelsHidden().fixedSize()
                .onChange(of: store.refreshMinutes) { _, _ in store.schedule() }
            }
            SettingsRow(symbol: "clock", title: "Dernière actualisation",
                        detail: store.lastRefresh.map { $0.formatted(.relative(presentation: .named)).capitalizedFirst } ?? "Jamais") {
                if store.refreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Actualiser maintenant") { store.refresh() }
                }
            }
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Barre des menus

private struct MenuBarPane: View {
    @EnvironmentObject var store: Store

    var quotaProviders: [ProviderInfo] {
        let ids = Set(store.quotas.map(\.provider)).union(["claude", "codex"])
        return store.providers.filter { ids.contains($0.id) }
    }

    var body: some View {
        MenuBarPreview()
        SettingsGroup("Contenu") {
            SettingsRow(symbol: "textformat", title: "Texte affiché") {
                Picker("", selection: store.$menuMode) {
                    Text("Quota restant, sinon dépense").tag("auto")
                    Text("Quota restant").tag("quota")
                    Text("Dépense du jour").tag("cost")
                    Text("Aucun (flamme seule)").tag("icon")
                }
                .labelsHidden().fixedSize()
            }
            if store.menuMode == "auto" || store.menuMode == "quota" {
                SettingsRow(symbol: "gauge.with.dots.needle.50percent", title: "Quota suivi",
                            detail: "Sert aussi à la couleur de la flamme et à la jauge.") {
                    Picker("", selection: store.$menuProvider) {
                        ForEach(quotaProviders) { p in Text(p.name).tag(p.id) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
        }
        SettingsGroup("Apparence") {
            SettingsRow(symbol: "flame.fill", tint: .green, title: "Flamme colorée selon le quota",
                        detail: "Verte tant que tout va bien, orange dès 80 % utilisés, rouge dès 95 %.") {
                Toggle("", isOn: store.$menuTint).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(symbol: "chart.bar.fill", title: "Mini-jauge du quota restant",
                        detail: "Petite barre verticale à droite de la flamme.") {
                Toggle("", isOn: store.$menuGauge).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

/// Live preview of the menu-bar item, drawn in a fake menu bar.
struct MenuBarPreview: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let used = primaryQuota(store.quotas(for: store.menuProvider))?.usedPercent
        let level = store.menuTint && used != nil ? AppDelegate.alertLevel(used: used) : nil
        let gauge = store.menuGauge ? used.map { (100 - min(max($0, 0), 100)) / 100 } : nil
        let t = AppDelegate.current?.menuLabel ?? ""
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Spacer()
                HStack(spacing: 4) {
                    if let img = AppDelegate.flame(level: level, remaining: gauge) {
                        Image(nsImage: img).renderingMode(level == nil ? .template : .original)
                    }
                    if !t.isEmpty { Text(t).monospacedDigit() }
                }
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.primary.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text(Date().formatted(.dateTime.weekday(.abbreviated).hour().minute()))
            }
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(.ultraThinMaterial)
            Spacer(minLength: 0)
        }
        .frame(height: 92)
        .background(
            LinearGradient(colors: scheme == .dark ? [Color(red: 0.16, green: 0.2, blue: 0.36), Color(red: 0.36, green: 0.18, blue: 0.3)]
                                                   : [Color(red: 0.62, green: 0.75, blue: 0.95), Color(red: 0.95, green: 0.74, blue: 0.68)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .overlay(alignment: .bottomLeading) {
            Text("Aperçu en direct").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85)).padding(10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aperçu de la barre des menus : \(t.isEmpty ? "flamme seule" : t)")
    }
}

// MARK: - Notifications

private struct AlertsPane: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let budget = store.monthlyBudget
        let spent = store.monthCost
        SettingsGroup("Budget mensuel", footer: "Notification à 80 % puis à 100 % du budget. Laisse 0 pour désactiver l'alerte.") {
            SettingsRow(symbol: "dollarsign.circle", title: "Budget", detail: "En équivalent API (USD).") {
                TextField("Aucun", value: store.$monthlyBudget, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 110)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Ce mois-ci").foregroundStyle(.secondary)
                    Spacer()
                    Text(money(spent)).font(.title3.weight(.semibold)).monospacedDigit()
                    if budget > 0 { Text("sur \(money(budget))").foregroundStyle(.secondary) }
                }
                if budget > 0 {
                    let f = min(spent / budget, 1)
                    ProgressView(value: f).tint(f >= 1 ? .red : f >= 0.8 ? .orange : .green)
                }
                Text("Projection en fin de mois : \(money(store.monthProjection))").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        SettingsGroup("Quotas d'abonnement", footer: "Une seule notification par fenêtre (5 h, hebdomadaire…) et par seuil.") {
            SettingsRow(symbol: "exclamationmark.triangle", title: "Prévenir quand il reste") {
                Picker("", selection: store.$quotaAlert) {
                    Text("Jamais").tag(0)
                    ForEach([30, 20, 10, 5], id: \.self) { Text("\($0) %").tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            SettingsRow(symbol: "xmark.octagon", title: "Prévenir quand la limite est atteinte") {
                Toggle("", isOn: store.$quotaAlertFull).labelsHidden().toggleStyle(.switch)
            }
        }
        SettingsGroup {
            SettingsRow(symbol: "bell", title: "Tester les notifications",
                        detail: "Si rien n'apparaît, autorise Ember dans Réglages Système › Notifications.") {
                Button("Envoyer") { store.notify("Ember", "Les notifications fonctionnent.", id: "test-" + UUID().uuidString) }
            }
        }
    }
}

// MARK: - Compte Claude

private struct ClaudePane: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if store.liveClaude { statusCard }
        SettingsGroup("Quota en direct",
                      footer: "Ember lit le jeton de Claude Code dans le trousseau, en lecture seule, et interroge api.anthropic.com. Il ne le renouvelle jamais : c'est Claude Code qui le fait quand il tourne. Désactivé, le quota est estimé à partir de ta consommation.") {
            SettingsRow(symbol: "antenna.radiowaves.left.and.right", title: "Lire le quota réel du compte Claude") {
                Toggle("", isOn: store.$liveClaude).labelsHidden().toggleStyle(.switch)
            }
            if store.liveClaude, let e = store.liveTokenExpiry {
                SettingsRow(symbol: "key", title: e < Date() ? "Jeton expiré depuis" : "Jeton valide jusqu'à",
                            detail: e.formatted(date: .complete, time: .shortened).capitalizedFirst)
            }
        }
    }

    private var statusCard: some View {
        let (color, symbol, title, detail): (Color, String, String, String) = switch store.liveProblem {
        case nil where store.liveStatus == "OK":
            (.green, "checkmark", "Connecté", "Le quota affiché est celui de ton compte, lu en direct.")
        case nil:
            (.gray, "hourglass", "En attente", "Première lecture en cours…")
        case .expired:
            (.orange, "clock.arrow.circlepath", "Jeton expiré",
             "Le jeton de Claude Code a expiré. Lancer Claude Code suffit à le renouveler ; en attendant, le quota est estimé.")
        case .signedOut:
            (.red, "xmark", "Déconnecté", "Anthropic refuse le jeton : reconnecte-toi avec /login dans Claude Code.")
        case .other:
            (.orange, "wifi.exclamationmark", "Injoignable", store.liveStatus)
        }
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if store.liveProblem != nil {
                    HStack {
                        if store.liveProblem == .signedOut {
                            Button("Se reconnecter (/login)") { ClaudeLink.open(login: true) }.emberProminent().tint(.orange)
                        } else {
                            Button("Lancer Claude Code") { ClaudeLink.open(login: false) }.emberProminent().tint(.orange)
                        }
                        Button("Réessayer") { store.refresh() }
                    }
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.3)))
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

// MARK: - Données et prix

/// One model actually used, with the price Ember applies to it.
struct ModelPriceRow: Identifiable {
    let model: String
    var tokens = 0
    var cost = 0.0
    var providers: Set<String> = []
    var price: PriceResult?
    var id: String { model }

    /// Groups records by model, most expensive first.
    static func rows(_ rs: [UsageRecord], cost: (UsageRecord) -> Double) -> [ModelPriceRow] {
        var acc: [String: ModelPriceRow] = [:]
        for r in rs where !r.model.isEmpty && r.model != "<synthetic>" && r.totalTokens > 0 {
            acc[r.model, default: ModelPriceRow(model: r.model)].tokens += r.totalTokens
            acc[r.model]!.cost += cost(r)
            acc[r.model]!.providers.insert(r.provider)
        }
        return acc.values.map { var v = $0; v.price = Pricing.shared.lookup(v.model); return v }
            .sorted { ($0.cost, $0.tokens, $1.model) > ($1.cost, $1.tokens, $0.model) }
    }
}

/// USD per million tokens, short: $15, $3.75, $0.30, $0.075.
func perMillion(_ v: Double) -> String {
    if v == 0 { return "$0" }
    if v >= 1, v.rounded() == v { return String(format: "$%.0f", v) }
    let cents = v * 100
    return String(format: abs(cents - cents.rounded()) < 1e-9 ? "$%.2f" : "$%.3f", v)
}

/// Badge describing where a model's price comes from.
struct PriceOrigin: View {
    let model: String
    let result: PriceResult?

    /// Table key without its vendor prefix, shown only when it differs from the model name.
    private func entry(_ key: String) -> String? {
        let short = key.split(separator: "/").last.map(String.init) ?? key
        let m = model.lowercased()
        return m == short || m.hasPrefix(short + "-20") || m == short + "[1m]" ? nil : short
    }

    var body: some View {
        let (c, s, t): (Color, String, String) = {
            guard let r = result else { return (.red, "questionmark.circle.fill", "Sans prix : compté 0 $") }
            let short = r.key.split(separator: "/").last.map(String.init) ?? r.key
            if r.approximate { return (.orange, "approximately.equal", "Approché : prix de \(short)") }
            let suffix = entry(r.key).map { " · \($0)" } ?? ""
            switch r.source {
            case .custom: return (.purple, "pencil.circle.fill", "Personnalisé" + suffix)
            case .modelsDev: return (.blue, "globe", "models.dev" + suffix)
            case .builtin: return (.teal, "shippingbox.fill", "Intégré à Ember" + suffix)
            }
        }()
        Label { Text(t).lineLimit(1).truncationMode(.middle) } icon: { Image(systemName: s) }
            .font(.caption).foregroundStyle(c)
    }
}

private struct DataPane: View {
    @EnvironmentObject var store: Store
    @ObservedObject var flags: SettingsFlags
    private var allTime: Bool { flags.pricesAllTime }

    var body: some View {
        let recs = allTime ? store.records : store.filtered(.month)
        let rows = ModelPriceRow.rows(recs, cost: store.cost)
        let unpriced = rows.filter { $0.price == nil && $0.tokens > 0 }
        let approx = rows.filter { $0.price?.approximate == true }

        HStack(spacing: 10) {
            tile(money(rows.reduce(0) { $0 + $1.cost }), allTime ? "Dépense totale" : "Dépense sur 30 jours", .green)
            tile(compact(rows.reduce(0) { $0 + $1.tokens }), "Tokens", .blue)
            tile("\(rows.count)", rows.count > 1 ? "Modèles utilisés" : "Modèle utilisé", .indigo)
            tile("\(unpriced.count + approx.count)", "Prix à vérifier", unpriced.isEmpty && approx.isEmpty ? .secondary : .orange)
        }

        SettingsGroup(title: "Prix des modèles utilisés",
                      footer: "Prix en USD par million de tokens. Ordre de priorité : tes prix personnalisés, puis models.dev, puis les prix intégrés à Ember, puis le prix d'un modèle de la même famille (≈). Un modèle sans prix est compté 0 $.") {
            Picker("", selection: $flags.pricesAllTime) {
                Text("30 jours").tag(false)
                Text("Tout").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        } content: {
            if rows.isEmpty && store.records.isEmpty && store.refreshing {
                ProgressView("Lecture des journaux…").controlSize(.small)
                    .frame(maxWidth: .infinity).padding(20)
            } else if rows.isEmpty {
                Text("Aucune consommation sur cette période.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(20)
            } else {
                priceTable(rows)
            }
        }

        SettingsGroup("Modifier les prix",
                      footer: "Format : {\"nom-du-modele\": [entrée, sortie, cache lu, cache écrit]}, en USD par million de tokens, nom insensible à la casse. Tes prix remplacent tous les autres.") {
            SettingsRow(symbol: "pencil", tint: .purple, title: "Mes prix personnalisés",
                        detail: "pricing-overrides.json, dans le dossier de données d'Ember.") {
                Button("Ouvrir…") {
                    if let u = Pricing.shared.ensureOverridesFile() { NSWorkspace.shared.open(u) }
                }
            }
            SettingsRow(symbol: "arrow.triangle.2.circlepath", tint: .purple, title: "Appliquer les modifications",
                        detail: flags.pricesReloaded ? "Prix rechargés, coûts recalculés." : "Relit le fichier et recalcule tous les coûts.") {
                Button("Recharger") { store.reloadPrices(); flags.pricesReloaded = true }
            }
            SettingsRow(symbol: "globe", tint: .blue, title: "Source des prix publics",
                        detail: priceSourcesText) {
                Link("models.dev", destination: URL(string: "https://models.dev")!)
            }
        }

        SettingsGroup("Fichiers") {
            SettingsRow(symbol: "folder", title: "Dossier de données", detail: "Historique de quota, cache et prix personnalisés.") {
                Button("Afficher dans le Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: Paths.support)) }
            }
            SettingsRow(symbol: "square.and.arrow.up", title: "Exporter toute la consommation", detail: "Un fichier CSV : jour, source, modèle, projet, tokens, coût.") {
                Button("Exporter en CSV…") {
                    if let u = store.exportCSV() { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                }
            }
        }

        DangerZone(flags: flags)
    }

    private var priceSourcesText: String {
        let c = Pricing.shared.counts
        var t = "\(c[.modelsDev] ?? 0) modèles tarifés par models.dev"
        if let b = c[.builtin], b > 0 { t += ", \(b) par Ember" }
        if let u = c[.custom], u > 0 { t += ", \(u) par toi" }
        return t + "."
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color == .secondary ? .primary : color)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func priceTable(_ rows: [ModelPriceRow]) -> some View {
        let w: CGFloat = 60
        return Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 0) {
            GridRow {
                Text("Modèle").gridColumnAlignment(.leading)
                Text("Entrée"); Text("Sortie"); Text("Cache lu"); Text("Cache écrit"); Text(allTime ? "Coût" : "Coût 30 j")
            }
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .padding(.vertical, 8)
            ForEach(rows) { r in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            ForEach(r.providers.sorted(), id: \.self) { id in
                                if let p = store.providers.first(where: { $0.id == id }) {
                                    ProviderIcon(id: p.id, symbol: p.symbol, size: 14).help(p.name)
                                }
                            }
                            Text(r.model).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        PriceOrigin(model: r.model, result: r.price)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        price(r.price?.price.input)
                        price(r.price?.price.output)
                        price(r.price?.price.cacheRead)
                        price(r.price?.price.cacheWrite)
                    }
                    .frame(width: w, alignment: .trailing)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(money(r.cost)).font(.callout.weight(.semibold))
                        Text(compact(r.tokens) + " tok").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(width: 70, alignment: .trailing)
                }
                .monospacedDigit()
                .padding(.vertical, 8)
                .opacity(r.price == nil ? 0.75 : 1)
            }
        }
        .padding(.horizontal, 14)
    }

    private func price(_ v: Double?) -> some View {
        Text(v.map(perMillion) ?? "—").font(.callout)
            .foregroundStyle(v == nil ? .tertiary : .primary)
            .help("USD par million de tokens")
    }
}

// MARK: - Sources

private struct SourcesPane: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let list = store.providers.filter { $0.status != .notInstalled }
        SettingsGroup(footer: "Ember lit ces fichiers en lecture seule, directement sur ton Mac. Les IA « sans données » sont installées mais ne laissent aucun compteur lisible.") {
            if list.isEmpty {
                Text("Aucune IA détectée pour l'instant.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(20)
            }
            ForEach(list) { p in
                HStack(alignment: .top, spacing: 12) {
                    ProviderIcon(id: p.id, symbol: p.symbol, size: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.name).font(.body.weight(.medium))
                        if case .detectedNoData(let r) = p.status {
                            Text(r).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(p.paths, id: \.self) { path in
                            Text(path).font(.caption.monospaced()).foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 12)
                    switch p.status {
                    case .active(let n):
                        badge("Suivie · \(n) série\(n > 1 ? "s" : "")", .green)
                    case .detectedNoData:
                        badge("Sans données", .secondary)
                    case .notInstalled: EmptyView()
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
        }
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption.weight(.medium)).foregroundStyle(c)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(c.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

// MARK: - À propos

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 88, height: 88)
            Text("Ember").font(.title.weight(.bold))
            Text("Suivi local de la consommation de tes IA de développement").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        SettingsGroup("Mises à jour", footer: "Chaque mise à jour est vérifiée (signature Ed25519) avant d'être installée ; en cas d'échec, l'ancienne version est restaurée.") {
            UpdateRow().padding(.horizontal, 14).padding(.vertical, 12)
        }
        SettingsGroup("Confidentialité") {
            SettingsRow(symbol: "lock.shield", tint: .green, title: "Tout reste sur ton Mac",
                        detail: "Seul le quota Claude en direct contacte api.anthropic.com, avec ton propre jeton, en lecture seule.")
            SettingsRow(symbol: "chevron.left.forwardslash.chevron.right", title: "Code source") {
                Link("GitHub", destination: URL(string: "https://github.com/AlexMouth/Ember")!)
            }
            SettingsRow(symbol: "dollarsign.circle", title: "Prix des modèles") {
                Link("models.dev", destination: URL(string: "https://models.dev")!)
            }
        }
    }
}

// MARK: - Danger zone

/// Destructive actions, set apart in a red-bordered box below everything else.
private struct DangerZone: View {
    @ObservedObject var flags: SettingsFlags

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Zone de danger", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill").font(.system(size: 14)).foregroundStyle(.red).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Effacer l'historique de quota et le cache").fontWeight(.medium)
                        Text("Les courbes de quota des 35 derniers jours seront perdues : elles ne peuvent pas être reconstruites.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    Button(role: .destructive) { flags.resetTyped = ""; flags.confirmReset = true } label: {
                        Text("Effacer…").foregroundStyle(.red)
                    }
                    .accessibilityHint("Ouvre une confirmation avant d'effacer")
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                if let done = flags.resetDone {
                    Divider().padding(.leading, 14)
                    Label(done ? "Effacé. Les fichiers sont dans la Corbeille si tu changes d'avis."
                               : "Certains fichiers n'ont pas pu être déplacés dans la Corbeille.",
                          systemImage: done ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.caption).foregroundStyle(done ? Color.secondary : Color.red)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.red.opacity(0.45), lineWidth: 1))
            Text("Les journaux de tes IA ne sont jamais touchés : la consommation et les coûts se recalculent au prochain scan.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .padding(.top, 12)
    }
}

/// Guard rail before erasing: says exactly what goes and what stays, offers an export first,
/// and only enables the button once the user has typed the confirmation word.
struct ResetConfirmSheet: View {
    static let word = "EFFACER"
    @EnvironmentObject var store: Store
    @ObservedObject var flags: SettingsFlags
    @Environment(\.dismiss) private var dismiss

    private var matches: Bool {
        flags.resetTyped.trimmingCharacters(in: .whitespaces).uppercased() == Self.word
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30)).foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Effacer l'historique de quota ?").font(.title3.weight(.semibold))
                    Text("Cette action ne peut pas être annulée depuis Ember.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                item("xmark.circle.fill", .red, "Historique de quota (35 jours) : perdu, les courbes repartent de zéro.")
                item("arrow.clockwise.circle.fill", .orange, "Cache de lecture : reconstruit au prochain scan, qui sera plus long.")
                item("checkmark.circle.fill", .green, "Journaux de tes IA, réglages et prix personnalisés : conservés.")
                item("trash.circle.fill", .secondary, "Les fichiers (\(ByteCountFormatter.string(fromByteCount: Store.resettableBytes(), countStyle: .file))) vont dans la Corbeille : tu peux encore les récupérer depuis le Finder.")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))

            VStack(alignment: .leading, spacing: 6) {
                Text("Pour confirmer, tape **\(Self.word)** ci-dessous.").font(.callout)
                TextField(Self.word, text: $flags.resetTyped)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if matches { erase() } }
                    .accessibilityLabel("Mot de confirmation")
            }

            HStack {
                Button("Exporter en CSV d'abord…") {
                    if let u = store.exportCSV() { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                }
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) { erase() } label: {
                    Text("Effacer définitivement")
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(!matches)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private func item(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        Label {
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }

    private func erase() {
        flags.resetDone = store.resetHistory()
        dismiss()
    }
}
