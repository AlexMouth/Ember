import SwiftUI

@main
struct EmberApp: App {
    @StateObject private var store = Store()

    init() {
        if CommandLine.arguments.contains("--dump") { Self.dump(); exit(0) }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Self.snapshot(dir: CommandLine.arguments[i + 1])
        }
    }

    /// Headless scan for diagnostics: prints per-provider totals and exits.
    static func dump() {
        let cache = FileCache()
        var outs: [(UsageProvider, ScanOutput)] = []
        for p in Discovery.providers() where p.installed() { outs.append((p, p.scan(cache: cache))) }
        cache.save()
        let (recs, _) = Store.aggregate(outs)
        for (p, o) in outs {
            let rs = recs.filter { $0.provider == p.id }
            let cost = rs.reduce(0) { $0 + Pricing.shared.cost($1) }
            print(String(format: "%-16@ entries=%5d records=%4d tokens=%@ cost=$%.2f quotas=%@", p.name as NSString, o.entries.count, rs.count,
                         compact(rs.reduce(0) { $0 + $1.totalTokens }) as NSString, cost,
                         o.quotas.map { "\($0.label):\(Int($0.usedPercent))%" }.joined(separator: ",") as NSString))
        }
    }

    /// Renders the main screens to PNG files for visual checks without screen-recording permission.
    static func snapshot(dir: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            MainActor.assumeIsolated {
                let store = Store()
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    MainActor.assumeIsolated {
                        let ui = DashState()
                        @MainActor func save<V: View>(_ v: V, _ name: String, w: CGFloat) {
                            let r = ImageRenderer(content: v.environmentObject(store).frame(width: w)
                                .padding(0).background(Color(white: 0.11)).environment(\.colorScheme, .dark))
                            r.scale = 2
                            if let img = r.nsImage, let t = img.tiffRepresentation, let b = NSBitmapImageRep(data: t),
                               let png = b.representation(using: .png, properties: [:]) {
                                try? png.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
                            }
                        }
                        save(MenuBarView(), "popover-general", w: 372)
                        save(MenuBarView(tab: "claude"), "popover-claude", w: 372)
                        save(OverviewPage(data: store.filtered(.all), ui: ui).padding(20), "overview", w: 980)
                        save(ProviderPage(id: "claude", data: store.filtered(.all, provider: "claude"), ui: ui).padding(20), "claude", w: 980)
                        save(ProviderPage(id: "codex", data: store.filtered(.all, provider: "codex"), ui: ui).padding(20), "codex", w: 980)
                        exit(0)
                    }
                }
            }
        }
    }

    var menuLabel: String {
        switch store.menuMode {
        case "icon": return ""
        case "cost": return money(store.todayCost)
        default:
            if let q = primaryQuota(store.quotas(for: store.menuProvider)) { return String(format: "%.0f %%", 100 - q.usedPercent) }
            return store.menuMode == "quota" ? "—" : money(store.todayCost)
        }
    }

    var body: some Scene {
        Window("Ember", id: "dashboard") {
            DashboardView().environmentObject(store)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 900, height: 620)

        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                if !menuLabel.isEmpty { Text(menuLabel).monospacedDigit() }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}
