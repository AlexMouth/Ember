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

    var body: some Scene {
        Settings {
            SettingsView().environmentObject(delegate.store)
        }
    }
}

/// Owns the menu-bar item (popover anchored right under the icon) and the dashboard window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The running delegate (NSApp.delegate is SwiftUI's adaptor, not this class).
    private(set) static weak var current: AppDelegate?
    let store = Store()
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var dashboard: NSWindow?
    private var settings: NSWindow?
    private var shownTitle: String?
    private var shownIcon: String?
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

    func applicationWillTerminate(_ notification: Notification) { store.flush() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
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
        if CommandLine.arguments.contains("--open-dashboard") { showDashboard() }
    }

    /// Called on every store change; only touches the button when the text actually changes,
    /// so the menu bar is not redrawn for each published property.
    private func updateLabel() {
        guard let b = item?.button else { return }
        let used = primaryQuota(store.quotas(for: store.menuProvider))?.usedPercent
        let level = store.menuTint && used != nil ? Self.alertLevel(used: used) : nil
        // Gauge drawn in 5 % steps: the icon is only redrawn when it would visibly change.
        let gauge = store.menuGauge ? used.map { (100 - min(max($0, 0), 100)) / 100 } : nil
        let step = gauge.map { Int(($0 * 20).rounded()) }
        let key = "\(level ?? -1)|\(step ?? -1)"
        if key != shownIcon {
            shownIcon = key
            b.image = Self.flame(level: level, remaining: step.map { Double($0) / 20 })
            b.setAccessibilityLabel(used.map { String(format: "Ember, %.0f %% du quota restant", 100 - $0) } ?? "Ember")
        }
        let t = menuLabel
        guard t != shownTitle else { return }
        shownTitle = t
        b.attributedTitle = NSAttributedString(string: t.isEmpty ? "" : " " + t,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)])
    }

    /// 0 = normal, 1 = above 80 % used, 2 = above 95 % used.
    nonisolated static func alertLevel(used: Double?) -> Int {
        guard let u = used else { return 0 }
        return u >= 95 ? 2 : u >= 80 ? 1 : 0
    }

    /// Menu-bar flame. `level` nil = template (follows the menu bar's appearance), otherwise
    /// green / orange / red. `remaining` (0...1) adds a small vertical gauge on the right.
    static func flame(level: Int?, remaining: Double? = nil) -> NSImage? {
        guard let base = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Ember") else { return nil }
        let color: NSColor? = level.map { [NSColor.systemGreen, .systemOrange, .systemRed][min(max($0, 0), 2)] }
        let flame = color.flatMap { base.withSymbolConfiguration(.init(paletteColors: [$0])) } ?? base
        guard let remaining else {
            flame.isTemplate = color == nil
            return flame
        }
        let fs = base.size, gw: CGFloat = 4, gap: CGFloat = 3
        let h = max(fs.height, 15)
        let img = NSImage(size: NSSize(width: fs.width + gap + gw, height: h), flipped: false) { _ in
            flame.draw(in: NSRect(x: 0, y: (h - fs.height) / 2, width: fs.width, height: fs.height))
            let ink = color ?? .black
            let track = NSRect(x: fs.width + gap, y: 1, width: gw, height: h - 2)
            ink.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: track, xRadius: gw / 2, yRadius: gw / 2).fill()
            let fill = NSRect(x: track.minX, y: track.minY, width: gw, height: max(gw, track.height * remaining))
            ink.setFill()
            NSBezierPath(roundedRect: fill, xRadius: gw / 2, yRadius: gw / 2).fill()
            return true
        }
        img.isTemplate = color == nil
        img.accessibilityDescription = "Ember"
        return img
    }

    @objc private func toggle() {
        guard let b = item?.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        if Date().timeIntervalSince(store.lastRefresh ?? .distantPast) > 60 { store.refresh() }
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
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isOpaque = false
            w.backgroundColor = .clear
            w.center()
            dashboard = w
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboard?.makeKeyAndOrderFront(nil)
    }

    /// Settings live in a window Ember owns: the popover and dashboard are AppKit-hosted, outside
    /// any SwiftUI scene, where SettingsLink/openSettings do not work reliably.
    func showSettings() {
        popover.performClose(nil)
        if settings == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environmentObject(store)))
            w.title = "Réglages Ember"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            w.center()
            settings = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }
}
