import Charts
import SwiftUI

// MARK: - Spend chart (4 styles, chosen in Settings › Général)

enum SpendStyle: String, CaseIterable, Identifiable {
    case stacked, cumulative, heatmap, focus
    var id: String { rawValue }
    var label: String {
        switch self {
        case .stacked: "Barres et moyenne"
        case .cumulative: "Cumul du mois"
        case .heatmap: "Calendrier"
        case .focus: "Période en cours"
        }
    }
    var detail: String {
        switch self {
        case .stacked: "Barres empilées par source ou par modèle, avec la moyenne."
        case .cumulative: "Courbe cumulée du mois, projection et mois dernier."
        case .heatmap: "Un carré par jour, coloré selon la dépense."
        case .focus: "Barres fines, période en cours en avant, sans les trous."
        }
    }
    var symbol: String {
        switch self {
        case .stacked: "chart.bar.fill"
        case .cumulative: "chart.line.uptrend.xyaxis"
        case .heatmap: "square.grid.3x3.fill"
        case .focus: "chart.bar.xaxis"
        }
    }
}

final class ChartSel: ObservableObject {
    @Published var label: String?
    @Published var day: Int?
}

/// Big number with a small label above it, for chart headers.
struct ChartStat: View {
    let label: String, value: String
    var big = false
    var tint: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(big ? .system(size: 22, weight: .semibold, design: .rounded) : .system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(tint)
        }
    }
}

struct SpendChart: View {
    @EnvironmentObject var store: Store
    let data: [UsageRecord]
    @ObservedObject var ui: DashState
    /// true: series are sources (overview). false: series are the top models (agent page).
    var stacked: Bool
    var provider: String? = nil
    var styleOverride: SpendStyle? = nil
    @AppStorage("spendStyle") private var styleRaw = SpendStyle.stacked.rawValue
    @StateObject private var hover = HoverState()
    @StateObject private var sel = ChartSel()

    struct Pt: Identifiable { let id = UUID(); let date: Date; let source: String; let cost: Double }

    var style: SpendStyle { styleOverride ?? SpendStyle(rawValue: styleRaw) ?? .stacked }
    var unit: Calendar.Component { ui.mode == "Jour" ? .day : ui.mode == "Semaine" ? .weekOfYear : .month }

    // MARK: data

    func points(split: Bool) -> (pts: [Pt], series: [(String, Color)]) {
        let cal = Calendar.current
        let topModels = stacked ? [] : Array(store.breakdown(data, by: \.model).prefix(3).map(\.name))
        var acc: [String: Pt] = [:]
        var seriesCost: [String: Double] = [:]
        for (k, rs) in Dictionary(grouping: data, by: { $0.day + "|" + (stacked ? $0.provider : $0.model) }) {
            let parts = k.split(separator: "|", maxSplits: 1).map(String.init)
            guard let d = Day.fmt.date(from: parts[0]) else { continue }
            let b = cal.dateInterval(of: unit, for: d)?.start ?? d
            let raw = parts.count > 1 ? parts[1] : ""
            let name = !split ? "Dépense" : stacked ? store.providerName(raw) : (topModels.contains(raw) ? raw : "Autres")
            let key = "\(b.timeIntervalSince1970)|\(name)"
            let c = store.totalCost(rs)
            acc[key] = Pt(date: b, source: name, cost: (acc[key]?.cost ?? 0) + c)
            seriesCost[name, default: 0] += c
        }
        let pts = acc.values.sorted { $0.date < $1.date }
        guard split else { return (pts, [("Dépense", .orange)]) }
        if stacked {
            let ids = Dictionary(grouping: data, by: \.provider).keys
            let named = ids.map { (store.providerName($0), color(for: $0)) }
            return (pts, named.sorted { (seriesCost[$0.0] ?? 0) > (seriesCost[$1.0] ?? 0) })
        }
        let palette: [Color] = [.orange, .purple, .teal]
        var s = topModels.enumerated().map { ($0.element, palette[$0.offset % palette.count]) }
        if seriesCost["Autres"] != nil { s.append(("Autres", .gray)) }
        return (pts, s)
    }

