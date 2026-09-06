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

// MARK: - Main Bandmap View

public struct BandmapView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var bandmap = BandmapEngine.shared
    @ObservedObject private var flrig = FLRigClient.shared
    @ObservedObject private var tci = TCIClient.shared

    @State private var studioMode: BandmapStudioMode = .studio
    @State private var zoomLevel: CGFloat = 1.0
    @State private var hoveredSpotID: UUID? = nil
    @State private var selectedSpotID: UUID? = nil
    @State private var spotFilterMode: String = "ALL" // ALL, FRESH, NEW_DXCC, FT8, CW, SSB
    @State private var quickToastMessage: String? = nil

    // Animation timer for SDR noise and waterfall phase
    @State private var animationPhase: Double = 0.0
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private let availableBands = ["160M", "80M", "60M", "40M", "30M", "20M", "17M", "15M", "12M", "10M", "6M", "2M"]
    private let panoramaBands = ["40M", "20M", "15M", "10M"]

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
        .background(Color(red: 0.04, green: 0.06, blue: 0.09)) // Deep dark shack #0A0E17
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
        .onReceive(timer) { _ in
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
                        .foregroundColor(.white)
                    Text("Live Spectrum · Dual VFO · Heatmap Ribbon")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Band Pills Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(availableBands, id: \.self) { band in
                        Button {
                            bandmap.selectedBand = band
                        } label: {
                            Text(band)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(bandmap.selectedBand == band ? Color.cyan : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                .foregroundColor(bandmap.selectedBand == band ? .black : .white)
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
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
            .frame(width: 170)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 0.07, green: 0.09, blue: 0.14))
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
            .background(Color.white.opacity(0.04))

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
                                    .foregroundColor(permitted ? .white.opacity(0.85) : .red.opacity(0.8))

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
                            .border(Color.white.opacity(0.06), width: 0.5)
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
        .background(Color(red: 0.05, green: 0.07, blue: 0.11))
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
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 52, alignment: .trailing)
                Rectangle()
                    .fill(Color.white.opacity(0.15))
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
                        .foregroundColor(.white)

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
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(red: 0.10, green: 0.13, blue: 0.20).opacity(0.95))
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
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

    @ViewBuilder
    private func liveSpectrumWaterfallPane(size: CGSize) -> some View {
        let bandRange = bandmap.bandRangeKHz(for: bandmap.selectedBand, region: bandmap.iaruRegion)
        let activeSpots = filteredSpots(bandRange: bandRange)
        let vfoAKHz = currentVFOAFrequencyKHz
        let vfoBKHz = currentVFOBFrequencyKHz

        VStack(spacing: 0) {
            // Spectrum Pane Header & Quick Tune Controls
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("LIVE SDR SPECTRUM & WATERFALL")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }

                Spacer()

                // Dial readout
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("VFO-A:")
                            .font(.caption2.bold())
                            .foregroundColor(.cyan)
                        Text(String(format: "%.3f kHz", vfoAKHz))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundColor(.white)
                    }

                    if bandmap.isSplitActive {
                        HStack(spacing: 4) {
                            Text("VFO-B (TX):")
                                .font(.caption2.bold())
                                .foregroundColor(.orange)
                            Text(String(format: "%.3f kHz", vfoBKHz))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(red: 0.06, green: 0.08, blue: 0.12))

            Divider()

            // Visual Spectrum & Waterfall Canvas
            GeometryReader { specGeo in
                let width = specGeo.size.width
                let height = specGeo.size.height
                let spectrumHeight = height * 0.38
                let waterfallHeight = height * 0.62

                VStack(spacing: 0) {
                    // Top: RF Spectrum Analyzer
                    ZStack(alignment: .topLeading) {
                        // Canvas for RF Line & Peaks
                        Canvas { context, sz in
                            drawSpectrumGraph(context: context, size: sz, range: bandRange, spots: activeSpots, phase: animationPhase)
                        }
                        .frame(height: spectrumHeight)
                        .background(Color(red: 0.03, green: 0.05, blue: 0.08))

                        // VFO-A Vertical Passband Filter Line & Box
                        if bandRange.contains(vfoAKHz) {
                            let xA = xPosition(forKHz: vfoAKHz, range: bandRange, width: width)
                            sdrCursorReticle(xPos: xA, height: spectrumHeight, label: "VFO-A (RX)", color: .cyan)
                        }

                        // VFO-B (TX) Reticle if Split Active
                        if bandmap.isSplitActive && bandRange.contains(vfoBKHz) {
                            let xB = xPosition(forKHz: vfoBKHz, range: bandRange, width: width)
                            sdrCursorReticle(xPos: xB, height: spectrumHeight, label: "VFO-B (TX)", color: .orange)
                        }

                        // Spot Pins on Spectrum
                        ForEach(activeSpots) { spot in
                            let x = xPosition(forKHz: spot.frequencyKHz, range: bandRange, width: width)
                            Button {
                                tuneToSpot(spot)
                            } label: {
                                VStack(spacing: 1) {
                                    Text(spot.callsign)
                                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(spot.status.color.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                                    Image(systemName: "arrowtriangle.down.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(spot.status.color)
                                }
                            }
                            .buttonStyle(.plain)
                            .position(x: x, y: 22)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let clickedKHz = khzForX(location.x, range: bandRange, width: width)
                        tuneToFrequency(khz: clickedKHz)
                    }

                    Divider()

                    // Bottom: SDR Waterfall Canvas
                    ZStack(alignment: .topLeading) {
                        Canvas { context, sz in
                            drawWaterfall(context: context, size: sz, range: bandRange, spots: activeSpots, phase: animationPhase)
                        }
                        .frame(height: waterfallHeight)

                        // Reticle Guidelines on Waterfall
                        if bandRange.contains(vfoAKHz) {
                            let xA = xPosition(forKHz: vfoAKHz, range: bandRange, width: width)
                            Rectangle()
                                .fill(Color.cyan.opacity(0.8))
                                .frame(width: 1.5, height: waterfallHeight)
                                .position(x: xA, y: waterfallHeight / 2)
                        }

                        if bandmap.isSplitActive && bandRange.contains(vfoBKHz) {
                            let xB = xPosition(forKHz: vfoBKHz, range: bandRange, width: width)
                            Rectangle()
                                .fill(Color.orange.opacity(0.8))
                                .frame(width: 1.5, height: waterfallHeight)
                                .position(x: xB, y: waterfallHeight / 2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let clickedKHz = khzForX(location.x, range: bandRange, width: width)
                        tuneToFrequency(khz: clickedKHz)
                    }
                }
            }
        }
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

    // Canvas drawing for Spectrum graph
    private func drawSpectrumGraph(
        context: GraphicsContext,
        size: CGSize,
        range: ClosedRange<Double>,
        spots: [BandmapSpot],
        phase: Double
    ) {
        let width = size.width
        let height = size.height
        let baseline = height - 12

        var path = Path()
        path.move(to: CGPoint(x: 0, y: baseline))

        let stepX: CGFloat = 4.0
        let steps = Int(width / stepX)

        for i in 0...steps {
            let x = CGFloat(i) * stepX

            // Dynamic RF noise baseline with micro-ripples
            let noise = sin(Double(x) * 0.08 + phase) * 3.0 + cos(Double(x) * 0.15 - phase * 0.5) * 2.0
            var y = baseline - 8 + CGFloat(noise)

            // Add peaks for nearby spots
            for spot in spots {
                let spotX = xPosition(forKHz: spot.frequencyKHz, range: range, width: width)
                let dist = abs(x - spotX)
                if dist < 24 {
                    let peakHeight = CGFloat((spot.snr ?? 0) + 25) * 2.2
                    let peak = max(0, (24 - dist) / 24) * min(height * 0.75, max(20, peakHeight))
                    y -= peak
                }
            }

            path.addLine(to: CGPoint(x: x, y: max(14, y)))
        }

        path.addLine(to: CGPoint(x: width, y: baseline))
        path.closeSubpath()

        // Gradient fill under spectrum curve
        let gradient = Gradient(colors: [
            Color.cyan.opacity(0.35),
            Color.blue.opacity(0.15),
            Color.clear
        ])
        context.fill(path, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: height)))

        // Stroke line on top
        context.stroke(path, with: .color(Color.cyan.opacity(0.9)), lineWidth: 1.5)
    }

    // Canvas drawing for SDR Waterfall
    private func drawWaterfall(
        context: GraphicsContext,
        size: CGSize,
        range: ClosedRange<Double>,
        spots: [BandmapSpot],
        phase: Double
    ) {
        let width = size.width
        let height = size.height
        let rowHeight: CGFloat = 6.0
        let rows = Int(height / rowHeight)

        for r in 0..<rows {
            let y = CGFloat(r) * rowHeight
            let rowPhase = phase + Double(r) * 0.15

            // Draw noise and signals across segments
            let segCount = 40
            let segWidth = width / CGFloat(segCount)

            for s in 0..<segCount {
                let x = CGFloat(s) * segWidth
                let freq = khzForX(x + segWidth / 2, range: range, width: width)

                // Base thermal background
                var intensity = (sin(Double(s) * 0.4 + rowPhase) + 1.0) * 0.12

                // Boost intensity if spot matches this frequency
                for spot in spots {
                    let dist = abs(spot.frequencyKHz - freq)
                    if dist < 1.8 {
                        intensity += 0.75
                    }
                }

                let color = waterfallThermalColor(intensity: intensity)
                context.fill(Path(CGRect(x: x, y: y, width: segWidth + 0.5, height: rowHeight + 0.5)), with: .color(color))
            }
        }
    }

    private func waterfallThermalColor(intensity: Double) -> Color {
        if intensity < 0.15 {
            return Color(red: 0.02, green: 0.04, blue: 0.10)
        } else if intensity < 0.35 {
            return Color(red: 0.05, green: 0.15, blue: 0.35)
        } else if intensity < 0.60 {
            return Color(red: 0.0, green: 0.55, blue: 0.80)
        } else if intensity < 0.80 {
            return Color(red: 0.95, green: 0.80, blue: 0.20)
        } else {
            return Color(red: 0.95, green: 0.20, blue: 0.20)
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
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(red: 0.07, green: 0.09, blue: 0.14))

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
        .background(Color(red: 0.05, green: 0.07, blue: 0.11))
    }

    private func spotFilterChip(title: String, tag: String) -> some View {
        Button {
            spotFilterMode = tag
        } label: {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(spotFilterMode == tag ? Color.cyan : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                .foregroundColor(spotFilterMode == tag ? .black : .white.opacity(0.8))
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
                        .foregroundColor(.white)
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
                        .foregroundColor(.white.opacity(0.7))
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
            ForEach(panoramaBands, id: \.self) { band in
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
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text(String(format: "%.1f", spot.frequencyKHz))
                                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.cyan)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }
                }
                .background(Color(red: 0.06, green: 0.08, blue: 0.12))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isBandActive ? Color.cyan : Color.white.opacity(0.1), lineWidth: 1)
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
                    .background(bandmap.isSplitActive ? Color.orange : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundColor(bandmap.isSplitActive ? .black : .white)
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
                    .foregroundColor(.white)

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
        .background(Color(red: 0.07, green: 0.09, blue: 0.14))
    }

    private func legendPill(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
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
