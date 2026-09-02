//
//  CompetitorProgressViews.swift
//  YAAM
//
//  Interactive Visualizations for Multi-Station Competitor Tracking,
//  Growth & Decline Curves, Velocity Benchmarks, and Overtake Projections.
//

import SwiftUI

// MARK: - Multi-Station Confirmed Progress Chart

struct MultiStationConfirmedProgressChart: View {
    let ownerCallsign: String
    let ownerPoints: [ConfirmedProgressPoint]
    let ownerCurrentConfirmed: Int
    let ownerMonthlyRate: Double
    @ObservedObject var competitorStore: CompetitorTrackingStore

    @State private var hoveredIndex: Int? = nil
    @State private var hoveredPosition: CGPoint? = nil

    private var allSeries: [String: [MultiSeriesTimelinePoint]] {
        competitorStore.generateMultiSeries(
            ownerCallsign: ownerCallsign,
            ownerPoints: ownerPoints,
            ownerCurrentConfirmed: ownerCurrentConfirmed,
            ownerMonthlyRate: ownerMonthlyRate
        )
    }

    private var allPointsFlat: [MultiSeriesTimelinePoint] {
        allSeries.values.flatMap { $0 }
    }

    private var maxValue: Int {
        let maxVal = allPointsFlat.map(\.cumulativeCount).max() ?? 1
        return max(maxVal, 100)
    }

