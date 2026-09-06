//
//  DigitalContestBandMatrixView.swift
//  YAAM
//
//  Gold-Standard Real-Time Multiplier & Rate Engine Matrix for macOS.
//  Provides high-density band-by-band breakdowns, real-time rate meters (10m, 60m, peak),
//  multiplier explorer (Grid Fields & DXCC), and seamless Cabrillo 3.0 export.
//

import SwiftUI
import AppKit

public struct DigitalContestBandMatrixView: View {
    @ObservedObject public var engine: DigitalContestEngine
    public var onOpenCabrilloExport: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: MatrixTab = .matrix
    @State private var selectedBandFilter: String = "All"
    @State private var confirmReset: Bool = false

    public enum MatrixTab: String, CaseIterable, Identifiable {
        case matrix = "Band Matrix"
        case multipliers = "Multiplier Explorer"
        case qsoLog = "Contest QSOs"

        public var id: String { rawValue }
    }

    public init(engine: DigitalContestEngine, onOpenCabrilloExport: (() -> Void)? = nil) {
        self.engine = engine
        self.onOpenCabrilloExport = onOpenCabrilloExport
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Contest Header & Score Banner
            headerScoreBanner
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 2. Real-Time Rate & Velocity HUD
            rateMeterHUD
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // 3. Tab Selector
            tabBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 4. Main Tab Content
            Group {
                switch selectedTab {
                case .matrix:
                    bandMatrixTable
                case .multipliers:
                    multiplierExplorerView
                case .qsoLog:
                    contestQSOLogView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // 5. Bottom Action Strip
            bottomActionStrip
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        }
        .frame(minWidth: 700, minHeight: 460)
    }

    // MARK: - 1. Header & Score Banner

    private var headerScoreBanner: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.yellow)

