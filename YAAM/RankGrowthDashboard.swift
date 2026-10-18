import SwiftUI
import Charts

struct RankPerformanceMonitor: View {
    @Binding var metric: RankHistoryMetric
    let series: [RankTrendSeries]
    let trackedCallsigns: [String]
    let isRefreshing: Bool
    let status: String
    let refreshAction: () -> Void
    let removeAction: (String) -> Void
    @AppStorage("leaderboardGrowthPeriod") private var period: RankGrowthPeriod = .month
    @AppStorage("leaderboardGrowthRace") private var race = false
    @State private var selectedRival: String = ""
    @State private var selectedDate: Date?
    var now: Date = Date()

    private var owner: RankTrendSeries? { series.first(where: \.isOwner) }
    private var points: [RankTrendPoint] { RankGrowthAnalysis.points(owner?.points ?? [], period: period, now: now) }
    private var comparisons: [RankGrowthComparison] { RankGrowthAnalysis.comparisons(series: series, period: period, now: now) }
    private var comparison: RankGrowthComparison? { comparisons.first(where: { $0.callsign == selectedRival }) ?? comparisons.first(where: { $0.dates.count >= 2 }) ?? comparisons.first }
    private var movement: Int? { RankGrowthAnalysis.improvement(points) }
    private var comparable: [RankGrowthComparison] { comparisons.filter { $0.gain != nil } }
    private var ahead: Int { comparable.filter { ($0.gain ?? 0) > 0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if status.lowercased().contains("failed") || status.lowercased().contains("unavailable") || status.lowercased().contains("error") {
                Label(points.isEmpty ? "History refresh unavailable. Open collection status for details." : "History refresh unavailable. Showing saved observations.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { summaryCards }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) { summaryCards }
            }
            if points.isEmpty {
                empty("Your growth story starts here", detail: "Refresh to retrieve recorded history. Track rivals above to compare your progress as observations arrive.")
            } else {
                chartPanel
            }
            if !comparisons.isEmpty { rivalPanel }
            DisclosureGroup("Collection status & data coverage") {
                VStack(alignment: .leading, spacing: 5) {
                    Text(status.isEmpty ? "Recorded observations are collected by Rank Service." : status)
                    Text("\(points.count) observed days in this period. Missing days remain gaps. Rank movement measures leaderboard position, not new QSOs. Daily server collection continues while YAAM is closed.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }.font(.caption)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.blue.opacity(0.2)))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .onChange(of: period) { _, _ in selectedDate = nil }
        .onChange(of: metric) { _, _ in selectedDate = nil }
        .onChange(of: selectedRival) { _, _ in selectedDate = nil }
        .onChange(of: race) { _, _ in selectedDate = nil }
    }

    @ViewBuilder private var summaryCards: some View {
                stat("LATEST RANK", value: points.last.map { "#\($0.rank.formatted())" } ?? "—", detail: points.last.map { day($0.date) + " · UTC" } ?? "Awaiting an observation", icon: "trophy.fill", tint: .blue)
                stat("PERIOD MOVEMENT", value: movement.map(signed) ?? "—", detail: movement == nil ? "Needs two observed days" : "Rank positions · higher is better", icon: "arrow.up.right", tint: (movement ?? 0) < 0 ? .orange : .green)
                stat("PERSONAL BEST", value: points.map(\.rank).min().map { "#\($0.formatted())" } ?? "—", detail: "Best observed in this period", icon: "sparkles", tint: .purple)
                stat("GAINING ON RIVALS", value: comparable.isEmpty ? "—" : "\(ahead) / \(comparable.count)", detail: "Matched observation dates per rival", icon: "flag.checkered", tint: .teal)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR GROWTH, IN PERSPECTIVE").font(.caption2.weight(.bold)).tracking(1.4).foregroundStyle(.blue)
                    Text("Operator growth & rival momentum").font(.title2.bold())
                    Text("\(owner?.callsign ?? "Your station") · track your momentum and see who you are catching.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isRefreshing { ProgressView().controlSize(.small) }
                Button(action: refreshAction) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered).help("Refresh recorded rank history").accessibilityLabel("Refresh rank history").disabled(isRefreshing)
            }
            ViewThatFits(in: .horizontal) {
                HStack { metricPicker; Spacer(); periodPicker }
                VStack(alignment: .leading, spacing: 8) { metricPicker; periodPicker }
            }
        }
    }
    private var metricPicker: some View {
        Picker("Ranking", selection: $metric) {
            ForEach(RankHistoryMetric.allCases) { Text($0.title).tag($0) }
        }.labelsHidden().pickerStyle(.segmented).frame(width: 310)
    }
    private var periodPicker: some View {
        Picker("Period", selection: $period) { ForEach(RankGrowthPeriod.allCases) { Text($0.rawValue).tag($0) } }
            .labelsHidden().pickerStyle(.segmented).frame(width: 300)
    }
    private func stat(_ label: String, value: String, detail: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.75)
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(minWidth: 125, maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
            .padding(14).background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { chartHeading; Spacer(); chartPicker }
                VStack(alignment: .leading, spacing: 10) { chartHeading; chartPicker }
            }
            if race {
                if let comparison {
                    Picker("Compare with", selection: Binding(get: { comparison.callsign }, set: { selectedRival = $0 })) {
                        ForEach(comparisons) { Text($0.callsign).tag($0.callsign) }
                    }.frame(maxWidth: 310)
                }
                if let comparison, comparison.dates.count >= 2 {
                    Text("Same starting day. Same observed days. Percentage change in rank, with positive values showing improvement.")
                        .font(.caption).foregroundStyle(.secondary)
                    growthChart(comparison)
                    HStack(spacing: 18) {
                        Label(owner?.callsign ?? "You", systemImage: "circle.fill").foregroundStyle(.blue)
                        Label(comparison.callsign, systemImage: "diamond.fill").foregroundStyle(.orange)
                        Spacer()
                        Text("\(day(comparison.dates.first!)) – \(day(comparison.dates.last!)) UTC").foregroundStyle(.secondary)
                    }.font(.caption.weight(.medium))
                } else { empty("A fair comparison needs two shared days", detail: "Both stations must have observations on the same dates. More history will unlock this view.") }
            } else {
                Text("Your rank on its own scale, so even small changes are visible. Lower rank is better; upward movement is a climb.")
                    .font(.caption).foregroundStyle(.secondary)
                ownChart
                if let first = points.first, let last = points.last {
                    HStack {
                        Text("#\(first.rank.formatted()) → #\(last.rank.formatted())").fontWeight(.semibold)
                        Spacer()
                        Text("\(day(first.date)) – \(day(last.date)) UTC").foregroundStyle(.secondary)
                    }.font(.caption)
                }
            }
            Text("Click or drag across the chart to inspect a recorded day. Breaks mean no observation.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(16).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }
    private var chartHeading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(race ? "The growth race" : "Your rank journey").font(.headline)
            Text(insight).font(.caption).foregroundStyle(movement == nil ? Color.secondary : (movement ?? 0) >= 0 ? .green : .orange)
        }
    }
    private var chartPicker: some View {
        Picker("Chart", selection: $race) { Text("Your rank").tag(false); Text("Growth race").tag(true) }
            .labelsHidden().pickerStyle(.segmented).frame(width: 240)
    }
    private var insight: String {
        if race {
            guard let pair = comparison, let gain = pair.gain else { return "Waiting for two shared observations." }
            if gain == 0 { return "Matching \(pair.callsign)'s pace on shared dates." }
            return "You \(gain > 0 ? "gained" : "lost") \(abs(gain).formatted()) positions against \(pair.callsign) on shared dates."
        }
        guard let movement else { return "One observation is a starting point — more days reveal your momentum." }
        if movement == 0 { return "Holding your position across the observed period." }
        return movement > 0 ? "You climbed \(movement.formatted()) positions across this period." : "You slipped \(abs(movement).formatted()) positions across this period."
    }
    private var dateDomain: ClosedRange<Date> {
        let end = RankHistoryCalendar.calendar.startOfDay(for: now)
        let start = (race ? comparison?.dates.first : points.first?.date) ?? end
        return start < end ? start...end : start.addingTimeInterval(-43200)...end.addingTimeInterval(43200)
    }
    private var ownDomain: ClosedRange<Double> {
        let values = points.map { -Double($0.rank) }
        let low = values.min() ?? -2, high = values.max() ?? -1
        let pad = max(2, (high - low) * 0.18)
        return (low - pad)...min(-1, high + pad)
    }
    private var ownChart: some View {
        let segments = RankGrowthAnalysis.segmentIDs(points)
        return Chart {
            ForEach(Array(points.enumerated()), id: \.element.id) { i, point in
                AreaMark(x: .value("UTC day", point.date), yStart: .value("Floor", ownDomain.lowerBound), yEnd: .value("Rank", -Double(point.rank)), series: .value("Segment", segments[i]))
                    .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.22), .blue.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("UTC day", point.date), y: .value("Rank", -Double(point.rank)), series: .value("Segment", segments[i]))
                    .foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 3))
                PointMark(x: .value("UTC day", point.date), y: .value("Rank", -Double(point.rank)))
                    .foregroundStyle(.blue).symbolSize(28)
                    .accessibilityLabel("\(day(point.date)), rank \(point.rank)")
            }
            if let selected = nearest(points) {
                RuleMark(x: .value("Selected", selected.date)).foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, alignment: .leading, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) { annotation("\(day(selected.date)) · #\(selected.rank.formatted())") }
            }
        }
        .chartYScale(domain: ownDomain)
        .chartYAxis { AxisMarks(position: .leading) { value in
            AxisGridLine().foregroundStyle(Color.primary.opacity(0.07))
            AxisValueLabel { if let rank = value.as(Double.self) { Text("#\(Int(abs(rank)).formatted())") } }
        } }
        .chartXScale(domain: dateDomain, range: .plotDimension(padding: 32))
        .chartXSelection(value: $selectedDate)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
        .frame(height: 240).padding(.top, 18)
    }
    private func growthChart(_ pair: RankGrowthComparison) -> some View {
        Chart {
            RuleMark(y: .value("Baseline", 0)).foregroundStyle(.secondary.opacity(0.4)).lineStyle(StrokeStyle(dash: [4, 4]))
            growthMarks(pair.owner, label: owner?.callsign ?? "You", color: .blue, diamond: false)
            growthMarks(pair.rival, label: pair.callsign, color: .orange, diamond: true)
            if let selected = nearest(pair.owner), let index = pair.owner.firstIndex(where: { $0.date == selected.date }) {
                RuleMark(x: .value("Selected", selected.date)).foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, alignment: .leading, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        annotation("\(day(selected.date)) · \(owner?.callsign ?? "You") #\(selected.rank.formatted()) · \(pair.callsign) #\(pair.rival[index].rank.formatted())")
                    }
            }
        }
        .chartYAxis { AxisMarks(position: .leading) { value in
            AxisGridLine().foregroundStyle(Color.primary.opacity(0.07))
            AxisValueLabel { if let v = value.as(Double.self) { Text(String(format: "%+.1f%%", v)) } }
        } }
        .chartXScale(domain: dateDomain, range: .plotDimension(padding: 32))
        .chartXSelection(value: $selectedDate)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
        .frame(height: 240).padding(.top, 18)
    }
    @ChartContentBuilder private func growthMarks(_ points: [RankTrendPoint], label: String, color: Color, diamond: Bool) -> some ChartContent {
        let segments = RankGrowthAnalysis.segmentIDs(points)
        ForEach(Array(points.enumerated()), id: \.element.id) { i, point in
            let value = RankGrowthAnalysis.percent(point.rank, baseline: points.first!.rank)
            LineMark(x: .value("UTC day", point.date), y: .value("Rank improvement (%)", value), series: .value("Line", "\(label)-\(segments[i])"))
                .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 3, dash: diamond ? [6, 3] : []))
            PointMark(x: .value("UTC day", point.date), y: .value("Rank improvement (%)", value))
                .foregroundStyle(color).symbol(diamond ? .diamond : .circle).symbolSize(30)
                .accessibilityLabel("\(label), \(day(point.date)), rank \(point.rank), improvement \(String(format: "%.1f", value)) percent")
        }
    }
    private var rivalPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Who are you catching?").font(.headline); Spacer(); Text("Shared dates only").font(.caption).foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 10)], spacing: 10) {
                ForEach(comparisons) { pair in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(pair.callsign).font(.system(.headline, design: .monospaced))
                            Spacer()
                            Button { selectedRival = pair.callsign; race = true } label: { Image(systemName: "chart.xyaxis.line") }
                                .buttonStyle(.borderless).help("Compare growth with \(pair.callsign)").accessibilityLabel("Compare with \(pair.callsign)")
                            Button { removeAction(pair.callsign) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Stop tracking \(pair.callsign)").accessibilityLabel("Stop tracking \(pair.callsign)")
                        }
                        if let gain = pair.gain {
                            Label(gain == 0 ? "Even pace" : "\(abs(gain).formatted()) positions \(gain > 0 ? "gained" : "lost")", systemImage: gain >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(gain > 0 ? .green : gain < 0 ? .orange : .secondary)
                        } else { Text("Waiting for two shared days").font(.caption).foregroundStyle(.secondary) }
                        if let gap = pair.gap, let rank = pair.rival.last?.rank {
                            Text("#\(rank.formatted()) · \(gap == 0 ? "Tied" : "You \(gap > 0 ? "lead" : "trail") by \(abs(gap).formatted())")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(pair.dates.first.map { start in "\(day(start)) – \(day(pair.dates.last!)) · \(pair.dates.count) shared days" } ?? "No shared observations in this period")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
    private func nearest(_ points: [RankTrendPoint]) -> RankTrendPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private func annotation(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.medium)).padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
    private func empty(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.largeTitle).foregroundStyle(.blue)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 32)
    }
    private func signed(_ value: Int) -> String { (value > 0 ? "+" : "") + value.formatted() }
    private func day(_ date: Date) -> String {
        let f = DateFormatter(); f.timeZone = TimeZone(secondsFromGMT: 0); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