    /// Total per bucket, in date order.
    func totals(_ pts: [Pt]) -> [(date: Date, cost: Double)] {
        Dictionary(grouping: pts, by: \.date).map { ($0.key, $0.value.reduce(0) { $0 + $1.cost }) }.sorted { $0.0 < $1.0 }
    }

    var currentBucket: Date { Calendar.current.dateInterval(of: unit, for: Date())?.start ?? Date() }
    var currentLabel: String { unit == .day ? "Aujourd'hui" : unit == .weekOfYear ? "Cette semaine" : "Ce mois-ci" }

    func stats(_ t: [(date: Date, cost: Double)]) -> (cur: Double, avg: Double) {
        let cur = t.first { $0.date == currentBucket }?.cost ?? 0
        let past = t.filter { $0.date != currentBucket && $0.cost > 0 }
        return (cur, past.isEmpty ? 0 : past.reduce(0) { $0 + $1.cost } / Double(past.count))
    }

    func deltaText(_ cur: Double, _ avg: Double) -> (String, Color) {
        guard avg > 0 else { return ("—", .secondary) }
        let d = (cur - avg) / avg * 100
        return (String(format: "%@%.0f %%", d >= 0 ? "+" : "−", abs(d)), d > 25 ? .red : d < -25 ? .green : .primary)
    }

    // MARK: body

    var body: some View {
        let trailing: String = switch style {
        case .cumulative: Date().formatted(.dateTime.month(.wide).year()).capitalizedFirst
        case .heatmap: "par jour"
        default: "USD équivalent API"
        }
        return Section_(title: "Dépense", trailing: trailing) {
            AnyView(VStack(alignment: .leading, spacing: 12) {
                switch style {
                case .stacked: stackedView
                case .cumulative: cumulativeView
                case .heatmap: heatmapView
                case .focus: focusView
                }
            })
        }
    }

    var modePicker: some View {
        Picker("", selection: $ui.mode) { ForEach(["Jour", "Semaine", "Mois"], id: \.self) { Text($0) } }
            .pickerStyle(.segmented).frame(width: 240).labelsHidden()
    }

    var empty: some View {
        Text("Aucune donnée sur cette période.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
    }

    // MARK: 1. stacked bars + average

    @ViewBuilder var stackedView: some View {
        let (pts, series) = points(split: true)
        let t = totals(pts)
        let (cur, avg) = stats(t)
        let (dt, dc) = deltaText(cur, avg)
        HStack(alignment: .bottom, spacing: 24) {
            ChartStat(label: currentLabel, value: money(cur), big: true)
            ChartStat(label: "vs moyenne", value: dt, tint: dc)
            ChartStat(label: "Moyenne / " + (unit == .day ? "jour" : unit == .weekOfYear ? "semaine" : "mois"), value: money(avg))
            Spacer()
            modePicker
        }
        if pts.isEmpty { empty } else {
            Chart {
                ForEach(pts) { p in
                    BarMark(x: .value("Date", p.date, unit: unit), y: .value("USD", p.cost))
                        .foregroundStyle(by: .value("Source", p.source))
                }
                if avg > 0 {
                    RuleMark(y: .value("Moyenne", avg))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("moy. " + money(avg)).font(.caption2).foregroundStyle(.secondary)
                        }
                }
                hoverRule(pts)
            }
            .chartForegroundStyleScale(domain: series.map(\.0), range: series.map(\.1))
            .chartLegend(position: .bottom, alignment: .leading)
            .chartOverlay { hoverLayer($0, hover) }
            .frame(height: 220)
        }
    }