                    Text(engine.contestTitle)
                        .font(.system(size: 14, weight: .bold))
                }

                HStack(spacing: 8) {
                    if !engine.myStationCall.isEmpty {
                        Text(engine.myStationCall)
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                    }
                    if !engine.myStationGrid.isEmpty {
                        Text(engine.myStationGrid)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(Color.orange)
                            .cornerRadius(3)
                    }
                    Text("• Serial: #\(engine.currentSerial)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Primary Score Display Card
            HStack(spacing: 16) {
                metricHeaderCard(
                    title: "CLAIMED SCORE",
                    value: engine.claimedScore.formatted(),
                    color: Color.yellow,
                    isMajor: true
                )

                metricHeaderCard(
                    title: "VALID QSOS",
                    value: "\(engine.totalQSOs)",
                    color: Color.green
                )

                metricHeaderCard(
                    title: "POINTS",
                    value: "\(engine.totalPoints)",
                    color: Color.primary
                )

                metricHeaderCard(
                    title: "TOTAL MULTS",
                    value: "\(engine.totalMultipliers)",
                    color: Color.orange
                )
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.defaultAction)
            .controlSize(.small)
        }
    }

    private func metricHeaderCard(title: String, value: String, color: Color, isMajor: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: isMajor ? 18 : 14, weight: .heavy, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.08))
        )
    }

    // MARK: - 2. Rate Meter HUD

    private var rateMeterHUD: some View {
        HStack(spacing: 12) {
            rateCard(
                icon: "speedometer",
                title: "10-MIN RATE",
                rate: engine.rate10Min,
                color: Color.green
            )

            rateCard(
                icon: "clock.arrow.circlepath",
                title: "60-MIN RATE",
                rate: engine.rate60Min,
                color: Color.cyan
            )

            rateCard(
                icon: "chart.line.uptrend.xyaxis",
                title: "PEAK RATE",
                rate: engine.peakRate,
                color: Color.purple
            )

            Divider()
                .frame(height: 24)

            HStack(spacing: 6) {
                Image(systemName: "number.square")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("AVG PTS / QSO")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f", engine.averagePointsPerQSO))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.yellow)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("PROJECTED FINAL")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(engine.projectedFinalScore.formatted())
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.yellow)
                }
            }
        }
    }

    private func rateCard(icon: String, title: String, rate: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(rate)")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(color)
                    Text("/hr")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.06))
        .cornerRadius(5)
    }

    // MARK: - 3. Tab Selector

    private var tabBar: some View {
        HStack {
            Picker("", selection: $selectedTab) {
                ForEach(MatrixTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 380)

            Spacer()

            if selectedTab == .multipliers {
                HStack(spacing: 6) {
                    Text("Band:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $selectedBandFilter) {
                        Text("All").tag("All")
                        ForEach(engine.contestType.bandsSupported, id: \.self) { (band: String) in
                            Text(band.uppercased()).tag(band)
                        }
                    }
                    .frame(width: 80)
                }
            }
        }
    }

    // MARK: - 4A. Band Matrix Table

    private var maxQSOsOnAnyBand: Int {
        let maxVal = engine.bandBreakdowns.map(\.qsoCount).max() ?? 0
        return max(1, maxVal)
    }

    private var bandMatrixTable: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Table Header
                HStack(spacing: 0) {
                    headerCell("BAND", width: 65, alignment: .leading)
                    headerCell("QSOS", width: 55, alignment: .trailing)
                    headerCell("DUPES", width: 55, alignment: .trailing)
                    headerCell("POINTS", width: 65, alignment: .trailing)
                    headerCell("GRID MULTS", width: 85, alignment: .trailing)
                    headerCell("DXCC MULTS", width: 85, alignment: .trailing)
                    headerCell("TOTAL MULTS", width: 85, alignment: .trailing)
                    headerCell("BAND SCORE", width: 95, alignment: .trailing)
                    Spacer()
                    headerCell("ACTIVITY SHARE", width: 110, alignment: .center)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))

                Divider()

                // Band Rows
                ForEach(engine.bandBreakdowns) { b in
                    bandRowView(b)
                    Divider()
                }

                // Summary Totals Row
                summaryTotalsRow
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.yellow.opacity(0.08))
            }
        }
    }

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
    }

    private func bandRowView(_ b: ContestBandBreakdown) -> some View {
        let isTopBand = b.qsoCount == maxQSOsOnAnyBand && b.qsoCount > 0
        return HStack(spacing: 0) {
            // Band Label
            Text(b.band.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(b.qsoCount > 0 ? Color.accentColor : Color.secondary)
                .frame(width: 65, alignment: .leading)

            // QSOs
            Text("\(b.qsoCount)")
                .font(.system(size: 11, weight: b.qsoCount > 0 ? .bold : .regular, design: .monospaced))
                .foregroundStyle(b.qsoCount > 0 ? Color.primary : Color.secondary.opacity(0.6))
                .frame(width: 55, alignment: .trailing)

            // Dupes
            Text("\(b.dupeCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(b.dupeCount > 0 ? Color.red.opacity(0.8) : Color.secondary.opacity(0.3))
                .frame(width: 55, alignment: .trailing)

            // Points
            Text("\(b.qsoPoints)")
                .font(.system(size: 11, weight: b.qsoPoints > 0 ? .bold : .regular, design: .monospaced))
                .foregroundStyle(b.qsoPoints > 0 ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 65, alignment: .trailing)

            // Grid Mults
            HStack(spacing: 4) {
                Text("\(b.gridMultCount)")
                    .font(.system(size: 11, weight: b.gridMultCount > 0 ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(b.gridMultCount > 0 ? Color.orange : Color.secondary.opacity(0.5))
            }
            .frame(width: 85, alignment: .trailing)

            // DXCC Mults
            Text("\(b.dxccMultCount)")
                .font(.system(size: 11, weight: b.dxccMultCount > 0 ? .bold : .regular, design: .monospaced))
                .foregroundStyle(b.dxccMultCount > 0 ? Color.blue : Color.secondary.opacity(0.5))
                .frame(width: 85, alignment: .trailing)

            // Total Mults
            Text("\(b.totalMults)")
                .font(.system(size: 11, weight: b.totalMults > 0 ? .heavy : .regular, design: .monospaced))
                .foregroundStyle(b.totalMults > 0 ? Color.yellow : Color.secondary.opacity(0.5))
                .frame(width: 85, alignment: .trailing)

            // Band Score
            Text(b.bandScore.formatted())
                .font(.system(size: 11, weight: b.bandScore > 0 ? .bold : .regular, design: .monospaced))
                .foregroundStyle(b.bandScore > 0 ? Color.yellow : Color.secondary.opacity(0.5))
                .frame(width: 95, alignment: .trailing)

            Spacer()

            // Progress Bar / Relative Share
            GeometryReader { geo in
                let fraction = CGFloat(b.qsoCount) / CGFloat(maxQSOsOnAnyBand)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 6)

                    Capsule()
                        .fill(isTopBand ? Color.yellow : Color.accentColor)
                        .frame(width: max(2, geo.size.width * fraction), height: 6)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 110, height: 16)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isTopBand ? Color.yellow.opacity(0.04) : Color.clear)
    }

    private var summaryTotalsRow: some View {
        let totalDupes = engine.bandBreakdowns.reduce(0) { $0 + $1.dupeCount }

        return HStack(spacing: 0) {
            Text("TOTAL")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.yellow)
                .frame(width: 65, alignment: .leading)

            Text("\(engine.totalQSOs)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.primary)
                .frame(width: 55, alignment: .trailing)

            Text("\(totalDupes)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(totalDupes > 0 ? Color.red : Color.secondary)
                .frame(width: 55, alignment: .trailing)

            Text("\(engine.totalPoints)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.green)
                .frame(width: 65, alignment: .trailing)

            Text("\(engine.totalGridMultipliers)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.orange)
                .frame(width: 85, alignment: .trailing)

            Text("\(engine.totalDXCCMultipliers)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.blue)
                .frame(width: 85, alignment: .trailing)

            Text("\(engine.totalMultipliers)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.yellow)
                .frame(width: 85, alignment: .trailing)

            Text(engine.claimedScore.formatted())
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.yellow)
                .frame(width: 95, alignment: .trailing)

            Spacer()

            Text("SCORE: \(engine.claimedScore.formatted())")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.yellow)
                .frame(width: 110, alignment: .center)
        }
    }

    // MARK: - 4B. Multiplier Explorer

    private var relevantBandsForExplorer: [ContestBandBreakdown] {
        if selectedBandFilter == "All" {
            return engine.bandBreakdowns
        }
        return engine.bandBreakdowns.filter { $0.band.lowercased() == selectedBandFilter.lowercased() }
    }

    private var multiplierExplorerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(relevantBandsForExplorer) { bandSummary in
                    VStack(alignment: .leading, spacing: 8) {
                        // Band Subheader
                        HStack(spacing: 8) {
                            Text(bandSummary.band.uppercased())
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundStyle(Color.accentColor)

                            Text("• \(bandSummary.gridMultCount) Grid Fields")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.orange)

                            Text("• \(bandSummary.dxccMultCount) DXCC Entities")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.blue)

                            Spacer()
                        }
                        .padding(.bottom, 2)

                        // 1. Grid Fields Badges
                        if !bandSummary.gridFields.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Worked Maidenhead Grid Fields:")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 6)], spacing: 6) {
                                    ForEach(bandSummary.gridFields.sorted(), id: \.self) { field in
                                        Text(field)
                                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.orange.opacity(0.18))
                                            .foregroundStyle(Color.orange)
                                            .cornerRadius(4)
                                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.orange.opacity(0.4), lineWidth: 1))
                                    }
                                }
                            }
                        }

                        // 2. DXCC Entities
                        if !bandSummary.dxccEntities.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Worked DXCC Countries:")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], spacing: 6) {
                                    ForEach(bandSummary.dxccEntities.sorted(), id: \.self) { country in
                                        HStack(spacing: 4) {
                                            Image(systemName: "globe.europe.africa.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(Color.blue)
                                            Text(country)
                                                .font(.system(size: 10, weight: .medium))
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.blue.opacity(0.12))
                                        .cornerRadius(4)
                                    }
                                }
                            }
                        }

                        if bandSummary.gridFields.isEmpty && bandSummary.dxccEntities.isEmpty {
                            Text("No multipliers logged yet on \(bandSummary.band.uppercased()).")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                            .padding(.top, 4)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - 4C. Contest QSO Log View

    private var contestQSOLogView: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if engine.qsoLog.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("No contest QSOs logged yet in this session.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
                } else {
                    ForEach(engine.qsoLog.reversed()) { qso in
                        qsoRow(qso)
                    }
                }
            }
            .padding(14)
        }
    }

    private func qsoRow(_ qso: ContestQSOEntry) -> some View {
        HStack(spacing: 8) {
            Text(qso.timestamp, style: .time)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            Text(qso.band.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, alignment: .leading)

            Text(qso.mode)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)

            Text(qso.countryFlag)
                .font(.system(size: 12))

            Text(qso.callsign)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .frame(width: 80, alignment: .leading)

            if let g = qso.grid {
                Text(g)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.orange)
                    .frame(width: 48, alignment: .leading)
            } else {
                Spacer().frame(width: 48)
            }

            Text("\(qso.sentExchange) -> \(qso.rcvdExchange)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            if qso.isGridMultiplier {
                Text("GRID MULT")
                    .font(.system(size: 8, weight: .heavy))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .foregroundStyle(.black)
                    .cornerRadius(3)
            }

            if qso.isDXCCMultiplier {
                Text("DXCC MULT")
                    .font(.system(size: 8, weight: .heavy))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(3)
            }

            Text("+\(qso.points) PTS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor).opacity(0.3)))
    }

    // MARK: - 5. Bottom Action Strip

    private var bottomActionStrip: some View {
        HStack(spacing: 12) {
            if let onOpenCabrilloExport {
                Button {
                    onOpenCabrilloExport()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up.fill")
                        Text("Export Official Cabrillo 3.0...")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
            }

            Spacer()

            if confirmReset {
                HStack(spacing: 8) {
                    Text("Reset this contest session?")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)

                    Button("Confirm Reset", role: .destructive) {
                        engine.resetContestSession()
                        confirmReset = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)

                    Button("Cancel") {
                        confirmReset = false
                    }
                    .controlSize(.small)
                }
            } else {
                Button {
                    confirmReset = true
                } label: {
                    Label("Reset Session...", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