    private var monthLabels: [String] {
        ownerPoints.map(\.label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. Interactive Legend with Toggle Switches
            legendHeader

            // 2. Multi-Line Chart Canvas
            GeometryReader { geometry in
                let plotHeight = max(1, geometry.size.height - 30)
                let plotWidth = max(1, geometry.size.width - 50)
                let origin = CGPoint(x: 45, y: plotHeight)
                let pointCount = monthLabels.count
                let step = pointCount > 1 ? plotWidth / CGFloat(pointCount - 1) : plotWidth

                ZStack(alignment: .topLeading) {
                    // A. Grid & Axes
                    axesAndGrid(origin: origin, plotHeight: plotHeight, width: geometry.size.width)

                    // B. Competitor Series Lines
                    ForEach(competitorStore.competitors.filter(\.isEnabled)) { comp in
                        if let series = allSeries[comp.callsign], series.count == pointCount {
                            seriesPath(series: series, origin: origin, plotHeight: plotHeight, step: step, color: comp.displayColor, isOwner: false)
                        }
                    }

                    // C. User Series Line (Thick Gradient Luminous Stroke)
                    if let ownerSeries = allSeries[ownerCallsign], ownerSeries.count == pointCount {
                        seriesPath(series: ownerSeries, origin: origin, plotHeight: plotHeight, step: step, color: .green, isOwner: true)
                    }

                    // D. X-Axis Month Labels
                    xAxisLabels(origin: origin, step: step, totalHeight: geometry.size.height, width: geometry.size.width)

                    // E. Y-Axis Value Labels
                    yAxisLabels(plotHeight: plotHeight)

                    // F. Hover Cursor Line & Multi-Station Inspector Badge
                    if let idx = hoveredIndex, idx >= 0, idx < pointCount {
                        let xPos = origin.x + CGFloat(idx) * step
                        Path { p in
                            p.move(to: CGPoint(x: xPos, y: 0))
                            p.addLine(to: CGPoint(x: xPos, y: plotHeight))
                        }
                        .stroke(Color.cyan.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                        hoverTooltipCard(index: idx, xPos: xPos, plotHeight: plotHeight)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        if location.x >= origin.x && location.x <= origin.x + plotWidth {
                            let rawIdx = Int(((location.x - origin.x) / step).rounded())
                            hoveredIndex = min(max(0, rawIdx), pointCount - 1)
                            hoveredPosition = location
                        } else {
                            hoveredIndex = nil
                        }
                    case .ended:
                        hoveredIndex = nil
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var legendHeader: some View {
        HStack(spacing: 8) {
            // User Station Pill
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("YOU (\(ownerCallsign))")
                    .font(.caption.weight(.bold).monospaced())
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Color.green.opacity(0.3), lineWidth: 1))

            Divider().frame(height: 14)

            // Competitor Pills (Click to toggle on/off)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(competitorStore.competitors) { comp in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                competitorStore.toggleVisibility(id: comp.id)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(comp.countryFlag)
                                    .font(.caption2)
                                Circle()
                                    .fill(comp.isEnabled ? comp.displayColor : Color.gray)
                                    .frame(width: 7, height: 7)
                                Text(comp.callsign)
                                    .font(.caption.weight(.semibold).monospaced())
                                    .foregroundStyle(comp.isEnabled ? .primary : .secondary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(comp.isEnabled ? comp.displayColor.opacity(0.15) : Color.gray.opacity(0.1), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(comp.isEnabled ? comp.displayColor.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Toggle visibility of \(comp.callsign)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func seriesPath(
        series: [MultiSeriesTimelinePoint],
        origin: CGPoint,
        plotHeight: CGFloat,
        step: CGFloat,
        color: Color,
        isOwner: Bool
    ) -> some View {
        let coordinates: [CGPoint] = series.enumerated().map { idx, pt in
            let x = origin.x + CGFloat(idx) * step
            let y = plotHeight - (CGFloat(pt.cumulativeCount) / CGFloat(maxValue)) * (plotHeight - 14)
            return CGPoint(x: x, y: max(6, y))
        }

        // Draw Historical Segment (Solid)
        let histCoords = coordinates.enumerated().filter { !series[$0.offset].isForecast }.map(\.element)
        if histCoords.count >= 2 {
            Path { p in
                p.move(to: histCoords[0])
                for pt in histCoords.dropFirst() {
                    p.addLine(to: pt)
                }
            }
            .stroke(
                isOwner ? LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [color, color], startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: isOwner ? 3.0 : 2.0, lineCap: .round, lineJoin: .round)
            )
        }

        // Draw Forecast Segment (Dashed)
        let forecastIndices = series.enumerated().filter { $0.element.isForecast }.map(\.offset)
        if let firstForecastIdx = forecastIndices.first, firstForecastIdx > 0 {
            let startPt = coordinates[firstForecastIdx - 1]
            let fCoords = [startPt] + forecastIndices.map { coordinates[$0] }
            Path { p in
                p.move(to: fCoords[0])
                for pt in fCoords.dropFirst() {
                    p.addLine(to: pt)
                }
            }
            .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: isOwner ? 2.5 : 1.8, lineCap: .round, dash: [4, 4]))
        }

        // Dot Markers
        ForEach(Array(coordinates.enumerated()), id: \.offset) { idx, coord in
            let isFore = series[idx].isForecast
            Circle()
                .fill(isFore ? Color.orange : color)
                .frame(width: isOwner ? 6 : 4.5, height: isOwner ? 6 : 4.5)
                .position(coord)
        }
    }

    private func axesAndGrid(origin: CGPoint, plotHeight: CGFloat, width: CGFloat) -> some View {
        ZStack {
            // Main axes
            Path { p in
                p.move(to: CGPoint(x: origin.x, y: 0))
                p.addLine(to: origin)
                p.addLine(to: CGPoint(x: width, y: origin.y))
            }
            .stroke(Color.gray.opacity(0.35), lineWidth: 1)

            // Horizontal Grid lines (5 rows)
            Path { p in
                for row in 0...4 {
                    let y = CGFloat(row) * plotHeight / 4
                    p.move(to: CGPoint(x: origin.x, y: y))
                    p.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color.gray.opacity(0.12), lineWidth: 1)
        }
    }

    private func xAxisLabels(origin: CGPoint, step: CGFloat, totalHeight: CGFloat, width: CGFloat) -> some View {
        ZStack {
            ForEach(Array(monthLabels.enumerated()), id: \.offset) { idx, label in
                if monthLabels.count <= 12 || idx % 2 == 0 || idx == monthLabels.count - 1 {
                    let xPos = origin.x + CGFloat(idx) * step
                    Text(label)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .position(x: xPos, y: totalHeight - 10)
                }
            }
        }
    }

    private func yAxisLabels(plotHeight: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach([0, 1, 2, 3, 4], id: \.self) { row in
                let val = Int((Double(4 - row) / 4.0) * Double(maxValue))
                Text("\(val)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .position(x: 22, y: CGFloat(row) * plotHeight / 4)
            }
        }
    }

    private func hoverTooltipCard(index: Int, xPos: CGFloat, plotHeight: CGFloat) -> some View {
        let label = monthLabels[index]
        let ownerVal = allSeries[ownerCallsign]?[index].cumulativeCount ?? 0

        var rows: [(call: String, count: Int, delta: Int, color: Color, flag: String)] = []
        rows.append((call: ownerCallsign, count: ownerVal, delta: 0, color: .green, flag: "🇮🇷"))

        for comp in competitorStore.competitors where comp.isEnabled {
            if let val = allSeries[comp.callsign]?[index].cumulativeCount {
                let delta = ownerVal - val
                rows.append((call: comp.callsign, count: val, delta: delta, color: comp.displayColor, flag: comp.countryFlag))
            }
        }

        // Sort descending by count
        rows.sort { $0.count > $1.count }

        let cardWidth: CGFloat = 200
        let cardX = min(max(xPos, originXSafe + cardWidth / 2), 650)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("📅 \(label)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Confirmed QSOs")
                    .font(.system(size: 7.5))
                    .foregroundStyle(.secondary)
            }
            Divider()

            ForEach(rows, id: \.call) { r in
                HStack(spacing: 4) {
                    Text(r.flag).font(.caption2)
                    Circle().fill(r.color).frame(width: 6, height: 6)
                    Text(r.call)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(r.call == ownerCallsign ? Color.green : .primary)
                    Spacer()
                    Text("\(r.count)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))

                    if r.call != ownerCallsign {
                        Text(r.delta >= 0 ? "+\(r.delta)" : "\(r.delta)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(r.delta >= 0 ? Color.green : Color.red)
                    }
                }
            }
        }
        .padding(8)
        .frame(width: cardWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
        .position(x: cardX, y: 65)
    }

    private var originXSafe: CGFloat { 45.0 }
}

// MARK: - Competitor Velocity & Head-to-Head Comparison Table

struct CompetitorVelocityComparisonTable: View {
    let ownerCallsign: String
    let ownerConfirmedCount: Int
    let ownerMonthlyRate: Double
    @ObservedObject var competitorStore: CompetitorTrackingStore
    @State private var showAddSheet: Bool = false
    @State private var competitorToEdit: CompetitorStation? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with Add Button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Competitor Velocity & Overtake Projections")
                        .font(.headline)
                    Text("Compare your monthly confirmation growth speed against rivals and view forecast overtake estimates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Competitor", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
            }

            // Table
            VStack(spacing: 0) {
                tableHeader

                // User Station Row
                userRow

                // Competitor Rows
                ForEach(competitorStore.competitors) { comp in
                    competitorRow(comp)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.25), lineWidth: 1))
        }
        .sheet(isPresented: $showAddSheet) {
            AddCompetitorModalView(competitorStore: competitorStore)
        }
        .sheet(item: $competitorToEdit) { comp in
            EditCompetitorModalView(competitor: comp, competitorStore: competitorStore)
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text("Station / Operator")
                .frame(width: 170, alignment: .leading)
            Text("Confirmed")
                .frame(width: 90, alignment: .trailing)
            Text("Monthly Pace")
                .frame(width: 100, alignment: .trailing)
            Text("Activity Trend")
                .frame(width: 130, alignment: .leading)
            Text("Gap vs You")
                .frame(width: 100, alignment: .trailing)
            Text("Overtake / Status Projection")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Actions")
                .frame(width: 65, alignment: .trailing)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
    }

    private var userRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Text("🇮🇷").font(.caption)
                Circle().fill(Color.green).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(ownerCallsign) (YOU)")
                        .font(.caption.weight(.bold).monospaced())
                        .foregroundStyle(Color.green)
                    Text("Your Active Station")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, alignment: .leading)

            Text("\(ownerConfirmedCount)")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .frame(width: 90, alignment: .trailing)

            Text("\(String(format: "%.1f", ownerMonthlyRate)) / mo")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color.green)
                .frame(width: 100, alignment: .trailing)

            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.green)
                Text("Baseline Station")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.green)
            }
            .frame(width: 130, alignment: .leading)

            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)

