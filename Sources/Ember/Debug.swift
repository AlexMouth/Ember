import AppKit
import SwiftUI

/// Diagnostic entry points, triggered from the command line:
///   Ember --dump              prints per-provider totals and exits
///   Ember --snapshot <dir>    renders the main screens to PNG files and exits
extension EmberApp {
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
                        SnapshotMode.on = true
                        let ui = DashState()
                        @MainActor func save<V: View>(_ v: V, _ name: String, w: CGFloat, dark: Bool = true) {
                            let r = ImageRenderer(content: v.environmentObject(store).frame(width: w)
                                .padding(0).background(dark ? Color(white: 0.11) : Color(white: 0.96))
                                .environment(\.colorScheme, dark ? .dark : .light))
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
                        save(SettingsView(only: "alerts").frame(height: 480), "settings-alerts", w: 600)
                        save(SettingsView(only: "general").frame(height: 480), "settings-general", w: 600)
                        save(SourcesView().frame(height: 480), "sources", w: 600)
                        save(MenuBarView(), "popover-general-light", w: 372, dark: false)
                        save(SettingsView(only: "alerts").frame(height: 480), "settings-alerts-light", w: 600, dark: false)
                        exit(0)
                    }
                }
            }
        }
    }
}
