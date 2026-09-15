//
//  ContestRateMatrixHUDView.swift
//  YAAM
//
//  Visual Contest Rate Speedometer & 2D Multiplier Matrix Dashboard.
//  Renders rolling 10m/60m rate speedometer, peak indicator, operating streaks,
//  and band-by-band multiplier distribution.
//

import Combine
import SwiftUI

public struct ContestRateMatrixHUDView: View {
    @ObservedObject private var engine = ContestRateMatrixEngine.shared
    public var activeBand: String

    public init(activeBand: String = "20M") {
        self.activeBand = activeBand
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Top Analytics Bar: Rate Speedometer & Key Metrics
            HStack(spacing: 12) {
                // Rate Speedometer Capsule
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.12), lineWidth: 4)
                            .frame(width: 44, height: 44)

                        Circle()
                            .trim(from: 0.0, to: min(1.0, CGFloat(engine.rolling10MinRate) / 180.0))
                            .stroke(
                                rateColor(engine.rolling10MinRate),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 44, height: 44)

                        VStack(spacing: 0) {
                            Text("\(engine.rolling10MinRate)")
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundColor(rateColor(engine.rolling10MinRate))
                            Text("/HR")
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("10m Rate:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(engine.rolling10MinRate)/h")
                                .font(.caption2.weight(.bold))
                        }
                        HStack(spacing: 4) {
                            Text("60m Rate:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(engine.rolling60MinRate)/h")
                                .font(.caption2.weight(.bold))
                        }
                        HStack(spacing: 4) {
                            Text("Peak:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(engine.peakHourlyRate)/h")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 8))

                Divider().frame(height: 48)

                // Contest Score & Multiplier Totals
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        metricTag(title: "TOTAL QSOS", value: "\(engine.totalQSOs)", color: .blue)
                        metricTag(title: "DXCC MULTS", value: "\(engine.totalDXCCMultipliers)", color: .orange)
                        metricTag(title: "ZONE MULTS", value: "\(engine.totalZoneMultipliers)", color: .purple)
                    }

                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill").font(.system(size: 8)).foregroundColor(.red)
                            Text("Streak: \(engine.currentStreak)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        }
                        Text("•")
                            .foregroundColor(.secondary)
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill").font(.system(size: 8)).foregroundColor(.green)
                            Text("On-Air: \(engine.totalOperatingMinutes)m")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        }
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("Proj 24h: \(formatScore(engine.projected24hScore))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }

                Spacer()
            }

            // 2D Band x Multiplier Matrix Table
            VStack(spacing: 2) {
                // Header row
                HStack(spacing: 4) {
                    Text("BAND")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 42, alignment: .leading)

                    ForEach(engine.bandSummaries) { s in
                        let isCurrent = s.band.uppercased() == activeBand.uppercased()
                        Text(s.band)
                            .font(.system(size: 8, weight: isCurrent ? .black : .bold, design: .monospaced))
                            .foregroundColor(isCurrent ? .orange : .secondary)
                            .frame(maxWidth: .infinity)
                    }

                    // TOTAL Column Header
                    Text("TOTAL")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(width: 46, alignment: .trailing)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)

                Divider().opacity(0.6)

                // Row: QSOs
                matrixRow(title: "QSOs", keyPath: \.qsoCount, total: "\(engine.totalQSOs)", highlightZeros: false, color: .primary)

                // Row: DXCC
                matrixRow(title: "DXCC", keyPath: \.dxccCount, total: "\(engine.totalDXCCMultipliers)", highlightZeros: true, color: .orange)

                // Row: Zones
                matrixRow(title: "Zones", keyPath: \.zoneCount, total: "\(engine.totalZoneMultipliers)", highlightZeros: true, color: .purple)

                // Row: Points
                matrixRow(title: "Points", keyPath: \.points, total: "\(engine.totalPoints)", highlightZeros: false, color: .green)
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.95))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private func matrixRow(title: String, keyPath: KeyPath<BandMultiplierSummary, Int>, total: String, highlightZeros: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 42, alignment: .leading)

            ForEach(engine.bandSummaries) { s in
                let val = s[keyPath: keyPath]
                let isCurrent = s.band.uppercased() == activeBand.uppercased()
                Text("\(val)")
                    .font(.system(size: 9, weight: isCurrent ? .bold : .medium, design: .monospaced))
                    .foregroundColor(val == 0 && highlightZeros ? .secondary.opacity(0.4) : (isCurrent ? color : .primary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 1)
                    .background(isCurrent ? color.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 3))
            }

            // Total Value Cell
            Text(total)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }

    private func metricTag(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
    }

    private func rateColor(_ rate: Int) -> Color {
        if rate >= 120 { return .red }
        if rate >= 80 { return .orange }
        if rate >= 40 { return .green }
        return .blue
    }

    private static let scoreFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private func formatScore(_ num: Int) -> String {
        Self.scoreFormatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }
}
