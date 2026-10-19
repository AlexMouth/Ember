import Charts
import SwiftUI

let providerColors: [String: Color] = [
    "claude": .orange, "codex": .green, "gemini": .blue, "kiro": .purple, "cursor": .mint,
]
func color(for provider: String) -> Color { providerColors[provider] ?? .gray }


/// Native-feeling grouped surface: system control background, hairline border, continuous corners.
struct InPopoverKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var inPopover: Bool {
        get { self[InPopoverKey.self] }
        set { self[InPopoverKey.self] = newValue }
    }
}

struct CardStyle: ViewModifier {
    var radius: CGFloat = 12
    @Environment(\.inPopover) private var inPopover
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if inPopover {
            // Translucent tile that lets the popover's vibrancy through instead of a heavy opaque block.
            content
                .background(Color.primary.opacity(0.07), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        } else {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 1.5, y: 0.5)
        }
    }
}
extension View { func card(radius: CGFloat = 12) -> some View { modifier(CardStyle(radius: radius)) } }

let pagePadding: CGFloat = 24
let gridSpacing: CGFloat = 16


final class HoverState: ObservableObject { @Published var date: Date? }

/// Transparent layer over a chart that reports the date under the pointer.
func hoverLayer(_ proxy: ChartProxy, _ hover: HoverState) -> some View {
    GeometryReader { g in
        Rectangle().fill(Color.clear).contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    guard let pf = proxy.plotFrame else { return }
                    hover.date = proxy.value(atX: loc.x - g[pf].origin.x, as: Date.self)
                case .ended: hover.date = nil
                }
            }
    }
}

struct HoverTip: View {
    let lines: [(String, String)]
    var title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(lines.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Text(lines[i].0).font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Text(lines[i].1).font(.caption.weight(.semibold).monospacedDigit())
                }
            }
        }
        .padding(8).frame(minWidth: 130)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

struct Badge: View {
    let text: String
    let good: Bool
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(good ? Color.green : Color.red).frame(width: 6, height: 6)
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(good ? Color.green : Color.red)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background((good ? Color.green : Color.red).opacity(0.14), in: Capsule())
    }
}

func aheadText(_ i: QuotaInfo) -> String {
    String(format: i.ahead >= 0 ? "+%.1f pts d'avance" : "%.1f pts de retard", i.ahead)
}

struct QuotaChart: View {
    let info: QuotaInfo
    var height: CGFloat = 160
    @StateObject private var hover = HoverState()

    struct P: Identifiable { let id: Int; let t: Date; let v: Double; let pace: Double }

    var pts: [P] {
        info.series.enumerated().map { P(id: $0.offset, t: $0.element.0, v: $0.element.1, pace: info.pace(at: $0.element.0)) }
    }

    /// End of the projected line: the reset, or the moment the quota would hit zero if sooner.
    var projEnd: (Date, Double)? {
        guard let p = info.projected else { return nil }
        if p >= 0 { return (info.end, p) }
        let used = max(info.q.usedPercent, 0.01)
        let secsUsed = info.now.timeIntervalSince(info.start)
        let toZero = info.remaining / (used / max(secsUsed, 1))
        return (min(info.end, info.now.addingTimeInterval(toZero)), 0)
    }

    struct HS { let t: Date; let v: Double; let pace: Double; let future: Bool }

    /// Sample under the pointer: measured before now, projected after.
    func hoverSample(_ h: Date) -> HS? {
        let t = min(max(h, info.start), info.end)
        if t > info.now {
            guard let e = projEnd else { return nil }
            let span = e.0.timeIntervalSince(info.now)
            let f = span > 0 ? min(t.timeIntervalSince(info.now) / span, 1) : 1
            return HS(t: t, v: info.remaining + (e.1 - info.remaining) * f, pace: info.pace(at: t), future: true)
        }
        guard let p = pts.min(by: { abs($0.t.timeIntervalSince(t)) < abs($1.t.timeIntervalSince(t)) }),
              abs(p.t.timeIntervalSince(t)) < info.end.timeIntervalSince(info.start) / 12 else { return nil }
        return HS(t: p.t, v: p.v, pace: p.pace, future: false)
    }

