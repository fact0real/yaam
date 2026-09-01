//
//  BandmapView.swift
//  YAAM
//
//  Interactive Radio Spectrum Bandmap UI Component
//  Visual frequency scale with live VFO tracking, 1-click QSY transceiver tuning,
//  color-coded DXCC award status badges, and band plan mode segment overlays.
//

import Combine
import SwiftUI

public struct BandmapView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var bandmap = BandmapEngine.shared
    @ObservedObject private var flrig = FLRigClient.shared
    @ObservedObject private var tci = TCIClient.shared

    @State private var hoveredSpotID: UUID? = nil
    @State private var zoomLevel: CGFloat = 1.0

    private let availableBands = ["160M", "80M", "40M", "30M", "20M", "17M", "15M", "12M", "10M", "6M", "2M"]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar & Band Selector
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundColor(.blue)
                        .font(.title3)
                    Text("Interactive Bandmap")
                        .font(.headline)
                        .fontWeight(.bold)
                }

                Spacer()

                // Band Selector Segment
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(availableBands, id: \.self) { band in
                            Button {
                                bandmap.selectedBand = band
                            } label: {
                                Text(band)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(bandmap.selectedBand == band ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                                    .foregroundColor(bandmap.selectedBand == band ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 380)

                Divider().frame(height: 20)

                Toggle("New Only", isOn: $bandmap.filterNewOnly)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Frequency Ruler & Spots Canvas
            GeometryReader { geometry in
                let size = geometry.size
                let bandRange = bandmap.bandRangeKHz(for: bandmap.selectedBand)
                let segments = bandmap.bandPlanSegments(for: bandmap.selectedBand)
                let activeSpots = filteredSpots(bandRange: bandRange)
                let currentRigKHz = currentVFOFrequencyKHz

                ScrollView([.vertical]) {
                    ZStack(alignment: .topLeading) {
                        // Background Band Plan Segments
                        VStack(spacing: 0) {
                            ForEach(segments) { seg in
                                let h = heightForSegment(seg, range: bandRange, totalHeight: size.height * zoomLevel)
                                HStack {
                                    Text(seg.name)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary.opacity(0.7))
                                        .padding(.leading, 8)
                                    Spacer()
                                }
                                .frame(height: max(18, h))
                                .background(seg.color)
                                .border(Color.secondary.opacity(0.15), width: 0.5)
                            }
                        }

                        // Frequency Ruler Grid Lines & Labels
                        frequencyRuler(range: bandRange, totalHeight: size.height * zoomLevel)

                        // Current Radio VFO Indicator Line
                        if bandRange.contains(currentRigKHz) {
                            let yPos = yPosition(forKHz: currentRigKHz, range: bandRange, totalHeight: size.height * zoomLevel)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("VFO: \(String(format: "%.3f kHz", currentRigKHz))")
                                    .font(.caption2.bold().monospacedDigit())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red, in: Capsule())
                                Rectangle()
                                    .fill(Color.red.opacity(0.85))
                                    .frame(height: 1.8)
                            }
                            .offset(y: yPos - 9)
                        }

                        // Plotted DX Spots
                        ForEach(activeSpots) { spot in
                            let yPos = yPosition(forKHz: spot.frequencyKHz, range: bandRange, totalHeight: size.height * zoomLevel)
                            spotRow(spot: spot, yPos: yPos)
                        }
                    }
                    .frame(minHeight: max(size.height, 600 * zoomLevel))
                }
            }

            Divider()

            // Bottom Status & Legend Bar
            HStack(spacing: 16) {
                HStack(spacing: 12) {
                    legendPill(label: "New DXCC", color: .green)
                    legendPill(label: "New Band", color: .blue)
                    legendPill(label: "Unconfirmed", color: .orange)
                    legendPill(label: "Worked", color: .secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("Zoom:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        zoomLevel = max(0.8, zoomLevel - 0.2)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.plain)

                    Text("\(Int(zoomLevel * 100))%")
                        .font(.caption.monospacedDigit())

                    Button {
                        zoomLevel = min(3.0, zoomLevel + 0.2)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private var currentVFOFrequencyKHz: Double {
        if tci.isConnected {
            return Double(tci.vfoAFrequencyHz) / 1000.0
        } else if flrig.isConnected {
            return flrig.frequencyHz / 1000.0
        } else if let rigSnap = appState.rigControlClient.snapshot, let mhz = Double(rigSnap.frequencyMHz) {
            return mhz * 1000.0
        }
        return 14074.0
    }

    private func filteredSpots(bandRange: ClosedRange<Double>) -> [BandmapSpot] {
        return bandmap.spots.filter { spot in
            guard spot.band.uppercased() == bandmap.selectedBand.uppercased() || bandRange.contains(spot.frequencyKHz) else { return false }
            if bandmap.filterNewOnly && spot.status == .worked { return false }
            if !bandmap.searchText.isEmpty {
                return spot.callsign.localizedCaseInsensitiveContains(bandmap.searchText) || spot.comment.localizedCaseInsensitiveContains(bandmap.searchText)
            }
            return true
        }
    }

    private func yPosition(forKHz freq: Double, range: ClosedRange<Double>, totalHeight: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let progress = (freq - range.lowerBound) / span
        return CGFloat(progress) * totalHeight
    }

    private func heightForSegment(_ seg: BandPlanSegment, range: ClosedRange<Double>, totalHeight: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 20 }
        let segSpan = seg.endKHz - seg.startKHz
        return CGFloat(segSpan / span) * totalHeight
    }

    // MARK: - Frequency Ruler Lines

    @ViewBuilder
    private func frequencyRuler(range: ClosedRange<Double>, totalHeight: CGFloat) -> some View {
        let stepKHz: Double = (range.upperBound - range.lowerBound > 1000.0) ? 100.0 : 25.0
        let start = (range.lowerBound / stepKHz).rounded(.down) * stepKHz
        ForEach(Array(stride(from: start, through: range.upperBound, by: stepKHz)), id: \.self) { freq in
            let y = yPosition(forKHz: freq, range: range, totalHeight: totalHeight)
            HStack(spacing: 8) {
                Text(String(format: "%.1f", freq))
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 58, alignment: .trailing)
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 1)
            }
            .offset(y: y - 6)
        }
    }

    // MARK: - Spot Row

    private func spotRow(spot: BandmapSpot, yPos: CGFloat) -> some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 70)

            Button {
                tuneToSpot(spot)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(spot.status.color)
                        .frame(width: 8, height: 8)

                    Text(spot.callsign)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)

                    Text(spot.mode)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))

                    if !spot.dxccPrefix.isEmpty {
                        Text(spot.dxccPrefix)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    if !spot.comment.isEmpty {
                        Text(spot.comment)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("\(spot.ageMinutes)m ago")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(spot.status.color.opacity(0.75), lineWidth: 1.2)
                )
            }
            .buttonStyle(.plain)
            .opacity(spot.opacity)
            .help("Click to QSY radio to \(spot.callsign) on \(String(format: "%.3f kHz", spot.frequencyKHz)) (\(spot.mode))")
        }
        .offset(y: yPos - 14)
    }

    private func legendPill(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
        }
    }

    private func tuneToSpot(_ spot: BandmapSpot) {
        let hz = spot.frequencyKHz * 1000.0

        // 1. QSY Transceiver via TCI or FLRig if connected
        if tci.isConnected {
            tci.setFrequency(hz: UInt64(hz))
            tci.setMode(spot.mode)
        } else if flrig.isConnected {
            Task {
                try? await flrig.setFrequency(hz: hz)
                try? await flrig.setMode(spot.mode)
            }
        }

        // 2. Populate Quick Log draft
        appState.quickLogDraft.callsign = spot.callsign
        appState.quickLogDraft.frequencyMHz = String(format: "%.4f", spot.frequencyKHz / 1000.0)
        appState.quickLogDraft.band = spot.band
        appState.quickLogDraft.mode = spot.mode

        appState.appendLog("QSY to \(spot.callsign) at \(String(format: "%.3f kHz", spot.frequencyKHz)) [\(spot.mode)]")
    }
}
