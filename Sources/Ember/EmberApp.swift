import AppKit
import Combine
import SwiftUI

@main
struct EmberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

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

    var body: some Scene {
        Settings {
            SettingsView().environmentObject(delegate.store)
        }
    }
}

/// Owns the menu-bar item (popover anchored right under the icon) and the dashboard window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var dashboard: NSWindow?
    private var bag = Set<AnyCancellable>()

    var menuLabel: String {
        switch store.menuMode {
        case "icon": return ""
        case "cost": return money(store.todayCost)
        default:
            if let q = primaryQuota(store.quotas(for: store.menuProvider)) { return String(format: "%.0f %%", 100 - q.usedPercent) }
            return store.menuMode == "quota" ? "—" : money(store.todayCost)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        it.button?.target = self
        it.button?.action = #selector(toggle)
        it.button?.imagePosition = .imageLeading
        item = it

        let host = NSHostingController(rootView: MenuBarView(
            openDashboard: { [weak self] in self?.showDashboard() },
            openSettings: { [weak self] in self?.showSettings() }
        ).environmentObject(store))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true

        store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateLabel() }
        }.store(in: &bag)
        updateLabel()
        Updater.shared.startAutoCheck()
    }

    private func updateLabel() {
        guard let b = item?.button else { return }
        b.image = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Ember")
        let t = menuLabel
        b.attributedTitle = NSAttributedString(string: t.isEmpty ? "" : " " + t,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)])
    }

    @objc private func toggle() {
        guard let b = item?.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func showDashboard() {
        popover.performClose(nil)
        if dashboard == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: DashboardView().environmentObject(store)))
            w.title = "Ember"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 900, height: 620))
            w.isReleasedWhenClosed = false
            w.center()
            dashboard = w
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboard?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