    var body: some View {
        let fmt: Date.FormatStyle = info.q.windowMinutes >= 1440 ? .dateTime.day().month(.abbreviated) : .dateTime.hour().minute()
        Chart {
            ForEach(pts) { p in
                AreaMark(x: .value("t", p.t), yStart: .value("a", p.pace), yEnd: .value("b", max(p.v, p.pace)), series: .value("s", "ahead"))
                    .foregroundStyle(Color.green.opacity(0.28))
                AreaMark(x: .value("t", p.t), yStart: .value("a", min(p.v, p.pace)), yEnd: .value("b", p.pace), series: .value("s", "behind"))
                    .foregroundStyle(Color.red.opacity(0.25))
            }
            LineMark(x: .value("t", info.start), y: .value("v", 100), series: .value("s", "pace"))
                .foregroundStyle(Color.secondary.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            LineMark(x: .value("t", info.end), y: .value("v", 0), series: .value("s", "pace"))
                .foregroundStyle(Color.secondary.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(pts) { p in
                LineMark(x: .value("t", p.t), y: .value("v", p.v), series: .value("s", "actual"))
                    .foregroundStyle(Color.orange).lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let e = projEnd {
                LineMark(x: .value("t", info.now), y: .value("v", info.remaining), series: .value("s", "proj"))
                    .foregroundStyle(Color.orange.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                LineMark(x: .value("t", e.0), y: .value("v", e.1), series: .value("s", "proj"))
                    .foregroundStyle(Color.orange.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            RuleMark(x: .value("now", info.now)).foregroundStyle(Color.orange.opacity(0.45))
                .annotation(position: .top, alignment: .center, spacing: 2) {
                    Text("Maintenant").font(.system(size: 9, weight: .medium)).foregroundStyle(Color.orange)
                }
            PointMark(x: .value("t", info.now), y: .value("v", info.remaining)).foregroundStyle(Color.orange).symbolSize(40)
            if let h = hover.date, let s = hoverSample(h) {
                RuleMark(x: .value("t", s.t)).foregroundStyle(Color.primary.opacity(0.35))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        HoverTip(lines: [(s.future ? "Prévu" : "Restant", String(format: "%.1f %%", s.v)),
                                         ("Attendu", String(format: "%.1f %%", s.pace)),
                                         ("Écart", String(format: "%+.1f pts", s.v - s.pace))],
                                 title: s.t.formatted(date: .abbreviated, time: .shortened) + (s.future ? " · projection" : ""))
                    }
                PointMark(x: .value("t", s.t), y: .value("v", s.v)).foregroundStyle(s.future ? Color.orange.opacity(0.8) : Color.primary).symbolSize(36)
            }
        }
        .chartOverlay { hoverLayer($0, hover) }
        .chartXScale(domain: info.start...info.end)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { v in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.18))
                AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d)) %").font(.caption2) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                AxisValueLabel(format: fmt).font(.caption2)
            }
        }
        .frame(height: height)
    }
}

/// A quota window with its big number, margin badge, burn-down chart and projection.
struct QuotaPanel: View {
    @EnvironmentObject var store: Store
    let info: QuotaInfo
    var height: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                let pid = info.q.provider
                ProviderIcon(id: pid, symbol: store.providers.first { $0.id == pid }?.symbol ?? "sparkles", size: 18)
                Text(store.providerName(pid).uppercased() + " · " + info.q.title.uppercased())
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(resetText(info.q.resetsAt)).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.0f %%", info.remaining)).font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-0.5)
                Text("restants").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Badge(text: aheadText(info), good: info.ahead >= 0)
            }
            QuotaChart(info: info, height: height)
            let p = info.projected
            Text(p.map { $0 >= 0 ? String(format: "Au rythme actuel : ≈ %.0f %% restants au reset", $0)
                                : "Au rythme actuel, la limite sera atteinte avant le reset" } ?? " ")
                .font(.caption).foregroundStyle((p ?? 0) >= 0 ? Color.secondary : Color.red)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}

func primaryQuota(_ qs: [QuotaWindow]) -> QuotaWindow? {
    qs.first { $0.label == "7 j" } ?? qs.max { $0.windowMinutes < $1.windowMinutes }
}
