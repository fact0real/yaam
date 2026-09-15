//
//  BandmapView.swift
//  YAAM
//
//  Interactive Radio Spectrum Bandmap & Live Waterfall Studio
//  3-Pane Pro Layout: Vertical Bandmap Ruler + SDR Spectrum/Waterfall + DX Spot Hunter Table.
//  Includes IARU Region & License Class privilege filtering, dual VFO & Split tracking,
//  thermal activity heatmap ribbon, 1-click QSY & double-click log, and Multi-Band Panorama.
//

import Combine
import SwiftUI

// MARK: - Bandmap Studio View Mode

public enum BandmapStudioMode: String, CaseIterable, Identifiable {
    case studio = "Studio (3-Pane)"
    case rulerOnly = "Ruler & Spots"
    case waterfallOnly = "SDR Waterfall"
    case panorama = "Multi-Band Panorama"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .studio: return "square.split.3x1"
        case .rulerOnly: return "ruler"
        case .waterfallOnly: return "waveform.path.ecg"
        case .panorama: return "square.grid.2x2"
        }
    }
}

// MARK: - Center Deck Mode (Radar & Activity vs. Smooth Waterfall)

public enum CenterDeckMode: String, CaseIterable, Identifiable {
    case radar = "Radar & Activity"
    case waterfall = "Smooth Waterfall"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .radar: return "antenna.radiowaves.left.and.right"
        case .waterfall: return "waveform.path.ecg"
        }
    }
}

// MARK: - Main Bandmap View

