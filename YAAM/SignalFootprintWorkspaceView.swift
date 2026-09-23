//
//  SignalFootprintWorkspaceView.swift
//  YAAM
//
//  Live PSKReporter & Reverse Beacon Network (RBN) Signal Footprint Console
//  ("ردپای سیگنال من در جهان")
//  Multi-projection 3D Globe, Azimuthal NS6T Map, and 2D GridTracker with
//  geodesic great circle propagation arcs, antenna polar radiation pattern radar,
//  and 1-click antenna rotator beam steering.
//

import AppKit
import CoreLocation
import MapKit
import SwiftUI

public struct SignalFootprintWorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var engine = SignalFootprintEngine.shared
    @ObservedObject private var rotatorService = RotatorService.shared
    @StateObject private var telemetryState = MapTelemetryState()

    // UI Viewport Controls
    @State private var selectedProjection: MapProjectionMode = .globe3D
    @State private var selectedTab: Int = 0 // 0: Live Spotters, 1: Polar Radar, 2: Band Matrix
    @State private var showGreatCircleArcs: Bool = true
    @State private var showSolarGreyline: Bool = true
    @State private var showGridOverlay: Bool = true
    @State private var showCountryLabels: Bool = true
    @State private var azimuthalRangeKm: Double = 20015.0
    @State private var selectedSpot: SignalFootprintSpot?
    @State private var searchText: String = ""
    @State private var sortOrder: SpotSortOrder = .distanceDesc
    @State private var showRotatorConfirmation: String? = nil

    private enum SpotSortOrder: String, CaseIterable, Identifiable {
        case distanceDesc = "Furthest DX"
        case snrDesc = "Strongest SNR"
        case timeDesc = "Most Recent"
        case bearingAsc = "Bearing (0°→360°)"

        var id: String { rawValue }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Top Telemetry HUD Strip
            telemetryHUDHeader
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 2. Main Body Split: Central Viewport + Lower Inspector
            HSplitView {
                // Left / Main: Map & Globe Viewport
                VStack(spacing: 0) {
                    mapViewportControlsBar
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))

                    Divider()

                    ZStack(alignment: .bottomLeading) {
                        mapCanvasView

                        // Rotator beam steering quick status banner
                        if let confirmation = showRotatorConfirmation {
                            HStack(spacing: 6) {
                                Image(systemName: "location.north.line.fill")
                                    .foregroundStyle(.cyan)
                                Text(confirmation)
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.cyan.opacity(0.4), lineWidth: 1))
                            .padding(12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .frame(minWidth: 420, minHeight: 320)

                // Right / Lower: Telemetry Inspector & Analysis Tabs
                VStack(spacing: 0) {
                    inspectorTabBar
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))

                    Divider()

                    switch selectedTab {
                    case 0:
                        spottersTableView
                    case 1:
                        polarAntennaRadarView
                    case 2:
                        bandMatrixView
                    default:
                        spottersTableView
                    }
                }
                .frame(minWidth: 380, idealWidth: 440, maxWidth: 580)
            }
        }
        .onAppear {
            syncStationInfo()
        }
    }

    // MARK: - Station Info Sync
    private func syncStationInfo() {
        let call = appState.activeStationProfile?.normalizedCallsign ?? appState.activeStationProfile?.callsign ?? "EP2AES"
        let grid = appState.effectiveStationGrid
        let coord = appState.effectiveStationCoordinate
        engine.setStation(callsign: call, grid: grid, latitude: coord.latitude, longitude: coord.longitude)
    }

    // MARK: - 1. Top Telemetry HUD Header
    private var telemetryHUDHeader: some View {
        HStack(spacing: 12) {
            // Station Call & Grid Beacon
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.green)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(engine.stationCallsign.isEmpty ? "EP2AES" : engine.stationCallsign)
                            .font(.system(.title3, design: .monospaced).weight(.heavy))
                        Text(engine.homeGrid)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(Color.blue)
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(engine.isSimulatedData ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                        Text(engine.isSimulatedData ? "SIMULATED FOOTPRINT" : (engine.isPolling ? "QUERYING PSK & RBN..." : "LIVE ON-AIR RADAR"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider().frame(height: 28)

            // KPI Cards
            HStack(spacing: 8) {
                kpiCard(
                    title: "MONITORS",
                    value: "\(engine.filteredSpots.count)",
                    unit: "heard",
                    icon: "dot.radiowaves.left.and.right",
                    color: .green
                )

                kpiCard(
                    title: "FURTHEST DX",
                    value: engine.sessionMaxDistanceKm > 0 ? "\(Int(engine.sessionMaxDistanceKm)) km" : "-",
                    unit: engine.sessionMaxDXCall.isEmpty ? "" : "\(engine.sessionMaxDXFlag) \(engine.sessionMaxDXCall)",
                    icon: "globe.americas.fill",
                    color: .orange
                )

                let bestSNR = engine.spots.compactMap(\.snr).max()
                kpiCard(
                    title: "BEST SNR",
                    value: bestSNR.map { $0 > 0 ? "+\($0) dB" : "\($0) dB" } ?? "-",
                    unit: "",
                    icon: "waveform.path.ecg",
                    color: .mint
                )

                let activeBandsCount = Set(engine.spots.map(\.band)).count
                kpiCard(
                    title: "ACTIVE BANDS",
                    value: "\(activeBandsCount)",
                    unit: "bands",
                    icon: "chart.bar.xaxis",
                    color: .purple
                )
            }

            Spacer(minLength: 8)

            // Time Range Picker
            Picker("", selection: $engine.selectedTimeRange) {
                ForEach(SignalFootprintTimeRange.allCases) { range in
                    Text(range.shortLabel).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .controlSize(.small)
            .help("Select reception history window")

            // Actions: Refresh, Simulate, Alerts
            HStack(spacing: 6) {
                Button {
                    engine.refreshNow()
                } label: {
                    HStack(spacing: 4) {
                        if engine.isPolling {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(engine.isPolling ? "Fetching" : "\(engine.countdownSeconds)s")
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(engine.isPolling)
                .help("Refresh telemetry from PSKReporter now")

                Button {
                    engine.loadSampleFootprintTelemetry()
                } label: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Load simulated worldwide footprint telemetry for demonstration")

                Menu {
                    Toggle("Audio Chime on Spot", isOn: $engine.audioAlertsEnabled)
                    Toggle("Voice Speech Announcement", isOn: $engine.voiceAlertsEnabled)
                    Divider()
                    Link("Open My PSKReporter Map Online", destination: URL(string: "https://pskreporter.info/pskmap.html?preset&callsign=\(engine.stationCallsign.isEmpty ? "EP2AES" : engine.stationCallsign)")!)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
    }

    private func kpiCard(title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(title)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.2), lineWidth: 1))
    }

    // MARK: - 2. Map Viewport Controls Bar
    private var mapViewportControlsBar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $selectedProjection) {
                Text("🌐 3D Globe").tag(MapProjectionMode.globe3D)
                Text("🧭 Azimuthal").tag(MapProjectionMode.azimuthal)
                Text("🗺 Flat Grid").tag(MapProjectionMode.gridTracker)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 230)

            Spacer()

            Toggle(isOn: $showGreatCircleArcs) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Toggle Great Circle Signal Arcs")

            Toggle(isOn: $showSolarGreyline) {
                Image(systemName: "sun.max.fill")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Toggle Day/Night Solar Greyline Terminator")

            Toggle(isOn: $showGridOverlay) {
                Image(systemName: "square.grid.3x3")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Toggle Maidenhead Grid Lines")
        }
    }

    // MARK: - 3. Map Canvas View
    @ViewBuilder
    private var mapCanvasView: some View {
        let markers = activeMarkers
        let homeCoord = engine.homeCoordinate

        switch selectedProjection {
        case .globe3D:
            Globe3DMapView(
                homeCoordinate: homeCoord,
                markers: markers,
                mapType: .hybrid,
                showGreatCircleArcs: showGreatCircleArcs,
                showDayNightShadow: showSolarGreyline,
                showCountryLabels: showCountryLabels,
                telemetryState: telemetryState,
                onSelectMarker: { marker in
                    handleMarkerSelection(marker)
                }
            )

        case .azimuthal:
            AzimuthalAndFlatMapCanvas(
                mode: .azimuthal,
                homeCoordinate: homeCoord,
                markers: markers,
                logSummaries: [:],
                activeOnAirGrids: Set(engine.spots.map { String($0.listenerGrid.prefix(4)).uppercased() }),
                showDayNightShadow: showSolarGreyline,
                showGridLines: showGridOverlay,
                showTrafficArcs: showGreatCircleArcs,
                showCountryLabels: showCountryLabels,
                azimuthalRangeKm: azimuthalRangeKm,
                stationCallsign: engine.stationCallsign,
                onSelectMarker: { marker in
                    handleMarkerSelection(marker)
                },
                onSelectGrid: { _ in }
            )

        case .gridTracker:
            GridTrackerMapView(
                homeCoordinate: homeCoord,
                markers: markers,
                logSummaries: [:],
                mapType: .standard,
                showDayNightShadow: showSolarGreyline,
                showGridLines: showGridOverlay,
                showTrafficArcs: showGreatCircleArcs,
                telemetryState: telemetryState,
                onSelectMarker: { marker in
                    handleMarkerSelection(marker)
                },
                onSelectGrid: { _ in }
            )
        }
    }

    private var activeMarkers: [Globe3DMarker] {
        var list: [Globe3DMarker] = []
        var seenCalls = Set<String>()

        for spot in engine.filteredSpots {
            let call = spot.listenerCall.uppercased()
            guard !call.isEmpty, !seenCalls.contains(call) else { continue }
            seenCalls.insert(call)

            list.append(Globe3DMarker(
                callsign: call,
                flag: spot.flag,
                coordinate: spot.coordinate,
                grid: spot.listenerGrid,
                band: spot.band,
                mode: spot.mode,
                snr: spot.snr,
                isHome: false,
                timestamp: spot.timestamp
            ))
        }
        return list
    }

    private func handleMarkerSelection(_ marker: Globe3DMarker) {
        if let found = engine.spots.first(where: { $0.listenerCall.uppercased() == marker.callsign }) {
            selectedSpot = found
        }
    }

    // MARK: - 4. Inspector Tab Bar
    private var inspectorTabBar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $selectedTab) {
                Text("📡 Spotters (\(engine.filteredSpots.count))").tag(0)
                Text("🎯 Polar Radar").tag(1)
                Text("📊 Band Matrix").tag(2)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(maxWidth: 290)

            Spacer()

            if selectedTab == 0 {
                Menu {
                    Picker("Sort By", selection: $sortOrder) {
                        ForEach(SpotSortOrder.allCases) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    Divider()
                    Picker("Band", selection: $engine.filterBand) {
                        Text("All Bands").tag("ALL")
                        ForEach(Array(Set(engine.spots.map(\.band))).sorted(), id: \.self) { b in
                            Text(b).tag(b)
                        }
                    }
                    Picker("Source", selection: $engine.filterSource) {
                        Text("All Sources").tag("ALL")
                        ForEach(SignalFootprintSource.allCases) { s in
                            Text(s.rawValue).tag(s.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
    }

    // MARK: - Tab 1: Live Spotters Table View
    private var sortedSpots: [SignalFootprintSpot] {
        let base = engine.filteredSpots.filter { spot in
            if searchText.isEmpty { return true }
            return spot.listenerCall.localizedCaseInsensitiveContains(searchText) ||
                   spot.listenerCountry.localizedCaseInsensitiveContains(searchText) ||
                   spot.listenerGrid.localizedCaseInsensitiveContains(searchText)
        }

        switch sortOrder {
        case .distanceDesc:
            return base.sorted { ($0.distanceKm ?? 0) > ($1.distanceKm ?? 0) }
        case .snrDesc:
            return base.sorted { ($0.snr ?? -99) > ($1.snr ?? -99) }
        case .timeDesc:
            return base.sorted { $0.timestamp > $1.timestamp }
        case .bearingAsc:
            return base.sorted { ($0.bearingDeg ?? 0) < ($1.bearingDeg ?? 0) }
        }
    }

    private var spottersTableView: some View {
        VStack(spacing: 0) {
            // Search Input
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search call, grid, or country...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            if sortedSpots.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No reports found")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("Transmit CQ or click 'Sparkles' above to load simulation data.")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sortedSpots, id: \.id) { spot in
                    spotterRow(spot)
                        .padding(.vertical, 3)
                        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                }
                .listStyle(.plain)
            }
        }
    }

    private func spotterRow(_ spot: SignalFootprintSpot) -> some View {
        HStack(spacing: 8) {
            // Country Flag & Call
            HStack(spacing: 4) {
                Text(spot.flag)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 0) {
                    Text(spot.listenerCall)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text(spot.listenerCountry)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 105, alignment: .leading)

            // Band & Mode
            VStack(alignment: .leading, spacing: 0) {
                Text(spot.band)
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(QSOMetadataFormatter.bandColor(spot.band))
                Text(spot.mode)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48, alignment: .leading)

            // SNR Badge
            Text(spot.snrText)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(spot.snrColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                .foregroundStyle(spot.snrColor)
                .frame(width: 58, alignment: .center)

            // Distance & Bearing
            VStack(alignment: .leading, spacing: 0) {
                Text(spot.distanceKm.map { "\(Int($0)) km" } ?? "-")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text(spot.bearingCompass.map { "\(spot.bearingDeg.map { "\(Int($0))°" } ?? "") \($0)" } ?? "-")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 78, alignment: .leading)

            Spacer()

            // 1-Click Steer Rotator Button
            if let bearing = spot.bearingDeg {
                Button {
                    steerRotator(to: bearing, call: spot.listenerCall)
                } label: {
                    Image(systemName: "location.north.line.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(rotatorService.isConnected ? Color.cyan : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Steer antenna beam to \(Int(bearing))° towards \(spot.listenerCall)")
            }

            // QRZ Web Lookup
            Button {
                if let url = URL(string: "https://www.qrz.com/db/\(spot.listenerCall)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Look up \(spot.listenerCall) on QRZ.com")
        }
    }

    private func steerRotator(to bearing: Double, call: String) {
        rotatorService.turnTo(azimuth: bearing)
        withAnimation {
            showRotatorConfirmation = "Turning Rotator to \(Int(bearing))° [\(call)]"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                showRotatorConfirmation = nil
            }
        }
    }

    // MARK: - Tab 2: Polar Antenna Radiation Pattern (Polar Radar)
    private var polarAntennaRadarView: some View {
        let sectors = engine.computePolarCoverage()
        let maxCount = max(1, sectors.map(\.spotCount).max() ?? 1)

        return VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ANTENNA COVERAGE PATTERN")
                        .font(.system(size: 11, weight: .heavy))
                    Text("Directional distribution of received reports across 16 compass sectors (360°)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if rotatorService.isConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "location.north.line.fill")
                            .foregroundStyle(.cyan)
                        Text("Beam: \(Int(rotatorService.currentAzimuth))°")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            // Circular Polar Canvas
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2.0, y: geo.size.height / 2.0)
                let radius = min(geo.size.width, geo.size.height) / 2.0 - 24.0

                ZStack {
                    // Concentric Range Rings
                    ForEach([0.25, 0.50, 0.75, 1.0], id: \.self) { fraction in
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            .frame(width: radius * 2.0 * fraction, height: radius * 2.0 * fraction)
                    }

                    // Radial Rays for 8 Cardinal Directions
                    ForEach(0..<8) { i in
                        let deg = Double(i) * 45.0
                        let rad = deg * .pi / 180.0
                        Path { p in
                            p.move(to: center)
                            p.addLine(to: CGPoint(
                                x: center.x + radius * sin(rad),
                                y: center.y - radius * cos(rad)
                            ))
                        }
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    }

                    // Compass Labels (N, E, S, W)
                    Text("N (0°)")
                        .font(.system(size: 9, weight: .heavy))
                        .position(x: center.x, y: center.y - radius - 10)
                    Text("E (90°)")
                        .font(.system(size: 9, weight: .heavy))
                        .position(x: center.x + radius + 14, y: center.y)
                    Text("S (180°)")
                        .font(.system(size: 9, weight: .heavy))
                        .position(x: center.x, y: center.y + radius + 10)
                    Text("W (270°)")
                        .font(.system(size: 9, weight: .heavy))
                        .position(x: center.x - radius - 14, y: center.y)

                    // Radiation Lobe Polygon
                    Path { path in
                        for (idx, sector) in sectors.enumerated() {
                            let rad = sector.bearingDeg * .pi / 180.0
                            let normalized = Double(sector.spotCount) / Double(maxCount)
                            let r = radius * max(0.12, normalized)
                            let pt = CGPoint(
                                x: center.x + r * sin(rad),
                                y: center.y - r * cos(rad)
                            )
                            if idx == 0 {
                                path.move(to: pt)
                            } else {
                                path.addLine(to: pt)
                            }
                        }
                        path.closeSubpath()
                    }
                    .fill(Color.green.opacity(0.28))

                    Path { path in
                        for (idx, sector) in sectors.enumerated() {
                            let rad = sector.bearingDeg * .pi / 180.0
                            let normalized = Double(sector.spotCount) / Double(maxCount)
                            let r = radius * max(0.12, normalized)
                            let pt = CGPoint(
                                x: center.x + r * sin(rad),
                                y: center.y - r * cos(rad)
                            )
                            if idx == 0 {
                                path.move(to: pt)
                            } else {
                                path.addLine(to: pt)
                            }
                        }
                        path.closeSubpath()
                    }
                    .stroke(Color.green, lineWidth: 2)

                    // Rotator Heading Indicator Ray
                    if rotatorService.isConnected {
                        let rad = rotatorService.currentAzimuth * .pi / 180.0
                        Path { p in
                            p.move(to: center)
                            p.addLine(to: CGPoint(
                                x: center.x + radius * sin(rad),
                                y: center.y - radius * cos(rad)
                            ))
                        }
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2.5, dash: [4, 2]))
                    }

                    // Center Station Dot
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
            }
            .frame(height: 240)

            // Polar Sectors Summary Grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(sectors) { s in
                        HStack(spacing: 6) {
                            Text(s.name)
                                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                                .frame(width: 32, alignment: .leading)
                            Text("\(s.spotCount) spots")
                                .font(.system(size: 9))
                                .foregroundStyle(s.spotCount > 0 ? Color.primary : Color.secondary)
                            Spacer()
                            if s.maxDistanceKm > 0 {
                                Text("\(Int(s.maxDistanceKm)) km")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Tab 3: Band Propagation Matrix View
    private var bandMatrixView: some View {
        let stats = engine.computeBandStats()

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BAND PROPAGATION REACH")
                    .font(.system(size: 11, weight: .heavy))
                Text("Comparative maximum distance and reception quality achieved across HF bands")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            if stats.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No multi-band data available")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(stats) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.band)
                                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                        .foregroundStyle(QSOMetadataFormatter.bandColor(item.band))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(QSOMetadataFormatter.bandColor(item.band).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))

                                    Text("\(item.spotCount) monitors")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Text("\(Int(item.maxDistanceKm)) km")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.orange)
                                }

                                // Max Distance Progress Bar
                                GeometryReader { barGeo in
                                    let maxWorldDist = 20015.0
                                    let progress = min(1.0, item.maxDistanceKm / maxWorldDist)

                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.secondary.opacity(0.15))
                                            .frame(height: 6)

                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(QSOMetadataFormatter.bandColor(item.band))
                                            .frame(width: max(4, barGeo.size.width * progress), height: 6)
                                    }
                                }
                                .frame(height: 6)

                                HStack {
                                    Text("Furthest: \(item.furthestFlag) \(item.furthestCall) (\(item.furthestCountry))")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    if let best = item.bestSNR {
                                        Text("Best: \(best > 0 ? "+\(best)" : "\(best)") dB")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(item.avgSNR >= 0 ? Color.green : Color.yellow)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(QSOMetadataFormatter.bandColor(item.band).opacity(0.2), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
        }
    }
}
