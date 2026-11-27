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