public struct BandmapView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var bandmap = BandmapEngine.shared
    @ObservedObject private var flrig = FLRigClient.shared
    @ObservedObject private var tci = TCIClient.shared

    @State private var studioMode: BandmapStudioMode = .studio
    @State private var centerDeckMode: CenterDeckMode = .radar
    @State private var zoomLevel: CGFloat = 1.0
    @State private var hoveredSpotID: UUID? = nil
    @State private var selectedSpotID: UUID? = nil
    @State private var hoverSpectrumX: CGFloat? = nil
    @State private var hoverSpectrumKHz: Double? = nil
    @State private var spotFilterMode: String = "ALL" // ALL, FRESH, NEW_DXCC, FT8, CW, SSB
    @State private var quickToastMessage: String? = nil
    @State private var showCATPopover: Bool = false

    // Animation timer for SDR noise and waterfall phase
    @State private var animationPhase: Double = 0.0
    private static let animationTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private static let availableBands = ["160M", "80M", "60M", "40M", "30M", "20M", "17M", "15M", "12M", "10M", "6M", "2M"]
    private static let panoramaBands = ["40M", "20M", "15M", "10M"]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Floating Glassmorphism HUD Bar
            hudHeaderBar

            Divider()

            // Main Studio Content Pane based on View Mode
            GeometryReader { geo in
                switch studioMode {
                case .studio:
                    HStack(spacing: 0) {
                        // Left Pane: Bandmap Ruler & Plotted Spots
                        verticalRulerPane(size: geo.size)
                            .frame(width: max(280, min(330, geo.size.width * 0.28)))

                        Divider()

                        // Center Pane: Live SDR Spectrum & Waterfall Studio
                        liveSpectrumWaterfallPane(size: geo.size)
                            .frame(maxWidth: .infinity)

                        Divider()

                        // Right Pane: Active DX Spot Hunter Table & Inspector
                        spotHunterTablePane(size: geo.size)
                            .frame(width: max(320, min(380, geo.size.width * 0.32)))
                    }

                case .rulerOnly:
                    HStack(spacing: 0) {
                        verticalRulerPane(size: geo.size)
                            .frame(maxWidth: .infinity)
                        Divider()
                        spotHunterTablePane(size: geo.size)
                            .frame(width: 360)
                    }

                case .waterfallOnly:
                    liveSpectrumWaterfallPane(size: geo.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .panorama:
                    multiBandPanoramaView(size: geo.size)
                }
            }

            Divider()

            // Bottom Status, Legend & Split Control Footer
            bottomStudioFooter
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .top) {
            if let msg = quickToastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(msg)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.green.opacity(0.5), lineWidth: 1))
                .shadow(radius: 6)
                .padding(.top, 50)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(Self.animationTimer) { _ in
            animationPhase += 0.2
        }
    }

    // MARK: - Floating Glassmorphism HUD Header

    private var hudHeaderBar: some View {
        HStack(spacing: 12) {
            // App Branding & Title
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .foregroundColor(.cyan)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Interactive Bandmap Studio")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text("Live Spectrum · Dual VFO · Heatmap Ribbon")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Band Pills Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Self.availableBands, id: \.self) { band in
                        Button {
                            bandmap.selectedBand = band
                        } label: {
                            Text(band)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    bandmap.selectedBand == band ? Color.cyan : Color(NSColor.controlBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(bandmap.selectedBand == band ? Color.cyan : Color.secondary.opacity(0.18), lineWidth: 0.8)
                                )
                                .foregroundColor(bandmap.selectedBand == band ? .black : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 420)

            Divider().frame(height: 20)

            // IARU Region Selector
            Menu {
                ForEach(IARURegion.allCases, id: \.self) { region in
                    Button {
                        bandmap.iaruRegion = region
                    } label: {
                        HStack {
                            Text(region.rawValue)
                            if bandmap.iaruRegion == region {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe.europe.africa.fill")
                        .foregroundColor(.cyan)
                    Text(bandmap.iaruRegion.shortTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 0.8)
                )
            }
            .menuStyle(.borderlessButton)

            // License Class Selector
            Menu {
                ForEach(LicenseClass.allCases, id: \.self) { lic in
                    Button {
                        bandmap.licenseClass = lic
                    } label: {
                        HStack {
                            Text(lic.rawValue)
                            if bandmap.licenseClass == lic {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .foregroundColor(.green)
                    Text(bandmap.licenseClass.shortTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 0.8)
                )
            }
            .menuStyle(.borderlessButton)

            Divider().frame(height: 20)

            // View Mode Picker
            Picker("", selection: $studioMode) {
                ForEach(BandmapStudioMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 330)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Left Pane: Vertical Bandmap Ruler & Spots

    @ViewBuilder
    private func verticalRulerPane(size: CGSize) -> some View {
        let bandRange = bandmap.bandRangeKHz(for: bandmap.selectedBand, region: bandmap.iaruRegion)
        let segments = bandmap.bandPlanSegments(for: bandmap.selectedBand, region: bandmap.iaruRegion, license: bandmap.licenseClass)
        let activeSpots = filteredSpots(bandRange: bandRange)
        let totalHeight = max(size.height - 40, 700 * zoomLevel)
        let vfoAKHz = currentVFOAFrequencyKHz
        let vfoBKHz = currentVFOBFrequencyKHz
        let densityBins = bandmap.activityDensity(band: bandmap.selectedBand)

        VStack(spacing: 0) {
            // Pane Subheader
            HStack {
                Text("\(bandmap.selectedBand) RULER")
                    .font(.caption.bold())
                    .foregroundColor(.cyan)
                Spacer()
                Text("\(activeSpots.count) Spots")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView([.vertical]) {
                ZStack(alignment: .topLeading) {
                    // 1. Background Band Plan Segments with License Caution Shading
                    VStack(spacing: 0) {
                        ForEach(segments) { seg in
                            let h = heightForSegment(seg, range: bandRange, totalHeight: totalHeight)
                            let permitted = seg.isPermitted(for: bandmap.licenseClass)

                            HStack(spacing: 6) {
                                Rectangle()
                                    .fill(seg.color)
                                    .frame(width: 4)

                                Text(seg.name)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(permitted ? .primary : .red)

                                Spacer()

                                if !permitted {
                                    HStack(spacing: 2) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                        Text("RESTRICTED")
                                    }
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.red.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            .padding(.horizontal, 6)
                            .frame(height: max(20, h))
                            .background(
                                permitted ?
                                seg.color.opacity(0.12) :
                                Color.red.opacity(0.15)
                            )
                            .border(Color.secondary.opacity(0.15), width: 0.5)
                        }
                    }

                    // 2. Activity Heatmap Ribbon (Left 8px)
                    activityHeatmapRibbon(bins: densityBins, range: bandRange, totalHeight: totalHeight)

                    // 3. Frequency Ruler Grid Lines & Graduation Labels
                    frequencyRulerGrid(range: bandRange, totalHeight: totalHeight)

                    // 4. Split Mode Bracket (Between VFO-A and VFO-B)
                    if bandmap.isSplitActive && bandRange.contains(vfoAKHz) && bandRange.contains(vfoBKHz) {
                        let yA = yPosition(forKHz: vfoAKHz, range: bandRange, totalHeight: totalHeight)
                        let yB = yPosition(forKHz: vfoBKHz, range: bandRange, totalHeight: totalHeight)
                        splitBracketIndicator(yA: yA, yB: yB, offsetKHz: vfoBKHz - vfoAKHz)
                    }

                    // 4.1. Pileup Sniper Target Reticle
                    if let sniper = bandmap.activeSniperSolution, sniper.isSplit, bandRange.contains(sniper.recommendedTxKHz) {
                        let ySniper = yPosition(forKHz: sniper.recommendedTxKHz, range: bandRange, totalHeight: totalHeight)
                        sniperTargetReticle(yPos: ySniper, solution: sniper)
                    }

                    // 5. VFO-A (RX) Indicator
                    if bandRange.contains(vfoAKHz) {
                        let yA = yPosition(forKHz: vfoAKHz, range: bandRange, totalHeight: totalHeight)
                        vfoCursorLine(
                            label: "RX \(String(format: "%.2f", vfoAKHz))",
                            color: .cyan,
                            icon: "antenna.radiowaves.left.and.right",
                            yPos: yA
                        )
                    }

                    // 6. VFO-B (TX) Indicator (If Split Active)
                    if bandmap.isSplitActive && bandRange.contains(vfoBKHz) {
                        let yB = yPosition(forKHz: vfoBKHz, range: bandRange, totalHeight: totalHeight)
                        vfoCursorLine(
                            label: "TX \(String(format: "%.2f", vfoBKHz))",
                            color: .orange,
                            icon: "bolt.horizontal.fill",
                            yPos: yB
                        )
                    }

                    // 7. Plotted DX Spot Cards
                    ForEach(activeSpots) { spot in
                        let yPos = yPosition(forKHz: spot.frequencyKHz, range: bandRange, totalHeight: totalHeight)
                        rulerSpotCard(spot: spot, yPos: yPos)
                    }
                }
                .frame(minHeight: totalHeight)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - Activity Heatmap Ribbon

    @ViewBuilder
    private func activityHeatmapRibbon(
        bins: [(freq: Double, density: Double)],
        range: ClosedRange<Double>,
        totalHeight: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(bins, id: \.freq) { bin in
                let y = yPosition(forKHz: bin.freq, range: range, totalHeight: totalHeight)
                let height = max(6, (25.0 / (range.upperBound - range.lowerBound)) * totalHeight)

                Rectangle()
                    .fill(thermalColor(for: bin.density))
                    .frame(width: 8, height: height)
                    .offset(y: y)
                    .help(String(format: "Activity Density at %.1f kHz: %.0f%%", bin.freq, bin.density * 100))
            }
        }
    }

    private func thermalColor(for density: Double) -> Color {
        if density < 0.1 {
            return Color.clear
        } else if density < 0.3 {
            return Color.blue.opacity(0.6)
        } else if density < 0.6 {
            return Color.cyan.opacity(0.8)
        } else if density < 0.85 {
            return Color.yellow.opacity(0.9)
        } else {
            return Color.red
        }
    }

    // MARK: - Frequency Ruler Grid

    @ViewBuilder
    private func frequencyRulerGrid(range: ClosedRange<Double>, totalHeight: CGFloat) -> some View {
        let span = range.upperBound - range.lowerBound
        let stepKHz: Double = span > 1000.0 ? 100.0 : (span > 300.0 ? 50.0 : 25.0)
        let start = (range.lowerBound / stepKHz).rounded(.down) * stepKHz

        ForEach(Array(stride(from: start, through: range.upperBound, by: stepKHz)), id: \.self) { freq in
            let y = yPosition(forKHz: freq, range: range, totalHeight: totalHeight)
            HStack(spacing: 6) {
                Spacer().frame(width: 10)
                Text(String(format: "%.1f", freq))
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 52, alignment: .trailing)
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 1)
            }
            .offset(y: y - 6)
        }
    }

    // MARK: - VFO Cursor & Split Visuals

    private func vfoCursorLine(label: String, color: Color, icon: String, yPos: CGFloat) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 10)
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                Text(label)
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
            .shadow(color: color.opacity(0.8), radius: 4)

            Rectangle()
                .fill(color)
                .frame(height: 2)
                .shadow(color: color.opacity(0.8), radius: 3)
        }
        .offset(y: yPos - 10)
    }

    private func splitBracketIndicator(yA: CGFloat, yB: CGFloat, offsetKHz: Double) -> some View {
        let top = min(yA, yB)
        let bottom = max(yA, yB)
        let height = max(4, bottom - top)

        return HStack(spacing: 4) {
            Spacer().frame(width: 74)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 1.5)
                Rectangle()
                    .fill(Color.orange.opacity(0.7))
                    .frame(width: 2, height: height)
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 1.5)
            }
            Text(String(format: "%@%.2f kHz", offsetKHz >= 0 ? "+" : "", offsetKHz))
                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                .foregroundColor(.orange)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
        }
        .offset(y: top)
    }

    private func sniperTargetReticle(yPos: CGFloat, solution: PileupSniperSolution) -> some View {
        HStack(spacing: 4) {
            Spacer().frame(width: 74)
            HStack(spacing: 3) {
                Image(systemName: "scope")
                    .font(.system(size: 8.5, weight: .bold))
                Text("SNIPER \(solution.offsetSignFormatted)")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 3))
            .shadow(color: Color.yellow.opacity(0.6), radius: 3)
            .onTapGesture {
                bandmap.applySniperSolution(solution)
            }
            .help("Click to arm VFO-B to Sniper Target (\(solution.frequencyFormattedMHz))")

            Rectangle()
                .fill(Color.yellow.opacity(0.85))
                .frame(height: 1.5)
                .shadow(color: Color.yellow.opacity(0.8), radius: 2)
        }
        .offset(y: yPos - 9)
    }

    // MARK: - Spot Card on Ruler

    private func rulerSpotCard(spot: BandmapSpot, yPos: CGFloat) -> some View {
        let flag = DXCCDatabase.resolve(callsign: spot.callsign).flagEmoji

        return HStack(spacing: 6) {
            Spacer().frame(width: 74)

            Button {
                tuneToSpot(spot)
            } label: {
                HStack(spacing: 6) {
                    // Pulsing fresh dot or status indicator
                    if spot.isFresh {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 6, height: 6)
                            .overlay(Circle().stroke(Color.cyan.opacity(0.6), lineWidth: 2).scaleEffect(1.4))
                    } else {
                        Circle()
                            .fill(spot.status.color)
                            .frame(width: 6, height: 6)
                    }

                    Text(flag)
                        .font(.caption2)

                    Text(spot.callsign)
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)

                    Text(spot.mode)
                        .font(.system(size: 8.5, weight: .black))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))

                    if let snr = spot.snr {
                        Text(String(format: "%+d", snr))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(snr >= 0 ? .green : .orange)
                    }

                    Spacer()

                    Text("\(spot.ageMinutes)m")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(colorScheme == .dark ? Color(red: 0.10, green: 0.13, blue: 0.20).opacity(0.95) : Color(NSColor.controlBackgroundColor))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 2, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(spot.status.color.opacity(0.8), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .opacity(spot.opacity)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    fillQuickLogAndFocus(spot: spot)
                }
            )
            .help("Click to QSY radio | Double-click to Log (\(spot.callsign))")
        }
        .offset(y: yPos - 12)
    }

    // MARK: - Center Pane: Live SDR Spectrum & Waterfall Studio

    private var isCATConnected: Bool {
        tci.isConnected || flrig.isConnected || appState.rigControlClient.state.isConnected
    }

    @ViewBuilder
    private func liveSpectrumWaterfallPane(size: CGSize) -> some View {
        let bandRange = bandmap.bandRangeKHz(for: bandmap.selectedBand, region: bandmap.iaruRegion)
        let activeSpots = filteredSpots(bandRange: bandRange)
        let vfoAKHz = currentVFOAFrequencyKHz
        let vfoBKHz = currentVFOBFrequencyKHz
        let segments = bandmap.bandPlanSegments(for: bandmap.selectedBand, region: bandmap.iaruRegion, license: bandmap.licenseClass)
        let spectrumH = max(160, min(240, size.height * 0.36))

        VStack(spacing: 0) {
            // 1. Center Header with Status, Rig Control Widget, Dial readout, and Deck Mode Picker
            centerHUDHeader(vfoAKHz: vfoAKHz, vfoBKHz: vfoBKHz)

            Divider()

            // 2. Panadapter Spectrum View (Upper half)
            panadapterSpectrumView(bandRange: bandRange, activeSpots: activeSpots, vfoAKHz: vfoAKHz, vfoBKHz: vfoBKHz, height: spectrumH)

            // 3. Horizontal IARU Band Plan Ribbon
            bandPlanHorizontalRibbon(segments: segments, bandRange: bandRange)

            Divider()

            // 4. Lower Deck: Either Radar & Activity + Inspector OR Smooth Waterfall
            if centerDeckMode == .radar {
                centerRadarAndInspectorView(bandRange: bandRange, activeSpots: activeSpots, size: size)
            } else {
                smoothWaterfallView(bandRange: bandRange, activeSpots: activeSpots, vfoAKHz: vfoAKHz, vfoBKHz: vfoBKHz)
            }
        }
    }

    @ViewBuilder
    private func centerHUDHeader(vfoAKHz: Double, vfoBKHz: Double) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isCATConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(isCATConnected ? "LIVE SDR SPECTRUM & PANADAPTER" : "DX CLUSTER SPECTRUM PANADAPTER · STANDBY")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.primary)

                if !isCATConnected {
                    Text("(CAT OFFLINE)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }
            }

            Spacer()

            // Direct CAT Hardware Quick-Connect / Setup button
            Button {
                showCATPopover.toggle()
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(isCATConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(isCATConnected ? "CAT Online" : "CAT Setup")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isCATConnected ? .green : .orange)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(isCATConnected ? Color.green.opacity(0.12) : Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(isCATConnected ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCATPopover) {
                RigConfigPopoverView(rig: RigControlEngine.shared)
            }

            Divider().frame(height: 18)

            // Deck Mode Picker (Radar & Activity vs. Smooth Waterfall)
            Picker("", selection: $centerDeckMode) {
                ForEach(CenterDeckMode.allCases) { deck in
                    Label(deck.rawValue, systemImage: deck.icon).tag(deck)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)

            Divider().frame(height: 18)

            // Dial readout
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("VFO-A:")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.cyan)
                    Text(String(format: "%.3f kHz", vfoAKHz))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }

                if bandmap.isSplitActive {
                    HStack(spacing: 4) {
                        Text("VFO-B (TX):")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.orange)
                        Text(String(format: "%.3f kHz", vfoBKHz))
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.18), lineWidth: 0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func panadapterSpectrumView(
        bandRange: ClosedRange<Double>,
        activeSpots: [BandmapSpot],
        vfoAKHz: Double,
        vfoBKHz: Double,
        height: CGFloat
    ) -> some View {
        GeometryReader { specGeo in
            let width = specGeo.size.width
            ZStack(alignment: .topLeading) {
                // 1. RF Canvas with Gaussian curves, S-meter scales & Frequency ticks
                Canvas { context, sz in
                    drawSpectrumGraph(context: context, size: sz, range: bandRange, spots: activeSpots, phase: animationPhase)
                }
                .frame(width: width, height: height)
                .background(colorScheme == .dark ? Color(red: 0.03, green: 0.05, blue: 0.08) : Color(red: 0.04, green: 0.07, blue: 0.12))

                // 2. Interactive Crosshair on Hover
                if let hoverX = hoverSpectrumX, let hoverFreq = hoverSpectrumKHz {
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 1, height: height)
                        .position(x: hoverX, y: height / 2)

                    Text(String(format: "%.3f kHz", hoverFreq))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.07, green: 0.09, blue: 0.14).opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cyan.opacity(0.6), lineWidth: 0.8))
                        .position(x: max(45, min(width - 45, hoverX)), y: 14)
                }

                // 3. VFO-A Reticle & Passband
                if bandRange.contains(vfoAKHz) {
                    let xA = xPosition(forKHz: vfoAKHz, range: bandRange, width: width)
                    sdrCursorReticle(xPos: xA, height: height, label: "VFO-A (RX)", color: .cyan)
                }

                // 4. VFO-B (TX) Reticle
                if bandmap.isSplitActive && bandRange.contains(vfoBKHz) {
                    let xB = xPosition(forKHz: vfoBKHz, range: bandRange, width: width)
                    sdrCursorReticle(xPos: xB, height: height, label: "VFO-B (TX)", color: .orange)
                }

                // 5. Staggered Anti-Collision Spot Pins
                ForEach(Array(activeSpots.enumerated()), id: \.element.id) { index, spot in
                    let x = xPosition(forKHz: spot.frequencyKHz, range: bandRange, width: width)
                    let yStagger: CGFloat = 20 + CGFloat((index % 3) * 22)
                    let isSelected = selectedSpotID == spot.id
                    Button {
                        selectedSpotID = spot.id
                    } label: {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(spot.status.color)
                                .frame(width: 5, height: 5)
                            Text(spot.callsign)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text(spot.mode)
                                .font(.system(size: 7.5, weight: .heavy))
                                .foregroundColor(spot.status.color)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(red: 0.10, green: 0.13, blue: 0.20).opacity(isSelected ? 0.98 : 0.85))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? Color.white : spot.status.color.opacity(0.7), lineWidth: isSelected ? 1.5 : 0.8)
                        )
                        .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHov in
                        if isHov {
                            hoveredSpotID = spot.id
                        } else if hoveredSpotID == spot.id {
                            hoveredSpotID = nil
                        }
                    }
                    .position(x: x, y: yStagger)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverSpectrumX = location.x
                    hoverSpectrumKHz = khzForX(location.x, range: bandRange, width: width)
                case .ended:
                    hoverSpectrumX = nil
                    hoverSpectrumKHz = nil
                }
            }
            .onTapGesture { location in
                let clickedKHz = khzForX(location.x, range: bandRange, width: width)
                tuneToFrequency(khz: clickedKHz)
            }
        }
        .frame(height: height)
    }

    private func sdrCursorReticle(xPos: CGFloat, height: CGFloat, label: String, color: Color) -> some View {
        ZStack(alignment: .top) {
            // Passband filter shadow (approx 2.4 kHz)
            Rectangle()
                .fill(color.opacity(0.18))
                .frame(width: 16, height: height)
                .position(x: xPos, y: height / 2)

            // Center tuning needle
            Rectangle()
                .fill(color)
                .frame(width: 1.5, height: height)
                .position(x: xPos, y: height / 2)

            // Header tag
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(color, in: RoundedRectangle(cornerRadius: 3))
                .position(x: xPos, y: 8)
        }
    }

    @ViewBuilder
    private func bandPlanHorizontalRibbon(segments: [BandPlanSegment], bandRange: ClosedRange<Double>) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 1) {
                ForEach(segments) { seg in
                    let startX = xPosition(forKHz: seg.startKHz, range: bandRange, width: width)
                    let endX = xPosition(forKHz: seg.endKHz, range: bandRange, width: width)
                    let segW = max(2, endX - startX)

                    ZStack {
                        seg.color.opacity(0.22)

                        if segW > 45 {
                            Text(seg.name)
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundColor(seg.color)
                                .lineLimit(1)
                        }
                    }
                    .frame(width: segW)
                    .overlay(Rectangle().stroke(seg.color.opacity(0.4), lineWidth: 0.5))
                    .help("\(seg.name): \(String(format: "%.1f - %.1f kHz", seg.startKHz, seg.endKHz))")
                }
            }
        }
        .frame(height: 16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func centerRadarAndInspectorView(
        bandRange: ClosedRange<Double>,
        activeSpots: [BandmapSpot],
        size: CGSize
    ) -> some View {
        HStack(spacing: 10) {
            // Left: Band Activity Radar Card
            bandActivityRadarCard(activeSpots: activeSpots, bandRange: bandRange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Right: Spot Inspector & Geodesic Intelligence Card
            spotInspectorCard(activeSpots: activeSpots)
                .frame(width: max(320, min(400, size.width * 0.40)))
                .frame(maxHeight: .infinity)
        }
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func bandActivityRadarCard(activeSpots: [BandmapSpot], bandRange: ClosedRange<Double>) -> some View {
        let cwCount = activeSpots.filter { $0.mode.uppercased() == "CW" }.count
        let digiCount = activeSpots.filter { $0.mode.uppercased().contains("FT8") || $0.mode.uppercased().contains("DATA") || $0.mode.uppercased() == "RTTY" }.count
        let phoneCount = activeSpots.filter { $0.mode.uppercased() == "USB" || $0.mode.uppercased() == "LSB" || $0.mode.uppercased() == "SSB" || $0.mode.uppercased() == "AM" || $0.mode.uppercased() == "FM" }.count
        let total = max(1, activeSpots.count)
        let presets = bandCallingPresets(for: bandmap.selectedBand)

        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.cyan)
                    Text("BAND ACTIVITY RADAR")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                }

                Spacer()

                Text("\(activeSpots.count) Active Spots on \(bandmap.selectedBand)")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            // Mode Distribution Progress Bars
            VStack(spacing: 5) {
                activityBarRow(title: "CW Mode", count: cwCount, total: total, color: .yellow)
                activityBarRow(title: "Digital / FT8", count: digiCount, total: total, color: .green)
                activityBarRow(title: "Phone (SSB)", count: phoneCount, total: total, color: .orange)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

            // Quick Calling Frequency Presets
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 9))
                    Text("Quick Calling Frequencies (1-Tap QSY):")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.primary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], spacing: 6) {
                    ForEach(presets, id: \.freqKHz) { preset in
                        Button {
                            tuneToFrequency(khz: preset.freqKHz, mode: preset.mode)
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(preset.mode == "CW" ? Color.yellow : (preset.mode.contains("FT8") ? Color.green : Color.orange))
                                    .frame(width: 5, height: 5)
                                Text(preset.label)
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.cyan.opacity(0.8))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                        .help("1-click QSY to \(preset.label)")
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func activityBarRow(title: String, count: Int, total: Int, color: Color) -> some View {
        let frac = CGFloat(count) / CGFloat(total)
        return HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            GeometryReader { barGeo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: barGeo.size.width * frac)
                }
            }
            .frame(height: 6)

            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 24, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func spotInspectorCard(activeSpots: [BandmapSpot]) -> some View {
        let spot = inspectedSpot

        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .foregroundColor(.cyan)
                    Text("SPOT INSPECTOR & GEODESIC")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                }

                Spacer()

                if let s = spot {
                    Text(s.status.rawValue)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(s.status.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(s.status.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                }
            }

            if let s = spot {
                let country = spotCountryInfo(for: s)
                let geo = spotGeodesicInfo(for: s)

                // Callsign & Country Flag Hero
                HStack(spacing: 8) {
                    Text(country?.flag ?? "🌐")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.callsign)
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(.primary)
                        Text(country?.name ?? "DX Station")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Frequency & Mode Pills
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.3f kHz", s.frequencyKHz))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                        HStack(spacing: 4) {
                            Text(s.mode)
                                .font(.system(size: 8.5, weight: .heavy))
                                .foregroundColor(.yellow)
                            if let snr = s.snr {
                                Text(String(format: "%+d dB", snr))
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(snr >= 0 ? .green : .orange)
                            }
                            Text("\(s.ageMinutes)m ago")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

                // Geodesic Vector & Azimuth Intelligence
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "location.north.line.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 9))
                        Text("Origin: \(stationCallsign) (\(stationGrid))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        if let zones = country?.continent {
                            Text(zones)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let g = geo {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "safari.fill")
                                    .foregroundColor(.cyan)
                                    .font(.system(size: 10))
                                Text(String(format: "Azimuth: %03.0f° %@", g.bearing, g.cardinal))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left.and.right")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 9))
                                Text(String(format: "%.0f km (%.0f mi)", g.distanceKm, g.distanceKm * GeodesicMath.kmToMiles))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))

                // Comment / Spotter
                if !s.comment.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 8))
                        Text(s.comment)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }

                // Action Buttons
                HStack(spacing: 6) {
                    Button {
                        tuneToSpot(s)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "target")
                            Text("Tune VFO")
                        }
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.cyan.opacity(0.25), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundColor(.cyan)
                    }
                    .buttonStyle(.plain)

                    Button {
                        fillQuickLogAndFocus(spot: s)
                        appState.operatorDeskSection = 0
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.pencil")
                            Text("Quick Log")
                        }
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.25), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Populate Quick Log draft and switch to Quick Log desk")

                    Button {
                        if let url = URL(string: "https://www.qrz.com/db/\(s.callsign)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "globe")
                            Text("QRZ")
                        }
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Select or hover a spot")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("Click any spot on the Panadapter or DX Hunter table to inspect bearing, distance, and log directly.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func smoothWaterfallView(
        bandRange: ClosedRange<Double>,
        activeSpots: [BandmapSpot],
        vfoAKHz: Double,
        vfoBKHz: Double
    ) -> some View {
        GeometryReader { watGeo in
            let width = watGeo.size.width
            let height = watGeo.size.height

            ZStack(alignment: .topLeading) {
                Canvas { context, sz in
                    drawWaterfall(context: context, size: sz, range: bandRange, spots: activeSpots, phase: animationPhase)
                }
                .frame(width: width, height: height)

                // Reticle Guidelines on Waterfall
                if bandRange.contains(vfoAKHz) {
                    let xA = xPosition(forKHz: vfoAKHz, range: bandRange, width: width)
                    Rectangle()
                        .fill(Color.cyan.opacity(0.8))
                        .frame(width: 1.5, height: height)
                        .position(x: xA, y: height / 2)
                }

                if bandmap.isSplitActive && bandRange.contains(vfoBKHz) {
                    let xB = xPosition(forKHz: vfoBKHz, range: bandRange, width: width)
                    Rectangle()
                        .fill(Color.orange.opacity(0.8))
                        .frame(width: 1.5, height: height)
                        .position(x: xB, y: height / 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let clickedKHz = khzForX(location.x, range: bandRange, width: width)
                tuneToFrequency(khz: clickedKHz)
            }
        }
    }

    // Canvas drawing for Spectrum graph with Gaussian bell curves, S-meter levels, and frequency ticks
    private func drawSpectrumGraph(
        context: GraphicsContext,
        size: CGSize,
        range: ClosedRange<Double>,
        spots: [BandmapSpot],
        phase: Double
    ) {
        let width = size.width
        let height = size.height
        let baseline = height - 16.0

        // 1. S-Meter Reference Grid Lines
        let sLevels: [(label: String, frac: CGFloat)] = [
            ("+20dB", 0.15),
            ("S9", 0.32),
            ("S7", 0.48),
            ("S5", 0.64),
            ("S3", 0.78),
            ("NF", 0.90)
        ]

        for item in sLevels {
            let y = height * item.frac
            var line = Path()
            line.move(to: CGPoint(x: 36, y: y))
            line.addLine(to: CGPoint(x: width, y: y))
            context.stroke(line, with: .color(Color.white.opacity(0.06)), style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))

            let text = Text(item.label)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
            context.draw(context.resolve(text), at: CGPoint(x: 18, y: y), anchor: .center)
        }

        // 2. Frequency Vertical Grid Lines
        let spanKHz = range.upperBound - range.lowerBound
        if spanKHz > 0 {
            let stepKHz: Double = spanKHz > 500 ? 100.0 : (spanKHz > 200 ? 50.0 : 25.0)
            let firstStep = ceil(range.lowerBound / stepKHz) * stepKHz
            var currFreq = firstStep
            while currFreq <= range.upperBound {
                let x = xPosition(forKHz: currFreq, range: range, width: width)
                var vert = Path()
                vert.move(to: CGPoint(x: x, y: 0))
                vert.addLine(to: CGPoint(x: x, y: baseline))
                context.stroke(vert, with: .color(Color.white.opacity(0.05)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))

                let freqText = Text(String(format: "%.3f", currFreq / 1000.0))
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                context.draw(context.resolve(freqText), at: CGPoint(x: x, y: baseline + 8), anchor: .center)

                currFreq += stepKHz
            }
        }

        // 3. Construct RF Spectrum Curve using Gaussian Distributions
        var path = Path()
        path.move(to: CGPoint(x: 0, y: baseline))

        let stepX: CGFloat = 3.0
        let steps = Int(width / stepX)

        for i in 0...steps {
            let x = CGFloat(i) * stepX

            // Gentle organic RF noise floor
            let noise = sin(Double(x) * 0.09 + phase) * 2.5 + cos(Double(x) * 0.16 - phase * 0.6) * 1.8
            var y = baseline - 6.0 + CGFloat(noise)

            // Gaussian RF signal peaks
            for spot in spots {
                let spotX = xPosition(forKHz: spot.frequencyKHz, range: range, width: width)
                let dist = abs(x - spotX)

                let isNarrow = spot.mode.uppercased().contains("CW") || spot.mode.uppercased().contains("FT8")
                let sigma: CGFloat = isNarrow ? 4.2 : 8.5

                if dist < sigma * 3.5 {
                    let peakHeight = min(height * 0.72, max(22.0, CGFloat((spot.snr ?? 4) + 22) * 1.8))
                    let gaussian = exp(-0.5 * pow(dist / sigma, 2))
                    y -= peakHeight * gaussian
                }
            }

            path.addLine(to: CGPoint(x: x, y: max(10, y)))
        }

        path.addLine(to: CGPoint(x: width, y: baseline))
        path.closeSubpath()

        // 4. Fill with multi-stop RF glow gradient
        let gradient = Gradient(stops: [
            .init(color: Color.cyan.opacity(0.40), location: 0.0),
            .init(color: Color.blue.opacity(0.20), location: 0.4),
            .init(color: Color(red: 0.04, green: 0.12, blue: 0.28).opacity(0.10), location: 0.7),
            .init(color: Color.clear, location: 1.0)
        ])
        context.fill(path, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: height)))

        // 5. Stroke glowing RF line
        context.stroke(path, with: .color(Color.cyan.opacity(0.95)), lineWidth: 1.5)
    }

    // Canvas drawing for High-Definition Smooth Waterfall
    private func drawWaterfall(
        context: GraphicsContext,
        size: CGSize,
        range: ClosedRange<Double>,
        spots: [BandmapSpot],
        phase: Double
    ) {
        let width = size.width
        let height = size.height
        let rowHeight: CGFloat = 4.0
        let rows = Int(height / rowHeight)

        // 180 fine resolution columns for silky smooth waterfall
        let segCount = 180
        let segWidth = width / CGFloat(segCount)

        for r in 0..<rows {
            let y = CGFloat(r) * rowHeight
            let rowPhase = phase + Double(r) * 0.12
            let yDecay = exp(-Double(r) * 0.035)

            for s in 0..<segCount {
                let x = CGFloat(s) * segWidth
                let freq = khzForX(x + segWidth / 2, range: range, width: width)

                // Soft background RF thermal noise (no diagonal block stripes)
                var intensity = (sin(Double(s) * 0.12 + rowPhase * 0.25) * 0.03 + 0.06)

                // Exponentially decaying vertical signal trails for spots
                for spot in spots {
                    let dist = abs(spot.frequencyKHz - freq)
                    let isNarrow = spot.mode.uppercased().contains("CW") || spot.mode.uppercased().contains("FT8")
                    let maxSpread: Double = isNarrow ? 1.2 : 2.8
                    if dist < maxSpread {
                        let bell = exp(-0.5 * pow(dist / (maxSpread * 0.5), 2))
                        intensity += 0.85 * bell * yDecay
                    }
                }

                let color = waterfallThermalColor(intensity: intensity)
                context.fill(Path(CGRect(x: x, y: y, width: segWidth + 0.5, height: rowHeight + 0.5)), with: .color(color))
            }
        }
    }

    private func waterfallThermalColor(intensity: Double) -> Color {
        if intensity < 0.12 {
            return Color(red: 0.02, green: 0.04, blue: 0.08)
        } else if intensity < 0.25 {
            return Color(red: 0.04, green: 0.12, blue: 0.26)
        } else if intensity < 0.50 {
            return Color(red: 0.06, green: 0.40, blue: 0.65)
        } else if intensity < 0.75 {
            return Color(red: 0.10, green: 0.78, blue: 0.90)
        } else if intensity < 0.92 {
            return Color(red: 0.96, green: 0.82, blue: 0.22)
        } else {
            return Color(red: 0.95, green: 0.25, blue: 0.20)
        }
    }

    // MARK: - Geodesic, Maidenhead & Spot Inspection Helpers

    private var inspectedSpot: BandmapSpot? {
        if let id = selectedSpotID, let spot = bandmap.spots.first(where: { $0.id == id }) {
            return spot
        }
        if let id = hoveredSpotID, let spot = bandmap.spots.first(where: { $0.id == id }) {
            return spot
        }
        return bandmap.spots.first(where: { $0.band.uppercased() == bandmap.selectedBand.uppercased() })
    }

    private var stationCallsign: String {
        let call = appState.currentStationCallsign
        return (call.isEmpty || call == "DEFAULT" || call == "NOCALL") ? "EP2AES" : call
    }

    private var stationGrid: String {
        let grid = appState.activeStationProfile?.normalizedGrid ?? ""
        return grid.isEmpty ? "LM55" : grid
    }

    private var stationCoordinate: GeoCoordinate {
        if let coord = parseMaidenhead(stationGrid) {
            return coord
        }
        return GeoCoordinate(latitude: 35.7, longitude: 51.4)
    }

    private func targetCoordinate(for spot: BandmapSpot) -> GeoCoordinate? {
        if let grid = extractGrid(from: spot.comment), let coord = parseMaidenhead(grid) {
            return coord
        }
        let entity = DXCCDatabase.resolve(callsign: spot.callsign)
        if let country = WorldVectorGeography.countries.first(where: { $0.id.uppercased() == entity.countryCode.uppercased() }) {
            return country.center
        }
        if !spot.dxccPrefix.isEmpty, let country = WorldVectorGeography.countries.first(where: { $0.primaryPrefix.uppercased() == spot.dxccPrefix.uppercased() }) {
            return country.center
        }

        // Special remote island / rare DXpedition coordinates
        let call = spot.callsign.uppercased()
        if call.hasPrefix("3Y") { return GeoCoordinate(latitude: -54.42, longitude: 3.35) }
        if call.hasPrefix("FT5W") || call.hasPrefix("FT5X") || call.hasPrefix("FT5Z") { return GeoCoordinate(latitude: -49.35, longitude: 70.21) }
        if call.hasPrefix("VK0") { return GeoCoordinate(latitude: -53.10, longitude: 73.50) }
        if call.hasPrefix("DP0") || call.hasPrefix("RI1A") { return GeoCoordinate(latitude: -70.67, longitude: -8.27) }

        // CQ Zone Centroid Fallback
        let cqCenters: [Int: GeoCoordinate] = [
            1: GeoCoordinate(latitude: 65, longitude: -150),
            2: GeoCoordinate(latitude: 60, longitude: -85),
            3: GeoCoordinate(latitude: 45, longitude: -120),
            4: GeoCoordinate(latitude: 45, longitude: -100),
            5: GeoCoordinate(latitude: 40, longitude: -75),
            6: GeoCoordinate(latitude: 25, longitude: -100),
            7: GeoCoordinate(latitude: 15, longitude: -85),
            8: GeoCoordinate(latitude: 20, longitude: -70),
            9: GeoCoordinate(latitude: 5, longitude: -65),
            10: GeoCoordinate(latitude: -10, longitude: -75),
            11: GeoCoordinate(latitude: -15, longitude: -50),
            12: GeoCoordinate(latitude: -35, longitude: -70),
            13: GeoCoordinate(latitude: -35, longitude: -60),
            14: GeoCoordinate(latitude: 50, longitude: 5),
            15: GeoCoordinate(latitude: 50, longitude: 20),
            16: GeoCoordinate(latitude: 55, longitude: 40),
            17: GeoCoordinate(latitude: 60, longitude: 75),
            18: GeoCoordinate(latitude: 60, longitude: 100),
            19: GeoCoordinate(latitude: 60, longitude: 140),
            20: GeoCoordinate(latitude: 38, longitude: 28),
            21: GeoCoordinate(latitude: 32, longitude: 53),
            22: GeoCoordinate(latitude: 22, longitude: 78),
            23: GeoCoordinate(latitude: 40, longitude: 95),
            24: GeoCoordinate(latitude: 26, longitude: 115),
            25: GeoCoordinate(latitude: 36, longitude: 138),
            26: GeoCoordinate(latitude: 15, longitude: 100),
            27: GeoCoordinate(latitude: 14, longitude: 125),
            28: GeoCoordinate(latitude: -5, longitude: 115),
            29: GeoCoordinate(latitude: -25, longitude: 120),
            30: GeoCoordinate(latitude: -30, longitude: 145),
            31: GeoCoordinate(latitude: 5, longitude: -170),
            32: GeoCoordinate(latitude: -40, longitude: 175),
            33: GeoCoordinate(latitude: 30, longitude: -5),
            34: GeoCoordinate(latitude: 25, longitude: 30),
            35: GeoCoordinate(latitude: 10, longitude: -10),
            36: GeoCoordinate(latitude: 0, longitude: 20),
            37: GeoCoordinate(latitude: -5, longitude: 35),
            38: GeoCoordinate(latitude: -30, longitude: 25),
            39: GeoCoordinate(latitude: -50, longitude: 70),
            40: GeoCoordinate(latitude: 65, longitude: -20)
        ]
        return cqCenters[entity.cqZone]
    }

    private func spotGeodesicInfo(for spot: BandmapSpot) -> (bearing: Double, cardinal: String, distanceKm: Double)? {
        guard let target = targetCoordinate(for: spot) else { return nil }
        let origin = stationCoordinate
        let dist = GeodesicMath.distanceKm(from: origin, to: target)
        let brg = GeodesicMath.initialBearing(from: origin, to: target)
        return (brg, cardinalDirection(for: brg), dist)
    }

    private func spotCountryInfo(for spot: BandmapSpot) -> (name: String, flag: String, continent: String)? {
        let entity = DXCCDatabase.resolve(callsign: spot.callsign)
        let details = "\(entity.continent) · CQ \(entity.cqZone) · ITU \(entity.ituZone)"
        return (entity.entityName, entity.flagEmoji, details)
    }

    private func cardinalDirection(for bearing: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((bearing + 11.25).truncatingRemainder(dividingBy: 360) / 22.5)
        return directions[max(0, min(15, index))]
    }

    private func parseMaidenhead(_ grid: String) -> GeoCoordinate? {
        let clean = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 4 else { return nil }
        let chars = Array(clean)
        guard chars[0] >= "A" && chars[0] <= "R",
              chars[1] >= "A" && chars[1] <= "R",
              chars[2] >= "0" && chars[2] <= "9",
              chars[3] >= "0" && chars[3] <= "9" else { return nil }

        let lonField = Double(chars[0].asciiValue! - Character("A").asciiValue!) * 20.0 - 180.0
        let latField = Double(chars[1].asciiValue! - Character("A").asciiValue!) * 10.0 - 90.0
        let lonSquare = Double(chars[2].asciiValue! - Character("0").asciiValue!) * 2.0
        let latSquare = Double(chars[3].asciiValue! - Character("0").asciiValue!) * 1.0

        var lon = lonField + lonSquare + 1.0
        var lat = latField + latSquare + 0.5

        if clean.count >= 6 {
            if chars[4] >= "A" && chars[4] <= "X", chars[5] >= "A" && chars[5] <= "X" {
                let lonSub = Double(chars[4].asciiValue! - Character("A").asciiValue!) * (2.0 / 24.0) + (1.0 / 24.0) - 1.0
                let latSub = Double(chars[5].asciiValue! - Character("A").asciiValue!) * (1.0 / 24.0) + (0.5 / 24.0) - 0.5
                lon += lonSub
                lat += latSub
            }
        }
        return GeoCoordinate(latitude: lat, longitude: lon)
    }

    private func extractGrid(from comment: String) -> String? {
        let pattern = #"(?i)\b([A-R]{2}[0-9]{2}([A-X]{2})?)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsRange = NSRange(comment.startIndex..<comment.endIndex, in: comment)
            if let match = regex.firstMatch(in: comment, range: nsRange),
               let range = Range(match.range(at: 1), in: comment) {
                return String(comment[range]).uppercased()
            }
        }
        return nil
    }

    private func bandCallingPresets(for band: String) -> [(freqKHz: Double, label: String, mode: String)] {
        switch band.uppercased() {
        case "160M":
            return [(1836.0, "1836 CW QRP", "CW"), (1840.0, "1840 FT8", "FT8")]
        case "80M":
            return [(3560.0, "3560 CW QRP", "CW"), (3573.0, "3573 FT8", "FT8"), (3750.0, "3750 DX Window", "LSB")]
        case "60M":
            return [(5351.5, "5351.5 CW", "CW"), (5357.0, "5357 FT8", "FT8")]
        case "40M":
            return [(7030.0, "7030 CW QRP", "CW"), (7074.0, "7074 FT8", "FT8"), (7150.0, "7150 DX Phone", "LSB")]
        case "30M":
            return [(10116.0, "10116 CW QRP", "CW"), (10136.0, "10136 FT8", "FT8")]
        case "20M":
            return [(14060.0, "14060 CW QRP", "CW"), (14074.0, "14074 FT8", "FT8"), (14200.0, "14200 DX Calling", "USB"), (14230.0, "14230 SSTV", "USB")]
        case "17M":
            return [(18080.0, "18080 CW QRP", "CW"), (18100.0, "18100 FT8", "FT8"), (18130.0, "18130 DX Calling", "USB")]
        case "15M":
            return [(21060.0, "21060 CW QRP", "CW"), (21074.0, "21074 FT8", "FT8"), (21250.0, "21250 DX Calling", "USB")]
        case "12M":
            return [(24890.0, "24890 CW", "CW"), (24915.0, "24915 FT8", "FT8"), (24950.0, "24950 Calling", "USB")]
        case "10M":
            return [(28060.0, "28060 CW QRP", "CW"), (28074.0, "28074 FT8", "FT8"), (28400.0, "28400 DX Calling", "USB"), (28680.0, "28680 SSTV", "USB")]
        case "6M":
            return [(50090.0, "50090 CW", "CW"), (50313.0, "50313 FT8", "FT8"), (50125.0, "50125 Calling", "USB")]
        case "2M":
            return [(144174.0, "144.174 FT8", "FT8"), (144200.0, "144.200 SSB", "USB"), (145500.0, "145.500 FM Call", "FM")]
        default:
            return [(14074.0, "14074 FT8", "FT8"), (14060.0, "14060 CW", "CW")]
        }
    }

    // MARK: - Right Pane: Active DX Spot Hunter Table & Inspector

    @ViewBuilder
    private func spotHunterTablePane(size: CGSize) -> some View {
        let bandRange = bandmap.bandRangeKHz(for: bandmap.selectedBand, region: bandmap.iaruRegion)
        let spots = filteredSpots(bandRange: bandRange)

        VStack(spacing: 0) {
            // Table Header & Search
            VStack(spacing: 6) {
                HStack {
                    Text("DX SPOT HUNTER")
                        .font(.caption.bold())
                        .foregroundColor(.cyan)

                    Spacer()

                    // Quick Actions: Simulate, Prune, Clear
                    Button {
                        bandmap.simulateDemoSpot()
                    } label: {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.cyan)
                    }
                    .buttonStyle(.plain)
                    .help("Simulate new live DX spot")

                    Button {
                        bandmap.pruneExpiredSpots()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Prune expired spots")

                    Button {
                        bandmap.clearAllSpots()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear all spots")
                }

                // Filter chips
                HStack(spacing: 4) {
                    spotFilterChip(title: "All", tag: "ALL")
                    spotFilterChip(title: "Fresh (<2m)", tag: "FRESH")
                    spotFilterChip(title: "New DXCC", tag: "NEW_DXCC")
                    spotFilterChip(title: "FT8", tag: "FT8")
                    spotFilterChip(title: "CW", tag: "CW")
                    spotFilterChip(title: "SSB", tag: "SSB")
                }

                // Search Box
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("Filter callsign or comment...", text: $bandmap.searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !bandmap.searchText.isEmpty {
                        Button {
                            bandmap.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Spots List Table
            if spots.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No DX Spots on \(bandmap.selectedBand)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text("Decodes from WSJT-X / JTDX and DX Cluster will appear here in real time.")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button("Simulate Live Spot") {
                        bandmap.simulateDemoSpot()
                    }
                    .controlSize(.small)
                    .padding(.top, 4)
                    Spacer()
                }
            } else {
                List(spots) { spot in
                    spotTableRow(spot: spot)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(
                            selectedSpotID == spot.id ?
                            Color.cyan.opacity(0.12) :
                            Color.clear
                        )
                }
                .listStyle(.plain)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func spotFilterChip(title: String, tag: String) -> some View {
        Button {
            spotFilterMode = tag
        } label: {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(spotFilterMode == tag ? Color.cyan : Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                .foregroundColor(spotFilterMode == tag ? .black : .primary)
        }
        .buttonStyle(.plain)
    }

    private func spotTableRow(spot: BandmapSpot) -> some View {
        let entity = DXCCDatabase.resolve(callsign: spot.callsign)

        return HStack(spacing: 8) {
            // Status Circle
            Circle()
                .fill(spot.status.color)
                .frame(width: 8, height: 8)

            // Flag + Callsign
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entity.flagEmoji)
                        .font(.caption2)
                    Text(spot.callsign)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }
                Text(entity.entityName)
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Frequency & Mode
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.1f", spot.frequencyKHz))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                HStack(spacing: 4) {
                    Text(spot.mode)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                    if let snr = spot.snr {
                        Text(String(format: "%+d", snr))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(snr >= 0 ? .green : .orange)
                    }
                }
            }

            // Time Ago
            Text("\(spot.ageMinutes)m")
                .font(.system(size: 8.5))
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)

            // Action Buttons: QSY / LOG
            HStack(spacing: 4) {
                Button {
                    tuneToSpot(spot)
                } label: {
                    Text("QSY")
                        .font(.system(size: 8.5, weight: .black))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)
                .help("Tune radio to spot frequency")

                Button {
                    fillQuickLogAndFocus(spot: spot)
                } label: {
                    Text("LOG")
                        .font(.system(size: 8.5, weight: .black))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help("Populate Quick Log draft")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSpotID = spot.id
            tuneToSpot(spot)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                fillQuickLogAndFocus(spot: spot)
            }
        )
    }

    // MARK: - Multi-Band Panorama Mode

    @ViewBuilder
    private func multiBandPanoramaView(size: CGSize) -> some View {
        HStack(spacing: 8) {
            ForEach(Self.panoramaBands, id: \.self) { band in
                let range = bandmap.bandRangeKHz(for: band, region: bandmap.iaruRegion)
                let spots = bandmap.spots.filter { $0.band.uppercased() == band.uppercased() || range.contains($0.frequencyKHz) }
                let currentVFO = currentVFOAFrequencyKHz
                let isBandActive = range.contains(currentVFO)

                VStack(spacing: 0) {
                    // Column Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(band)
                                .font(.headline.bold())
                                .foregroundColor(isBandActive ? .cyan : .white)
                            Text("\(spots.count) Spots")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if isBandActive {
                            Text("ACTIVE VFO")
                                .font(.system(size: 7.5, weight: .black))
                                .foregroundColor(.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.cyan, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(isBandActive ? Color.cyan.opacity(0.15) : Color.white.opacity(0.05))

                    Divider()

                    // Vertical Mini Ruler & Spots List
                    ScrollView([.vertical]) {
                        VStack(spacing: 4) {
                            ForEach(spots) { spot in
                                Button {
                                    bandmap.selectedBand = band
                                    tuneToSpot(spot)
                                } label: {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(spot.status.color)
                                            .frame(width: 6, height: 6)
                                        Text(spot.callsign)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text(String(format: "%.1f", spot.frequencyKHz))
                                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.cyan)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }
                }
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isBandActive ? Color.cyan : Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .padding(10)
    }

    // MARK: - Bottom Status, Legend & Split Controls

    private var bottomStudioFooter: some View {
        HStack(spacing: 16) {
            // Split Controls
            HStack(spacing: 8) {
                Button {
                    bandmap.isSplitActive.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: bandmap.isSplitActive ? "bolt.horizontal.fill" : "bolt.horizontal")
                        Text("SPLIT")
                            .font(.system(size: 10, weight: .black))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(bandmap.isSplitActive ? Color.orange : Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundColor(bandmap.isSplitActive ? .black : .primary)
                }
                .buttonStyle(.plain)

                if bandmap.isSplitActive {
                    HStack(spacing: 4) {
                        Text("TX Offset:")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Button("+1k") { setSplitOffset(1.0) }
                            .buttonStyle(.borderless)
                            .font(.caption2.bold())
                        Button("+2k") { setSplitOffset(2.0) }
                            .buttonStyle(.borderless)
                            .font(.caption2.bold())
                        Button("+5k") { setSplitOffset(5.0) }
                            .buttonStyle(.borderless)
                            .font(.caption2.bold())

                        Button("A=B") {
                            bandmap.vfoBKHz = currentVFOAFrequencyKHz
                            if tci.isConnected {
                                tci.setFrequency(hz: UInt64(bandmap.vfoBKHz * 1000.0), receiver: 0, vfo: 1)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2.bold())
                    }
                }
            }

            Divider().frame(height: 16)

            // Legend indicators
            HStack(spacing: 10) {
                legendPill(label: "New DXCC", color: .green)
                legendPill(label: "New Band", color: .cyan)
                legendPill(label: "Unconfirmed", color: .orange)
                legendPill(label: "Worked", color: .secondary)
            }

            Spacer()

            // Zoom Controls
            HStack(spacing: 6) {
                Text("Ruler Zoom:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button {
                    zoomLevel = max(0.8, zoomLevel - 0.2)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)

                Text("\(Int(zoomLevel * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)

                Button {
                    zoomLevel = min(3.0, zoomLevel + 0.2)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func legendPill(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Frequency Helpers & Tuning Actions

    private var currentVFOAFrequencyKHz: Double {
        if tci.isConnected {
            return Double(tci.vfoAFrequencyHz) / 1000.0
        } else if flrig.isConnected {
            return flrig.frequencyHz / 1000.0
        } else if let rigSnap = appState.rigControlClient.snapshot, let mhz = Double(rigSnap.frequencyMHz) {
            return mhz * 1000.0
        }
        return bandmap.vfoAKHz
    }

    private var currentVFOBFrequencyKHz: Double {
        if tci.isConnected {
            return Double(tci.vfoBFrequencyHz) / 1000.0
        }
        return bandmap.vfoBKHz
    }

    private func setSplitOffset(_ offsetKHz: Double) {
        let vfoA = currentVFOAFrequencyKHz
        let vfoB = vfoA + offsetKHz
        bandmap.vfoBKHz = vfoB
        bandmap.isSplitActive = true
        if tci.isConnected {
            tci.setFrequency(hz: UInt64(vfoB * 1000.0), receiver: 0, vfo: 1)
        }
    }

    private func filteredSpots(bandRange: ClosedRange<Double>) -> [BandmapSpot] {
        return bandmap.spots.filter { spot in
            guard spot.band.uppercased() == bandmap.selectedBand.uppercased() || bandRange.contains(spot.frequencyKHz) else { return false }
            if bandmap.filterNewOnly && spot.status == .worked { return false }
            if !bandmap.searchText.isEmpty {
                let matchCall = spot.callsign.localizedCaseInsensitiveContains(bandmap.searchText)
                let matchComment = spot.comment.localizedCaseInsensitiveContains(bandmap.searchText)
                guard matchCall || matchComment else { return false }
            }
            switch spotFilterMode {
            case "FRESH": return spot.isFresh
            case "NEW_DXCC": return spot.status == .newDXCC
            case "FT8": return spot.mode.uppercased().contains("FT8")
            case "CW": return spot.mode.uppercased() == "CW"
            case "SSB": return spot.mode.uppercased() == "USB" || spot.mode.uppercased() == "LSB"
            default: return true
            }
        }
    }

    private func yPosition(forKHz freq: Double, range: ClosedRange<Double>, totalHeight: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let progress = (freq - range.lowerBound) / span
        return CGFloat(progress) * totalHeight
    }

    private func xPosition(forKHz freq: Double, range: ClosedRange<Double>, width: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let progress = (freq - range.lowerBound) / span
        return CGFloat(progress) * width
    }

    private func khzForX(_ x: CGFloat, range: ClosedRange<Double>, width: CGFloat) -> Double {
        guard width > 0 else { return range.lowerBound }
        let progress = Double(max(0, min(width, x)) / width)
        return range.lowerBound + progress * (range.upperBound - range.lowerBound)
    }

    private func heightForSegment(_ seg: BandPlanSegment, range: ClosedRange<Double>, totalHeight: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 20 }
        let segSpan = seg.endKHz - seg.startKHz
        return CGFloat(segSpan / span) * totalHeight
    }

    private func tuneToSpot(_ spot: BandmapSpot) {
        tuneToFrequency(khz: spot.frequencyKHz, mode: spot.mode, callsign: spot.callsign)
    }

    private func tuneToFrequency(khz: Double, mode: String? = nil, callsign: String? = nil) {
        let hz = khz * 1000.0

        // 1. Hardware / Rig Control
        if tci.isConnected {
            tci.setFrequency(hz: UInt64(hz))
            if let mode = mode, !mode.isEmpty {
                tci.setMode(mode)
            }
        } else if flrig.isConnected {
            Task {
                try? await flrig.setFrequency(hz: hz)
                if let mode = mode, !mode.isEmpty {
                    try? await flrig.setMode(mode)
                }
            }
        } else {
            bandmap.vfoAKHz = khz
            if bandmap.isSplitActive {
                bandmap.vfoBKHz = khz + bandmap.splitOffsetKHz
            }
        }

        // 2. Draft log updates
        if let callsign = callsign, !callsign.isEmpty {
            appState.quickLogDraft.callsign = callsign
            appState.quickLogDraft.frequencyMHz = String(format: "%.4f", khz / 1000.0)
            appState.quickLogDraft.band = bandmap.selectedBand
            if let mode = mode {
                appState.quickLogDraft.mode = mode
            }
            appState.appendLog("QSY to \(callsign) at \(String(format: "%.3f kHz", khz))" + (mode != nil ? " [\(mode!)]" : ""))
            showToast("QSY: \(callsign) · \(String(format: "%.3f kHz", khz))")
        } else {
            showToast("QSY: \(String(format: "%.3f kHz", khz))")
        }
    }

    private func fillQuickLogAndFocus(spot: BandmapSpot) {
        tuneToSpot(spot)
        appState.quickLogDraft.callsign = spot.callsign
        appState.quickLogDraft.frequencyMHz = String(format: "%.4f", spot.frequencyKHz / 1000.0)
        appState.quickLogDraft.band = spot.band
        appState.quickLogDraft.mode = spot.mode
        appState.appendLog("Quick Log Draft populated for \(spot.callsign)")
        showToast("Logged \(spot.callsign) into Draft")
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            quickToastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if quickToastMessage == message {
                    quickToastMessage = nil
                }
            }
        }
    }
}