    @ChartContentBuilder func hoverRule(_ pts: [Pt]) -> some ChartContent {
        if let h = hover.date {
            let b = Calendar.current.dateInterval(of: unit, for: h)?.start ?? h
            let rows = pts.filter { $0.date == b }.sorted { $0.cost > $1.cost }
            if !rows.isEmpty {
                let fmt: Date.FormatStyle = unit == .month ? .dateTime.month(.wide).year() : .dateTime.day().month(.abbreviated).year()
                RuleMark(x: .value("Date", b, unit: unit)).foregroundStyle(Color.primary.opacity(0.25))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        HoverTip(lines: (rows.count > 1 ? [("Total", money(rows.reduce(0) { $0 + $1.cost }))] : [])
                                 + rows.map { ($0.source, money($0.cost)) },
                                 title: (unit == .weekOfYear ? "Semaine du " : "") + b.formatted(fmt))
                    }
            }
        }
    }

    // MARK: 4. thin bars, current period highlighted, empty periods collapsed

    @ViewBuilder var focusView: some View {
        let t = totals(points(split: false).pts).filter { $0.cost > 0 }
        let multiYear = (t.last.map { $0.date.timeIntervalSince(t.first!.date) } ?? 0) > 330 * 86400
        let label: (Date) -> String = { d in
            switch unit {
            case .month: d.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
            default: multiYear ? d.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)) : d.formatted(.dateTime.day().month(.abbreviated))
            }
        }
        let rows = t.map { (label: label($0.date), date: $0.date, cost: $0.cost) }
        let cur = rows.first { $0.date == currentBucket }
        let best = rows.max { $0.cost < $1.cost }
        let step = max(1, Int((Double(rows.count) / 10).rounded(.up)))
        let shown = Set(rows.enumerated().filter { $0.offset % step == 0 || $0.offset == rows.count - 1 }.map(\.element.label))
        HStack(alignment: .bottom, spacing: 24) {
            ChartStat(label: currentLabel, value: money(cur?.cost ?? 0), big: true, tint: .orange)
            if let best { ChartStat(label: "Record", value: money(best.cost) + " · " + best.label) }
            ChartStat(label: "Périodes actives", value: "\(rows.count)")
            Spacer()
            modePicker
        }
        if rows.isEmpty { empty } else {
            Chart {
                ForEach(rows, id: \.label) { r in
                    let isCur = r.date == currentBucket
                    BarMark(x: .value("Période", r.label), y: .value("USD", r.cost), width: .ratio(0.45))
                        .foregroundStyle(isCur ? Color.orange : Color.orange.opacity(sel.label == r.label ? 0.75 : 0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .annotation(position: .top, spacing: 3) {
                            if isCur || sel.label == r.label {
                                Text(money(r.cost)).font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(isCur ? Color.orange : .primary)
                            }
                        }
                }
            }
            .chartXSelection(value: $sel.label)
            .chartXAxis {
                AxisMarks(values: rows.map(\.label).filter { shown.contains($0) }) { _ in AxisValueLabel() }
            }
            .frame(height: 220)
            if unit != .day && rows.count < (t.isEmpty ? 0 : spanCount(t)) {
                Text("Les périodes sans dépense sont repliées.").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    /// Number of buckets between the first and last spending bucket, empty ones included.
    func spanCount(_ t: [(date: Date, cost: Double)]) -> Int {
        guard let a = t.first?.date, let b = t.last?.date else { return 0 }
        return (Calendar.current.dateComponents([unit], from: a, to: b).value(for: unit) ?? 0) + 1
    }

    // MARK: 2. cumulative month, projection, last month, budget

    @ViewBuilder var cumulativeView: some View {
        let m = monthSeries()
        let spent = m.cur.last?.1 ?? 0
        let proj = m.today > 0 ? spent / Double(m.today) * Double(m.days) : 0
        let budget = provider == nil ? store.monthlyBudget : 0
        let prevSame = m.prev.first { $0.0 == min(m.today, m.prev.count - 1) }?.1 ?? 0
        let (dt, dc) = deltaText(spent, prevSame)
        HStack(alignment: .bottom, spacing: 24) {
            ChartStat(label: "Dépensé ce mois", value: money(spent), big: true)
            ChartStat(label: "Projection fin de mois", value: money(proj), tint: budget > 0 && proj > budget ? .red : .primary)
            ChartStat(label: "vs même date le mois dernier", value: dt, tint: dc)
            if budget > 0 { ChartStat(label: "Budget", value: money(budget)) }
            Spacer()
        }
        Chart {
            ForEach(m.prev, id: \.0) { p in
                LineMark(x: .value("Jour", p.0), y: .value("USD", p.1), series: .value("Série", "Mois dernier"))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
            }
            ForEach(m.cur, id: \.0) { p in
                AreaMark(x: .value("Jour", p.0), y: .value("USD", p.1))
                    .foregroundStyle(LinearGradient(colors: [Color.orange.opacity(0.28), Color.orange.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Jour", p.0), y: .value("USD", p.1), series: .value("Série", "Ce mois"))
                    .foregroundStyle(Color.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if m.today < m.days {
                ForEach([(m.today, spent), (m.days, proj)], id: \.0) { p in
                    LineMark(x: .value("Jour", p.0), y: .value("USD", p.1), series: .value("Série", "Projection"))
                        .foregroundStyle(Color.orange.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.8, dash: [5, 4]))
                }
            }
            PointMark(x: .value("Jour", m.today), y: .value("USD", spent)).foregroundStyle(Color.orange).symbolSize(45)
            if budget > 0 {
                RuleMark(y: .value("Budget", budget))
                    .foregroundStyle(Color.red.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("budget " + money(budget)).font(.caption2).foregroundStyle(.secondary)
                    }
            }
            if let d = sel.day, d >= 0 {
                let c = m.cur.first { $0.0 == d }?.1
                let p = m.prev.first { $0.0 == d }?.1
                RuleMark(x: .value("Jour", d)).foregroundStyle(Color.primary.opacity(0.25))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        HoverTip(lines: (c.map { [("Ce mois", money($0))] } ?? []) + (p.map { [("Mois dernier", money($0))] } ?? []),
                                 title: "Jour \(d)")
                    }
            }
        }
        .chartXSelection(value: $sel.day)
        .chartXScale(domain: 0...max(m.days, m.prev.count - 1))
        .chartXAxis { AxisMarks(values: [1, 8, 15, 22, m.days]) { v in AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)") } } }
        .frame(height: 220)
        HStack(spacing: 14) {
            legend(Color.orange, "Ce mois")
            legend(Color.orange.opacity(0.8), "Projection", dashed: true)
            legend(Color.secondary.opacity(0.45), "Mois dernier")
        }
    }

    func legend(_ c: Color, _ t: String, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 14, y: 1)) }
                .stroke(c, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 2] : []))
                .frame(width: 14, height: 2)
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Cumulative spend per day of month, for this month (up to today) and the previous one.
    func monthSeries() -> (cur: [(Int, Double)], prev: [(Int, Double)], days: Int, today: Int) {
        let cal = Calendar.current, now = Date()
        let prevDate = cal.date(byAdding: .month, value: -1, to: now) ?? now
        let curP = String(Day.string(now).prefix(7)), prevP = String(Day.string(prevDate).prefix(7))
        var cur: [Int: Double] = [:], prev: [Int: Double] = [:]
        let rs = store.filtered(.all, provider: provider).filter { $0.day.hasPrefix(curP) || $0.day.hasPrefix(prevP) }
        for (day, g) in Dictionary(grouping: rs, by: \.day) {
            let d = Int(day.suffix(2)) ?? 0, c = store.totalCost(g)
            if day.hasPrefix(curP) { cur[d, default: 0] += c } else { prev[d, default: 0] += c }
        }
        let n = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let pn = cal.range(of: .day, in: .month, for: prevDate)?.count ?? 30
        let today = cal.component(.day, from: now)
        func cum(_ m: [Int: Double], _ upTo: Int) -> [(Int, Double)] {
            var s = 0.0
            return [(0, 0)] + (1...max(upTo, 1)).map { s += m[$0] ?? 0; return ($0, s) }
        }
        return (cum(cur, today), prev.isEmpty ? [] : cum(prev, pn), n, today)
    }

    // MARK: 3. calendar heatmap

    @ViewBuilder var heatmapView: some View {
        let daily = Dictionary(grouping: store.filtered(.all, provider: provider), by: \.day).mapValues { store.totalCost($0) }
        SpendHeatmap(daily: daily)
    }
}

struct SpendHeatmap: View {
    let daily: [String: Double]
    let cell: CGFloat = 13, gap: CGFloat = 3

    static func level(_ c: Double, max m: Double) -> Int {
        guard c > 0, m > 0 else { return 0 }
        return 1 + min(3, Int((c / m).squareRoot() * 4))
    }
    static func fill(_ l: Int) -> Color {
        [Color.primary.opacity(0.07), Color.orange.opacity(0.25), Color.orange.opacity(0.5), Color.orange.opacity(0.75), Color.orange][l]
    }

    var body: some View {
        GeometryReader { g in
            let cols = max(8, min(53, Int((g.size.width - 22) / (cell + gap))))
            grid(cols: cols)
        }
        .frame(height: 7 * (cell + gap) + 16 + 72)
    }

    func grid(cols: Int) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7               // 0 = Monday
        let start = cal.date(byAdding: .day, value: -(wd + 7 * (cols - 1)), to: today)!
        let days: [(date: Date, key: String)] = (0..<(cols * 7)).compactMap { i in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            return d > today ? nil : (d, Day.string(d))
        }
        let costs = days.map { daily[$0.key] ?? 0 }
        let mx = costs.max() ?? 0
        let total = costs.reduce(0, +), active = costs.filter { $0 > 0 }.count
        let rec = zip(days, costs).max { $0.1 < $1.1 }
        let fmt = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 24) {
                ChartStat(label: "\(cols) dernières semaines", value: money(total), big: true)
                ChartStat(label: "Jours actifs", value: "\(active)")
                if let rec, rec.1 > 0 { ChartStat(label: "Jour record", value: money(rec.1) + " · " + rec.0.date.formatted(fmt)) }
                Spacer()
            }
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: gap) {
                    Text(" ").font(.system(size: 9)).frame(height: 12)
                    ForEach(0..<7, id: \.self) { r in
                        Text(r == 0 ? "L" : r == 2 ? "M" : r == 4 ? "V" : "").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 14, height: cell)
                    }
                }
                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<cols, id: \.self) { c in
                        let first = cal.date(byAdding: .day, value: c * 7, to: start)!
                        let prevFirst = cal.date(byAdding: .day, value: (c - 1) * 7, to: start)!
                        // First column only gets a label if its month lasts long enough not to collide with the next one.
                        let newMonth = c == 0 ? cal.component(.day, from: first) <= 14
                            : cal.component(.month, from: first) != cal.component(.month, from: prevFirst)
                        VStack(spacing: gap) {
                            Text(newMonth && c < cols - 2 ? first.formatted(.dateTime.month(.abbreviated)) : "")
                                .font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize().frame(width: cell, height: 12, alignment: .leading)
                            ForEach(0..<7, id: \.self) { r in
                                let i = c * 7 + r
                                if i < days.count {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Self.fill(Self.level(costs[i], max: mx)))
                                        .frame(width: cell, height: cell)
                                        .help(days[i].date.formatted(fmt) + " : " + money(costs[i]))
                                } else {
                                    Color.clear.frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("moins").font(.caption2).foregroundStyle(.tertiary)
                ForEach(0..<5, id: \.self) { l in RoundedRectangle(cornerRadius: 2).fill(Self.fill(l)).frame(width: 10, height: 10) }
                Text("plus").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Rankings (models, projects) and token mix

final class ExpandState: ObservableObject { @Published var open = false }

func shareText(_ f: Double) -> String {
    f <= 0 ? "0 %" : f < 0.001 ? "<0,1 %" : f < 0.1 ? String(format: "%.1f %%", f * 100).replacingOccurrences(of: ".", with: ",") : String(format: "%.0f %%", f * 100)
}

/// Ranked list by cost: rank, name, bar proportional to the leader, share of the total. Top 5, then expandable.
struct RankingCard: View {
    @EnvironmentObject var store: Store
    let title: String
    let data: [UsageRecord]
    let key: KeyPath<UsageRecord, String>
    var tint: Color = .orange
    var limit = 5
    @StateObject private var ex = ExpandState()

    var body: some View {
        let rows = store.breakdown(data, by: key)
        let total = max(rows.reduce(0) { $0 + $1.cost }, 0.0001)
        let lead = max(rows.first?.cost ?? 0, 0.0001)
        let shown = ex.open ? rows : Array(rows.prefix(limit))
        return Section_(title: title, trailing: rows.isEmpty ? "" : "\(rows.count)") {
            AnyView(VStack(alignment: .leading, spacing: 11) {
                if rows.isEmpty { Text("Aucune donnée.").foregroundStyle(.secondary) }
                ForEach(Array(shown.enumerated()), id: \.element.name) { i, r in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(i == 0 ? tint : Color.secondary)
                            .frame(width: 18, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(r.name.isEmpty ? "—" : r.name).lineLimit(1).truncationMode(.middle)
                                if key == \UsageRecord.model && Pricing.shared.isApproximate(r.name) {
                                    Text("≈").foregroundStyle(.orange).help("Prix approché par famille")
                                }
                                Spacer(minLength: 8)
                                Text(compact(r.tokens)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                                Text(money(r.cost)).font(.callout.weight(.semibold).monospacedDigit())
                            }
                            HStack(spacing: 8) {
                                shareBar(r.cost / lead, tint.opacity(i == 0 ? 1 : 0.6))
                                Text(shareText(r.cost / total)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                    .frame(width: 42, alignment: .trailing)
                            }
                        }
                    }
                }
                if rows.count > limit {
                    Button { withAnimation(.snappy) { ex.open.toggle() } } label: {
                        Label(ex.open ? "Afficher moins" : "Afficher les \(rows.count - limit) autres",
                              systemImage: ex.open ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 28)
                }
            })
        }
    }
}

/// Token types on a log scale, so the huge cache-read share doesn't flatten everything else.
struct TokenBreakdown: View {
    let data: [UsageRecord]
    var body: some View {
        let parts: [(String, Int, Color)] = [
            ("Entrée", data.reduce(0) { $0 + $1.input }, .blue), ("Sortie", data.reduce(0) { $0 + $1.output }, .orange),
            ("Cache écrit", data.reduce(0) { $0 + $1.cacheWrite }, .purple), ("Cache lu", data.reduce(0) { $0 + $1.cacheRead }, .teal),
        ].sorted { $0.1 > $1.1 }
        let total = max(parts.reduce(0) { $0 + $1.1 }, 1)
        let top = log10(Double(max(parts.first?.1 ?? 1, 1)) + 1)
        return Section_(title: "Répartition des tokens", trailing: compact(total)) {
            AnyView(VStack(alignment: .leading, spacing: 10) {
                ForEach(parts, id: \.0) { p in
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Circle().fill(p.2).frame(width: 7, height: 7)
                            Text(p.0).lineLimit(1)
                        }
                        .frame(width: 110, alignment: .leading)
                        shareBar(top > 0 ? log10(Double(p.1) + 1) / top : 0, p.2)
                        Text(compact(p.1)).font(.callout.weight(.semibold).monospacedDigit()).frame(width: 64, alignment: .trailing)
                        Text(shareText(Double(p.1) / Double(total))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                    }
                }
                Text("Barres en échelle logarithmique : sans elle, le cache lu écraserait tout le reste.")
                    .font(.caption).foregroundStyle(.tertiary)
            })
        }
    }
}
