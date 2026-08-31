//
//  SixMeterWatchView.swift
//  YAAM
//
//  Dedicated Scientific Monitor and Real-Time Propagation Suite for the 6-Meter Magic Band (50 MHz)
//  Featuring Mid-Point Reflection Analysis, Multi-Hop (Es1/Es2/F2), Dynamic Sparse-Receiver Weighting,
//  Automatic Beam Heading, Webhook Alarms, and Audio/Voice Opening Alerts.
//

import AppKit
import AVFoundation
import Combine
import SwiftUI

public struct SixMeterWatchView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var engine = SixMeterPropagationEngine.shared
    @State private var showAttributionSheet = false
    @State private var showScoringFormulaSheet = false
    @State private var showAlarmSettingsSheet = false
    @State private var selectedSpotFilter = "All"
    @AppStorage("sixMeterAudioAlerts") private var audioAlertsEnabled = true
    @AppStorage("sixMeterVoiceAlerts") private var voiceAlertsEnabled = false

    private let pskMapURL = URL(string: "https://pskreporter.info/pskmap.html")!
    private let kc2gMapURL = URL(string: "https://prop.kc2g.com/")!
    private let dxMapsURL = URL(string: "https://www.dxmaps.com/spots/mapg.php?Lan=E&Frec=50&ML=M&Map=W&DXC=N&HF=N&GL=N")!
    private let noaaDashboardURL = URL(string: "https://www.swpc.noaa.gov/")!

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Live Opening / Imminent Trigger Banner (Flashing when Band is OPEN or VERY HIGH)
                if engine.assessment.level == .open || engine.assessment.level == .veryHigh || engine.assessment.maxRecordedMUF >= 50.0 {
                    bandOpenAlarmBanner
                }

                // Header & Primary Gauge + Optimal Beam Heading
                openingHeader

                // Mid-Point Propagation Corridors (Es1 Single-Hop vs Es2 Double-Hop vs F2)
                midpointCorridorsSection

                // Space Weather & Ionospheric Metric Cards
                spaceWeatherBar

                // Scientific Composite Probability Score Breakdown (Dynamic Compensation)
                scoringFormulaSection

                // Multi-Factor Mechanisms Breakdown (Es, F2, TEP, Aurora)
                mechanismsSection

                // Live 50 MHz Reception Feed (with 2000 km Regional Buffer)
                liveReceptionSection

                // Global Ionosonde Sounders with FoEs Trend
                ionosondeSection

                // External Map & Research Launchers
                quickLaunchSection

                // Footer & Data Sources Pill
                footerAttributionBar
            }
            .padding(22)
        }
        .task {
            engine.setHomeLocation(
                grid: appState.activeStationProfile?.grid,
                latitude: appState.activeStationProfile?.latitude,
                longitude: appState.activeStationProfile?.longitude
            )
            await engine.refreshAllData(stationCallsign: appState.currentStationCallsign)
        }
        .sheet(isPresented: $showAttributionSheet) {
            SixMeterAttributionSheet()
        }
        .sheet(isPresented: $showScoringFormulaSheet) {
            SixMeterScoringFormulaSheet(assessment: engine.assessment)
        }
        .sheet(isPresented: $showAlarmSettingsSheet) {
            SixMeterAlarmsAndWebhooksSheet()
        }
    }

    // MARK: - 0. Flashing Band Open / Imminent Alarm Banner
    private var bandOpenAlarmBanner: some View {
        let assessment = engine.assessment
        let isOpen = assessment.maxRecordedMUF >= 50.0

        return HStack(spacing: 12) {
            Image(systemName: isOpen ? "bolt.fill" : "waveform.path.ecg")
                .font(.title2)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(isOpen ? "🚨 6-METER MAGIC BAND IS OPEN!" : "⚡️ 6-METER OPENING IMMINENT / VERY HIGH ALERT!")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)

                Text(isOpen ?
                     "Midpoint ionospheric MUF has crossed 50 MHz (\(String(format: "%.0f", assessment.maxRecordedMUF)) MHz)! Target: \(assessment.optimalBeam.targetHotspot) [\(assessment.optimalBeam.hopType)] at beam heading \(assessment.optimalBeam.headingCompass)" :
                     "Dense Sporadic-E ionization detected! Midpoint MUF is \(String(format: "%.0f", assessment.maxRecordedMUF)) MHz approaching 50 MHz threshold. Target: \(assessment.optimalBeam.targetHotspot) [\(assessment.optimalBeam.hopType)] at beam heading \(assessment.optimalBeam.headingCompass)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.95))
            }

            Spacer()

            Button {
                NSSound(named: "Hero")?.play()
            } label: {
                Label("Test Chime", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: isOpen ? [Color.orange, Color.red.opacity(0.9)] : [Color.orange.opacity(0.9), Color.yellow.opacity(0.85)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow, lineWidth: 1.5))
        .shadow(color: Color.orange.opacity(0.4), radius: 8, x: 0, y: 3)
    }

    // MARK: - 1. Opening Header & Live Probability Gauge + Optimal Beam
    private var openingHeader: some View {
        let assessment = engine.assessment

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(assessment.level.color.opacity(0.18))
                    Circle()
                        .stroke(assessment.level.color.opacity(0.4), lineWidth: 2)
                    Image(systemName: assessment.level.icon)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(assessment.level.color)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(assessment.summaryHeadline)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(assessment.level.color)
                        
                        Text("\(assessment.probabilityScore)% Score")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(assessment.level.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(assessment.level.color)

                        Text(assessment.level.rawValue)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(assessment.level.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(assessment.level.color)
                    }

                    Text(assessment.summaryDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    Picker("Region", selection: $engine.selectedRegion) {
                        ForEach(SixMeterRegionFilter.allCases) { region in
                            Label(region.rawValue, systemImage: region.icon).tag(region)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 230)

                    HStack(spacing: 8) {
                        Button {
                            Task {
                                await engine.refreshAllData(stationCallsign: appState.currentStationCallsign)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if engine.isFetching {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Refresh (\(engine.refreshCountdownSeconds)s)")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(engine.isFetching)

                        Button {
                            showAlarmSettingsSheet = true
                        } label: {
                            Label("Alarms & Webhooks", systemImage: "bell.badge.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            showScoringFormulaSheet = true
                        } label: {
                            Label("Analysis Engine", systemImage: "function")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            showAttributionSheet = true
                        } label: {
                            Label("Sources & Licenses", systemImage: "info.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            // Optimal Beam Heading Banner
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "location.north.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("OPTIMAL BEAM HEADING")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(assessment.optimalBeam.headingCompass)
                            .font(.subheadline.monospaced().weight(.bold))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.trailing, 8)

                Divider()
                    .frame(height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("TARGET CORRIDOR & HOTSPOT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Text(assessment.optimalBeam.hopType)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.blue)
                    }
                    Text("\(assessment.optimalBeam.targetHotspot) (\(Int(assessment.optimalBeam.distanceKm)) km)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                    Text(assessment.optimalBeam.reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(16)
        .background(assessment.level.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(assessment.level.color.opacity(0.35), lineWidth: 1.5)
        )
    }

    // MARK: - 2. Mid-Point Propagation Corridors (Geometry, Es1 vs Es2 vs F2)
    private var midpointCorridorsSection: some View {
        let corridors = engine.assessment.corridors

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Single-Hop (Es1 ≤2200km), Double-Hop (Es2 >2200km) & F2 Corridors", systemImage: "arrow.triangle.swap")
                    .font(.headline)
                Spacer()
                Text("Evaluates maximum ionization along Great Circle corridors")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 390), spacing: 10)], spacing: 10) {
                ForEach(corridors) { corridor in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(corridor.azimuthCompass)
                                .font(.caption.monospaced().weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(corridor.statusColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(corridor.statusColor)

                            Text(corridor.hopType)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(corridor.statusText)
                                .font(.caption2.bold())
                                .foregroundStyle(corridor.statusColor)
                        }

                        Text(corridor.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(corridor.primaryReflector)
                                .font(.system(size: 9).weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            if let sec = corridor.secondaryReflector {
                                Text(sec)
                                    .font(.system(size: 9).weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        HStack {
                            Text("Distance: \(Int(corridor.distanceKm)) km")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(corridor.hopDistanceDetail)
                                .font(.system(size: 9).monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(corridor.statusColor.opacity(corridor.isOpen ? 0.6 : (corridor.isApproaching ? 0.4 : 0.2)), lineWidth: corridor.isOpen ? 1.5 : 1)
                    )
                }
            }
        }
    }

    // MARK: - 3. Space Weather & Ionospheric Bar
    private var spaceWeatherBar: some View {
        let sw = engine.spaceWeather
        let assessment = engine.assessment

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Space Weather & Ionospheric Indicators", systemImage: "sun.max.trianglebadge.exclamationmark.fill")
                    .font(.headline)
                Spacer()
                if let updated = sw.lastUpdated {
                    Text("NOAA SWPC · \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                metricCard(
                    title: "Solar Flux (SFI)",
                    value: sw.solarFlux > 0 ? String(format: "%.0f", sw.solarFlux) : "165",
                    unit: "sfu",
                    icon: "sun.dust.fill",
                    color: sw.solarFlux >= 160 ? .orange : .blue,
                    statusText: sw.solarFlux >= 160 ? "High (F2 Active)" : "Moderate"
                )

                metricCard(
                    title: "Planetary K-Index",
                    value: String(format: "%.1f", sw.kpIndex),
                    unit: "Kp",
                    icon: "gauge.with.needle",
                    color: sw.kpIndex >= 5 ? .purple : (sw.kpIndex >= 3 ? .yellow : .green),
                    statusText: sw.kpIndex >= 5 ? "Storm / Aurora" : (sw.kpIndex <= 2 ? "Quiet" : "Unsettled")
                )

                metricCard(
                    title: "Planetary A-Index",
                    value: String(format: "%.0f", sw.aIndex),
                    unit: "Ap",
                    icon: "waveform.path.ecg",
                    color: sw.aIndex >= 20 ? .yellow : .green,
                    statusText: sw.aIndex >= 20 ? "Active" : "Normal"
                )

                metricCard(
                    title: "Solar Flare Status",
                    value: sw.xrayFlareClass,
                    unit: "",
                    icon: "flame.fill",
                    color: sw.xrayFlareClass.contains("X") ? .red : (sw.xrayFlareClass.contains("M") ? .orange : .green),
                    statusText: sw.xrayFlareClass.contains("X") ? "Blackout Alert" : "Stable"
                )

                metricCard(
                    title: "Highest FoEs & Rate",
                    value: String(format: "%.1f", assessment.maxRecordedFoEs),
                    unit: "MHz",
                    icon: "cloud.bolt.rain.fill",
                    color: assessment.maxRecordedFoEs >= 10 ? .orange : (assessment.maxRecordedFoEs >= 8 ? .yellow : .blue),
                    statusText: assessment.maxFoEsTrend
                )

                metricCard(
                    title: "Max MUF (Oblique)",
                    value: String(format: "%.0f", assessment.maxRecordedMUF),
                    unit: "MHz",
                    icon: "chart.line.uptrend.xyaxis",
                    color: assessment.maxRecordedMUF >= 50 ? .orange : (assessment.maxRecordedMUF >= 42 ? .yellow : .secondary),
                    statusText: assessment.maxRecordedMUF >= 50 ? "Magic Band Open" : (assessment.maxRecordedMUF >= 42 ? "High Standby" : "< 42 MHz")
                )
            }
        }
    }

    private func metricCard(title: String, value: String, unit: String, icon: String, color: Color, statusText: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
                Spacer()
                Text(statusText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12), in: Capsule())
            }

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.25), lineWidth: 1))
    }

    // MARK: - 4. Scientific Weighted Scoring Breakdown (with Dynamic Compensation)
    private var scoringFormulaSection: some View {
        let b = engine.assessment.scoreBreakdown

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Composite Probability Weighting Model (\(b.finalScore)% Overall Score)", systemImage: "chart.bar.xaxis")
                    .font(.headline)

                if b.isSparseReceiverCompensated {
                    Text("⚖️ Dynamic Sparse-Receiver Compensation Active")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }

                Spacer()

                Button("Detailed Formula Info") {
                    showScoringFormulaSheet = true
                }
                .font(.caption2)
                .buttonStyle(.link)
            }

            VStack(spacing: 8) {
                scoreFactorRow(title: "Accessible Mid-Point MUF", weight: "\(b.midpointWeightPercent)% Weight", score: b.midpointScore, detail: b.midpointDesc, color: .orange)
                scoreFactorRow(title: "2000 km Regional Telemetry", weight: "\(b.telemetryWeightPercent)% Weight", score: b.telemetryScore, detail: b.telemetryDesc, color: .green)
                scoreFactorRow(title: "Diurnal Solar Time & Season", weight: "\(b.diurnalWeightPercent)% Weight", score: b.diurnalScore, detail: b.diurnalDesc, color: .blue)
                scoreFactorRow(title: "Space Weather (SFI & Kp)", weight: "\(b.spaceWeatherWeightPercent)% Weight", score: b.spaceWeatherScore, detail: b.spaceWeatherDesc, color: .purple)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func scoreFactorRow(title: String, weight: String, score: Double, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text("(\(weight))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f / 100", score))
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .separatorColor).opacity(0.15))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(3, geo.size.width * CGFloat(score) / 100.0), height: 5)
                }
            }
            .frame(height: 5)

            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - 5. Multi-Factor Propagation Mechanisms Grid
    private var mechanismsSection: some View {
        let mechanisms = engine.assessment.mechanisms

        return VStack(alignment: .leading, spacing: 12) {
            Label("Propagation Modes & Physics Breakdown", systemImage: "sparkle.magnifyingglass")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 12)], spacing: 12) {
                ForEach(mechanisms, id: \.name) { mech in
                    mechanismCard(mech)
                }
            }
        }
    }

    private func mechanismCard(_ mech: PropagationMechanismDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(mech.color.opacity(0.15))
                    Image(systemName: mech.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(mech.color)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mech.name)
                        .font(.subheadline.weight(.bold))
                    Text(mech.status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(mech.color)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(mech.score)%")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(mech.color)
                    Text("Probability")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .separatorColor).opacity(0.15))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(mech.color)
                        .frame(width: max(4, geo.size.width * CGFloat(mech.score) / 100.0), height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text(mech.metricLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(mech.metricValue)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 2)

            Text(mech.explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(height: 160, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(mech.color.opacity(0.3), lineWidth: 1))
    }

    // MARK: - 6. Live 50 MHz Reception Feed & Spots
    private var liveReceptionSection: some View {
        let allSpots = engine.spots
        let filteredSpots = allSpots.filter { spot in
            let regionMatch = engine.selectedRegion.matches(grid: spot.receiverGrid, distanceFromHomeKm: spot.distanceFromHomeKm) || engine.selectedRegion.matches(grid: spot.senderGrid, distanceFromHomeKm: spot.distanceFromHomeKm)
            if selectedSpotFilter == "All" { return regionMatch }
            return regionMatch && spot.mode.uppercased() == selectedSpotFilter.uppercased()
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live 50 MHz Signals & Reception Telemetry", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                
                Text("(\(filteredSpots.count) active reports in filter)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Mode", selection: $selectedSpotFilter) {
                    Text("All Modes").tag("All")
                    Text("FT8").tag("FT8")
                    Text("CW").tag("CW")
                    Text("SSB").tag("SSB")
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            if filteredSpots.isEmpty {
                ContentUnavailableView(
                    "No 6m Reports in \(engine.selectedRegion.rawValue)",
                    systemImage: "waveform.slash",
                    description: Text(engine.isFetching ? "Querying live PSK Reporter 50 MHz telemetry..." : "No recent 50 MHz spots recorded within this filter. Switch to 'Worldwide' or check during local Es peak.")
                )
                .frame(minHeight: 140)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("TX CALL (SENDER)")
                            .frame(width: 150, alignment: .leading)
                        Text("GRID HOP")
                            .frame(width: 150, alignment: .leading)
                        Text("RX CALL (RECEIVER)")
                            .frame(width: 150, alignment: .leading)
                        Text("FREQUENCY")
                            .frame(width: 100, alignment: .leading)
                        Text("MODE")
                            .frame(width: 60, alignment: .leading)
                        Text("SNR")
                            .frame(width: 70, alignment: .leading)
                        Text("DISTANCE")
                            .frame(width: 90, alignment: .leading)
                        Text("CORRIDOR")
                            .frame(width: 100, alignment: .leading)
                        Spacer()
                        Text("AGE")
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .separatorColor).opacity(0.12))

                    Divider()

                    ForEach(Array(filteredSpots.prefix(15))) { spot in
                        HStack {
                            HStack(spacing: 4) {
                                Text(spot.senderCall)
                                    .font(.subheadline.monospaced().weight(.semibold))
                                if !spot.senderGrid.isEmpty {
                                    Text("[\(spot.senderGrid)]")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 150, alignment: .leading)

                            HStack(spacing: 4) {
                                Text(spot.senderGrid.prefix(4))
                                    .font(.caption2.monospaced().weight(.bold))
                                    .foregroundStyle(.orange)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text(spot.receiverGrid.prefix(4))
                                    .font(.caption2.monospaced().weight(.bold))
                                    .foregroundStyle(.green)
                            }
                            .frame(width: 150, alignment: .leading)

                            HStack(spacing: 4) {
                                Text(spot.receiverCall)
                                    .font(.subheadline.monospaced())
                                if !spot.receiverGrid.isEmpty {
                                    Text("[\(spot.receiverGrid)]")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 150, alignment: .leading)

                            Text(String(format: "%.3f MHz", spot.frequencyMHz))
                                .font(.caption.monospaced())
                                .frame(width: 100, alignment: .leading)

                            Text(spot.mode)
                                .font(.caption2.bold())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(spot.mode == "FT8" ? Color.green.opacity(0.15) : Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(spot.mode == "FT8" ? Color.green : Color.orange)
                                .frame(width: 60, alignment: .leading)

                            Text(spot.snrText)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(spot.snrColor)
                                .frame(width: 70, alignment: .leading)

                            Text(spot.distanceKm.map { "\(Int($0)) km" } ?? "-")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .leading)

                            HStack(spacing: 3) {
                                if spot.isRegionalBuffer {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.system(size: 9))
                                }
                                Text(spot.distanceFromHomeKm.map { "\(Int($0)) km away" } ?? "Regional")
                                    .font(.caption2)
                                    .foregroundStyle(spot.isRegionalBuffer ? .primary : .secondary)
                            }
                            .frame(width: 100, alignment: .leading)

                            Spacer()

                            Text(spot.ageText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)

                        Divider()
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1))
            }
        }
    }

    // MARK: - 7. Global Ionosonde Sounders with Trend Rate
    private var ionosondeSection: some View {
        let stations = engine.ionosondeStations

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Global Ionosonde Sounders & FoEs Trend Rates (GIRO / DIDBase & KC2G)", systemImage: "antenna.radiowaves.left.and.right.circle")
                    .font(.headline)
                Spacer()
                Text("Sounding stations: \(stations.count) · Tracks 15m delta (ΔFoEs / Δt)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(stations) { st in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(st.code)
                                    .font(.caption.monospaced().weight(.bold))
                                Spacer()
                                Text(st.country)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text(st.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(st.trend.rawValue)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(st.trend.color)
                            }

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("FoEs (Rate)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 2) {
                                        Text(st.foEs.map { String(format: "%.1f", $0) } ?? "-")
                                            .font(.caption.monospaced().weight(.bold))
                                            .foregroundStyle(st.isEsAbove50MHz ? .orange : (st.isEsApproaching50MHz ? .yellow : .primary))
                                        Text(String(format: "%+.1f", st.deltaFoEsPerHour))
                                            .font(.system(size: 8).monospaced())
                                            .foregroundStyle(st.trend.color)
                                    }
                                }

                                Spacer()

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Es MUF")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                    Text(st.sporadicEMUF.map { String(format: "%.0f M", $0) } ?? "-")
                                        .font(.caption.monospaced().weight(.bold))
                                        .foregroundStyle(st.isEsAbove50MHz ? .orange : (st.isEsApproaching50MHz ? .yellow : .primary))
                                }

                                Spacer()

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("FoF2")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                    Text(st.foF2.map { String(format: "%.1f M", $0) } ?? "-")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .frame(width: 200, height: 115)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(st.isEsAbove50MHz ? Color.orange.opacity(0.6) : (st.isEsApproaching50MHz ? Color.yellow.opacity(0.5) : Color(nsColor: .separatorColor).opacity(0.3)), lineWidth: (st.isEsAbove50MHz || st.isEsApproaching50MHz) ? 1.5 : 1)
                        )
                    }
                }
            }
        }
    }

    // MARK: - 8. Interactive Tools & Maps Launchers
    private var quickLaunchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Interactive 6m Propagation Maps & Research Tools", systemImage: "map.fill")
                .font(.headline)

            HStack(spacing: 12) {
                mapLaunchCard(
                    title: "KC2G Real-Time MUF Map",
                    subtitle: "Real-time global ionospheric MUF contours and live soundings overlay",
                    icon: "globe.europe.africa.fill",
                    color: .blue,
                    url: kc2gMapURL
                )

                mapLaunchCard(
                    title: "PSK Reporter 50 MHz Live Map",
                    subtitle: "Real-time reception reports for FT8, CW, and digital modes on 6m",
                    icon: "dot.radiowaves.left.and.right",
                    color: .green,
                    url: pskMapURL
                )

                mapLaunchCard(
                    title: "DXMaps 50 MHz Worldwide",
                    subtitle: "Live VHF propagation paths, Sporadic-E clouds, and QSO links",
                    icon: "waveform.path.ecg.rectangle.fill",
                    color: .purple,
                    url: dxMapsURL
                )

                mapLaunchCard(
                    title: "NOAA SWPC Space Weather",
                    subtitle: "GOES Solar X-ray flux, solar flare alarms, and geomagnetic forecast",
                    icon: "sun.max.fill",
                    color: .orange,
                    url: noaaDashboardURL
                )
            }
        }
    }

    private func mapLaunchCard(title: String, subtitle: String, icon: String, color: Color, url: URL) -> some View {
        Link(destination: url) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 9. Footer & Attribution Bar
    private var footerAttributionBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
                .font(.caption)

            Text("Powered by real-time scientific telemetry from NOAA SWPC, GIRO / DIDBase, PSK Reporter, and KC2G MUF under open amateur radio research licenses.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Alarms & Webhooks") {
                showAlarmSettingsSheet = true
            }
            .buttonStyle(.link)
            .font(.caption2)

            Button("View Licenses & Attributions") {
                showAttributionSheet = true
            }
            .buttonStyle(.link)
            .font(.caption2)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Alarms & Webhooks Settings Sheet
public struct SixMeterAlarmsAndWebhooksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("sixMeterAudioAlerts") private var audioAlertsEnabled = true
    @AppStorage("sixMeterVoiceAlerts") private var voiceAlertsEnabled = false
    @AppStorage("sixMeterWebhookURL") private var webhookURL = ""
    @State private var webhookTestStatus = ""
    @State private var isTestingWebhook = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("6m Opening Alarms & Webhook Notifications", systemImage: "bell.badge.fill")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            Text("Configure automatic sound, voice speech, and Discord/Telegram/Custom Webhook alerts when the 6-Meter Band crosses the 50 MHz opening threshold or reaches Very High Alert:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Local macOS Alarms") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Chime Audio Alert on 50 MHz Opening / Imminent Alert", isOn: $audioAlertsEnabled)
                        Toggle("Voice Speech Announcement (Speaks Beam Heading & Target)", isOn: $voiceAlertsEnabled)

                        HStack {
                            Button("Test Audio Chime") {
                                NSSound(named: "Hero")?.play()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Test Voice Alert") {
                                let synth = AVSpeechSynthesizer()
                                let utterance = AVSpeechUtterance(string: "Attention operator: Six meter magic band is open. Recommended beam heading 295 degrees WNW towards Western Europe.")
                                utterance.rate = 0.52
                                synth.speak(utterance)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Webhook Push Notification (Discord / Telegram / Custom)") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Enter a Discord Webhook URL, Telegram Bot Webhook endpoint, or custom HTTP POST JSON URL:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("https://discord.com/api/webhooks/... or https://api.telegram.org/bot...", text: $webhookURL)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button {
                                isTestingWebhook = true
                                webhookTestStatus = "Sending test webhook..."
                                Task {
                                    let success = await SixMeterPropagationEngine.shared.dispatchWebhook(
                                        urlStr: webhookURL,
                                        assessment: SixMeterPropagationEngine.shared.assessment
                                    )
                                    isTestingWebhook = false
                                    webhookTestStatus = success ? "✅ Webhook delivered successfully!" : "❌ Webhook failed (check URL or connection)"
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if isTestingWebhook {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text("Test Webhook")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(webhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTestingWebhook)

                            if !webhookTestStatus.isEmpty {
                                Text(webhookTestStatus)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(webhookTestStatus.contains("✅") ? .green : .red)
                            }
                        }
                    }
                    .padding(8)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(minWidth: 540, idealWidth: 600, minHeight: 400, idealHeight: 460)
    }
}

// MARK: - Scoring Formula & Scientific Engine Sheet
public struct SixMeterScoringFormulaSheet: View {
    public let assessment: SixMeterAssessment
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("6m Opening Probability Formulation & Science", systemImage: "function")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            Text("The 6m Magic Band (50 MHz) opening probability is computed via a multi-factor weighted scientific formulation that models single-hop (Es1), double-hop (Es2), and F2 midpoint geometry, ionization rates, regional telemetry, and solar indices:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    formulaCard(
                        title: "1. Accessible Mid-Point Ionospheric MUF (\(assessment.scoreBreakdown.midpointWeightPercent)% Weight)",
                        formula: "Score = f(Max Midpoint MUF) · Threshold = 50 MHz",
                        detail: "Evaluates the maximum MUF across sounders in the Great Circle path (e.g. Athens AT138 and Nicosia NIC40 for 295°). For double-hop Es2 (2,600 km), reflection midpoints are at ~700 km and ~1,950 km."
                    )

                    formulaCard(
                        title: "2. 2000 km Regional Telemetry Buffer (\(assessment.scoreBreakdown.telemetryWeightPercent)% Weight)",
                        formula: "Score = f(Active 50 MHz spots within 2000 km radius)",
                        detail: "Monitors live FT8/CW spots across Turkey, Greece, Cyprus, Levant, and the Gulf. When regional receiver density is low (<5 receivers), the system dynamically shifts 15% weight to Mid-Point MUF so valid ionospheric conditions are not penalized."
                    )

                    formulaCard(
                        title: "3. Diurnal Solar Hour & Seasonal Curve (15% Weight)",
                        formula: "Diurnal Peaks: 10:00–13:00 & 17:00–20:00 Local · Summer Peak: May–August",
                        detail: "Sporadic-E formation correlates strongly with mid-morning and late-afternoon tidal winds and metallic ion shear layers in the E-region."
                    )

                    formulaCard(
                        title: "4. Space Weather (SFI & Kp) (10% Weight)",
                        formula: "F2 Solar Max: SFI ≥ 160–200 · Aurora: Kp ≥ 5",
                        detail: "Evaluates secondary propagation modes such as direct F2 layer worldwide propagation and high-latitude auroral backscatter."
                    )
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(minWidth: 580, idealWidth: 640, minHeight: 460, idealHeight: 520)
    }

    private func formulaCard(title: String, formula: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(formula)
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.orange)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Data Sources, Attribution & Open Licenses Sheet
public struct SixMeterAttributionSheet: View {
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Data Sources, Attributions & Open Licenses", systemImage: "doc.plaintext.fill")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            Text("The YAAM 6-Meter Magic Band monitor combines telemetry from world-leading scientific observatories, ionosonde sounder networks, and amateur radio crowdsourced networks:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    attributionItem(
                        name: "NOAA Space Weather Prediction Center (SWPC)",
                        role: "Planetary K-index, Solar Flux Index (SFI), A-index, GOES X-ray solar flare risk, and geomagnetic alerts.",
                        license: "U.S. Public Domain (NOAA Open Data Policy). Free RESTful JSON telemetry.",
                        url: "https://www.swpc.noaa.gov/"
                    )

                    attributionItem(
                        name: "GIRO / DIDBase (Global Ionosonde Radio Observatory)",
                        role: "Real-time ionosonde sounder critical frequencies (FoEs, h'E, FoF2) from Lowell Digisonde sounders worldwide for Sporadic-E calculation.",
                        license: "University of Massachusetts Lowell Center for Atmospheric Research (CAR). Academic Open Citation (CC BY 4.0).",
                        url: "https://giro.uml.edu/"
                    )

                    attributionItem(
                        name: "PSK Reporter (Philip Gladstone)",
                        role: "Live crowdsourced signal reception reports, SNR distribution, and FT8/CW 50 MHz grid square telemetry.",
                        license: "Provided courtesy of Philip Gladstone (pskreporter.info). Utilized under Amateur Radio Fair-Use and community data terms.",
                        url: "https://pskreporter.info/"
                    )

                    attributionItem(
                        name: "KC2G Ionospheric Propagation & MUF",
                        role: "Real-time Maximum Usable Frequency (MUF) mapping, global ionospheric contour data, and processed sounding layers.",
                        license: "Provided courtesy of KC2G (prop.kc2g.com). Licensed under Open Amateur Radio Research terms.",
                        url: "https://prop.kc2g.com/"
                    )

                    attributionItem(
                        name: "Reverse Beacon Network (RBN)",
                        role: "Global real-time CW and digital beacon monitoring network.",
                        license: "Provided by the RBN volunteer developer and station network.",
                        url: "https://reversebeacon.net/"
                    )

                    attributionItem(
                        name: "YAAM Open Source Software Compliance",
                        role: "YAAM (Yet Another ADIF Manager) provides non-commercial, open-source integration of these public feeds for the global amateur radio community.",
                        license: "All telemetry is fetched client-side with proper User-Agent identification and rate limiting in accordance with provider usage policies.",
                        url: "https://github.com"
                    )
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(minWidth: 580, idealWidth: 640, minHeight: 480, idealHeight: 540)
    }

    private func attributionItem(name: String, role: String, license: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if let u = URL(string: url) {
                    Link(destination: u) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            }

            Text(role)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(license)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 1))
    }
}