            Text("Target: Maintaining momentum")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.green.opacity(0.06))
        .border(Color.gray.opacity(0.12), width: 0.5)
    }

    private func competitorRow(_ comp: CompetitorStation) -> some View {
        let gap = ownerConfirmedCount - comp.confirmedCount
        let deltaRate = ownerMonthlyRate - comp.monthlyGrowthRate

        // Overtake calculation
        let overtakeText: String
        let overtakeColor: Color

        if gap > 0 {
            if deltaRate >= 0 {
                overtakeText = "You lead by +\(gap) QSOs (Widening gap by +\(String(format: "%.1f", deltaRate))/mo)"
                overtakeColor = .green
            } else {
                let months = Double(gap) / abs(deltaRate)
                overtakeText = "You lead by +\(gap), rival closing in ~\(String(format: "%.1f", months)) months"
                overtakeColor = .orange
            }
        } else {
            let deficit = abs(gap)
            if deltaRate > 0 {
                let months = Double(deficit) / deltaRate
                overtakeText = "You trail by -\(deficit) QSOs (Projected overtake in ~\(String(format: "%.1f", months)) months)"
                overtakeColor = .cyan
            } else {
                overtakeText = "You trail by -\(deficit) QSOs (Rival expanding lead by +\(String(format: "%.1f", abs(deltaRate)))/mo)"
                overtakeColor = .red
            }
        }

        return HStack(spacing: 8) {
            HStack(spacing: 5) {
                Text(comp.countryFlag).font(.caption)
                Circle().fill(comp.displayColor).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 0) {
                    Text(comp.callsign)
                        .font(.caption.weight(.bold).monospaced())
                    if !comp.name.isEmpty {
                        Text(comp.name)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 170, alignment: .leading)

            Text("\(comp.confirmedCount)")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 90, alignment: .trailing)

            Text("\(String(format: "%.1f", comp.monthlyGrowthRate)) / mo")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(comp.displayColor)
                .frame(width: 100, alignment: .trailing)

            HStack(spacing: 4) {
                Image(systemName: comp.activityTrend.icon)
                    .font(.caption2)
                    .foregroundStyle(comp.activityTrend.color)
                Text(comp.activityTrend.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(comp.activityTrend.color)
            }
            .frame(width: 130, alignment: .leading)

            Text(gap >= 0 ? "+\(gap)" : "\(gap)")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(gap >= 0 ? Color.green : Color.red)
                .frame(width: 100, alignment: .trailing)

            Text(overtakeText)
                .font(.caption2)
                .foregroundStyle(overtakeColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Button {
                    competitorStore.toggleVisibility(id: comp.id)
                } label: {
                    Image(systemName: comp.isEnabled ? "eye.fill" : "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(comp.isEnabled ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle chart visibility")

                Button {
                    competitorToEdit = comp
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit competitor")

                Button {
                    competitorStore.deleteCompetitor(id: comp.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Delete competitor")
            }
            .frame(width: 65, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .border(Color.gray.opacity(0.10), width: 0.5)
    }
}

// MARK: - Add Competitor Modal Sheet

struct AddCompetitorModalView: View {
    @ObservedObject var competitorStore: CompetitorTrackingStore
    @Environment(\.dismiss) private var dismiss

    @State private var callsign: String = ""
    @State private var name: String = ""
    @State private var confirmedCountText: String = "1200"
    @State private var monthlyRateText: String = "35"
    @State private var selectedColorHex: String = "#FF9500"

    private let availableColors: [(name: String, hex: String)] = [
        ("Orange", "#FF9500"),
        ("Purple", "#AF52DE"),
        ("Crimson", "#FF2D55"),
        ("Teal", "#30B0C7"),
        ("Yellow", "#FFCC00"),
        ("Pink", "#FF375F"),
        ("Indigo", "#5856D6"),
        ("Mint", "#00C7BE")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("Add Competitor / Rival Station")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Form {
                TextField("Callsign (e.g. EP2LMA, DL7ON):", text: $callsign)
                    .font(.headline.monospaced())

                TextField("Operator Name / Club (Optional):", text: $name)

                TextField("Current Confirmed QSOs:", text: $confirmedCountText)

                TextField("Estimated Monthly QSOs Added:", text: $monthlyRateText)

                Picker("Chart Line Color:", selection: $selectedColorHex) {
                    ForEach(availableColors, id: \.hex) { c in
                        HStack {
                            Circle().fill(Color(hex: c.hex) ?? .orange).frame(width: 10, height: 10)
                            Text(c.name)
                        }
                        .tag(c.hex)
                    }
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save Competitor") {
                    let confirmed = Int(confirmedCountText.filter(\.isNumber)) ?? 0
                    let rate = Double(monthlyRateText) ?? 25.0
                    competitorStore.addCompetitor(
                        callsign: callsign,
                        name: name,
                        confirmedCount: confirmed,
                        monthlyRate: rate,
                        colorHex: selectedColorHex
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(callsign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 380)
    }
}

// MARK: - Edit Competitor Modal Sheet

struct EditCompetitorModalView: View {
    @State var competitor: CompetitorStation
    @ObservedObject var competitorStore: CompetitorTrackingStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirmedCountText: String = ""
    @State private var monthlyRateText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(competitor.countryFlag)
                Text("Edit Competitor: \(competitor.callsign)")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Form {
                TextField("Operator Name:", text: $competitor.name)

                TextField("Confirmed QSOs:", text: $confirmedCountText)

                TextField("Monthly Rate (QSO/mo):", text: $monthlyRateText)

                TextField("Color Hex (e.g. #FF9500):", text: $competitor.colorHex)
            }
            .onAppear {
                confirmedCountText = "\(competitor.confirmedCount)"
                monthlyRateText = "\(competitor.monthlyGrowthRate)"
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Update") {
                    if let c = Int(confirmedCountText.filter(\.isNumber)) {
                        competitor.confirmedCount = c
                    }
                    if let r = Double(monthlyRateText) {
                        competitor.monthlyGrowthRate = r
                    }
                    competitorStore.updateCompetitor(competitor)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}
