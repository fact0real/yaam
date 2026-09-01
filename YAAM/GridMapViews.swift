//
//  GridMapViews.swift
//  YAAM
//
//  Unified 3D Globe, Azimuthal Antenna Map, and Native MapKit GridTracker Operator Workspace.
//  Zero-Flicker, High-Performance & Low-CPU Architecture.
//

import CoreLocation
import MapKit
import SwiftUI

// MARK: - Activity Source Layer Filter

public enum MapActivityLayer: String, CaseIterable, Identifiable, Sendable {
    case all = "🌟 All Activity"
    case onTheAir = "📡 On-The-Air (PSK)"
    case recentQSOs = "📻 Recent Logged QSOs"
    case liveTraffic = "⚡️ WSJT-X & Cluster"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .all: return "All Activity"
        case .onTheAir: return "On-Air"
        case .recentQSOs: return "Log QSOs"
        case .liveTraffic: return "WSJT-X"
        }
    }
}

// MARK: - Unified 3D Globe, Azimuthal & GridTracker Operator Workspace

public struct GlobeAndGridTrackerWorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var onAirService = OnTheAirMonitorService.shared
    @StateObject private var telemetryState = MapTelemetryState()

    @State private var selectedProjection: MapProjectionMode = .gridTracker
    @State private var selectedActivityLayer: MapActivityLayer = .all
    @State private var mapKitStyle: MKMapType = .standard
    @State private var selectedBand: String = "ALL"
    @State private var selectedMode: String = "ALL"
    @State private var showSolarGreyline: Bool = true
    @State private var showGridOverlay: Bool = true
    @State private var showTrafficArcs: Bool = true
    @State private var showCountryLabels: Bool = true
    @State private var azimuthalRangeKm: Double = 6000.0
    @State private var audioAlertOnNewGrid: Bool = false
    @State private var selectedMarker: Globe3DMarker?
    @State private var selectedGridDetail: String?
    @State private var showStationCard: Bool = false

    private let availableBands = ["ALL", "160M", "80M", "40M", "20M", "17M", "15M", "12M", "10M", "6M", "2M", "70CM"]
    private let availableModes = ["ALL", "FT8", "FT4", "CW", "SSB", "RTTY"]
    private let azimuthalRanges: [(label: String, km: Double)] = [
        ("Regional (3,000 km)", 3000.0),
        ("Europe/ME (6,000 km)", 6000.0),
        ("Continental (10,000 km)", 10000.0),
        ("Global (20,000 km)", 20015.0)
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Filter & Controls Toolbar
            toolbarHeader

            Divider()

            // MARK: - Main Map Viewport / HUD
            ZStack(alignment: .topTrailing) {
                mapViewport

                // Top Floating Telemetry Bar (GridTracker Style)
                VStack {
                    HStack {
                        TelemetryHUDBarView(telemetryState: telemetryState)
                        Spacer()
                    }
                    .padding(.top, 10)
                    .padding(.leading, 12)
                    Spacer()
                }

                // Floating Station Inspector HUD Card (on click)
                if showStationCard, let marker = selectedMarker {
                    stationCalloutCard(marker)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .padding(16)
                } else if showStationCard, let grid = selectedGridDetail {
                    gridSummaryCard(grid)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .padding(16)
                }
            }

            Divider()

            // MARK: - Bottom Grid Hunter & VUCC Analytics HUD
            gridHunterFooter
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(appState.wsjtxListener.$liveDecodes) { decodes in
            checkForWantedGridAlerts(decodes)
        }
    }

    // MARK: - Toolbar Header

    private var toolbarHeader: some View {
        ViewThatFits(in: .horizontal) {
            // Expanded single row with compact controls
            HStack(spacing: 7) {
                projectionControl
                Divider().frame(height: 18)
                mapStyleControl
                activityLayerControl
                azimuthalRangeControl
                bandFilterControl
                modeFilterControl
                Spacer(minLength: 4)
                togglesControl
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            // Compact two rows
            VStack(spacing: 5) {
                HStack(spacing: 7) {
                    projectionControl
                    Divider().frame(height: 18)
                    mapStyleControl
                    activityLayerControl
                    Spacer(minLength: 4)
                }
                HStack(spacing: 7) {
                    azimuthalRangeControl
                    bandFilterControl
                    modeFilterControl
                    Spacer(minLength: 4)
                    togglesControl
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var projectionControl: some View {
        Picker("", selection: $selectedProjection) {
            Text("🌐 Globe").tag(MapProjectionMode.globe3D)
            Text("🧭 Azimuth").tag(MapProjectionMode.azimuthal)
            Text("🗺 2D Grid").tag(MapProjectionMode.gridTracker)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 215)
    }

    @ViewBuilder
    private var mapStyleControl: some View {
        if selectedProjection == .gridTracker || selectedProjection == .globe3D {
            Picker("", selection: $mapKitStyle) {
                Text("🗺 Map").tag(MKMapType.standard)
                Text("🛰 Sat").tag(MKMapType.satellite)
                Text("🏔 Hybrid").tag(MKMapType.hybrid)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 155)
        }
    }

    private var activityLayerControl: some View {
        Menu {
            ForEach(MapActivityLayer.allCases) { layer in
                Button {
                    selectedActivityLayer = layer
                } label: {
                    HStack {
                        Text(layer.rawValue)
                        if selectedActivityLayer == layer { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text(selectedActivityLayer.shortTitle)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
    }

    @ViewBuilder
    private var azimuthalRangeControl: some View {
        if selectedProjection == .azimuthal {
            Menu {
                ForEach(azimuthalRanges, id: \.km) { r in
                    Button {
                        azimuthalRangeKm = r.km
                    } label: {
                        HStack {
                            Text(r.label)
                            if azimuthalRangeKm == r.km { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "scope")
                    Text("Range: \(Int(azimuthalRangeKm)) km")
                        .fontWeight(.semibold)
                }
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
        }
    }

    private var bandFilterControl: some View {
        Menu {
            ForEach(availableBands, id: \.self) { band in
                Button {
                    selectedBand = band
                } label: {
                    HStack {
                        Text(band)
                        if selectedBand == band { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path")
                Text("Band: \(selectedBand)")
                    .fontWeight(.semibold)
            }
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
    }

    private var modeFilterControl: some View {
        Menu {
            ForEach(availableModes, id: \.self) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    HStack {
                        Text(mode)
                        if selectedMode == mode { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                Text("Mode: \(selectedMode)")
                    .fontWeight(.semibold)
            }
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
    }

    private var togglesControl: some View {
        HStack(spacing: 5) {
            Toggle(isOn: $showCountryLabels) {
                Label("Countries", systemImage: "flag.fill")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .tint(.teal)
            .help("Toggle Country Names & Flags")

            Toggle(isOn: $showSolarGreyline) {
                Label("Greyline", systemImage: "sun.max.fill")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .tint(.orange)
            .help("Toggle Real-Time Solar Day/Night Greyline Terminator")

            Toggle(isOn: $showGridOverlay) {
                Label("Grids", systemImage: "square.grid.3x3")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .tint(.blue)
            .help("Toggle Maidenhead Grid Squares Overlay")

            Toggle(isOn: $showTrafficArcs) {
                Label("Arcs", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .tint(.cyan)
            .help("Toggle Great Circle Live Decode Arcs")

            Toggle(isOn: $audioAlertOnNewGrid) {
                Image(systemName: audioAlertOnNewGrid ? "bell.badge.fill" : "bell")
                    .foregroundStyle(audioAlertOnNewGrid ? .green : .secondary)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Audio alert when a new wanted Maidenhead Grid is decoded")
        }
    }

    // MARK: - Map Viewport

    @ViewBuilder
    private var mapViewport: some View {
        let homeCoord = userHomeCoordinate
        let markers = activeMapMarkers
        let logSummaries = MaidenheadGridEngine.aggregateLogbook(
            records: appState.qsoRecords,
            bandFilter: selectedBand,
            modeFilter: selectedMode
        )
        let activeGrids = Set(markers.map { String($0.grid.prefix(4)).uppercased() }.filter { !$0.isEmpty })

        switch selectedProjection {
        case .gridTracker:
            GridTrackerMapView(
                homeCoordinate: homeCoord,
                markers: markers,
                logSummaries: logSummaries,
                mapType: mapKitStyle,
                showDayNightShadow: showSolarGreyline,
                showGridLines: showGridOverlay,
                showTrafficArcs: showTrafficArcs,
                telemetryState: telemetryState,
                onSelectMarker: { marker in
                    selectedMarker = marker
                    selectedGridDetail = nil
                    withAnimation(.spring(response: 0.35)) { showStationCard = true }
                },
                onSelectGrid: { grid in
                    selectedGridDetail = grid
                    selectedMarker = nil
                    withAnimation(.spring(response: 0.35)) { showStationCard = true }
                }
            )

        case .globe3D:
            Globe3DMapView(
                homeCoordinate: homeCoord,
                markers: markers,
                mapType: mapKitStyle == .standard ? .hybrid : mapKitStyle,
                showGreatCircleArcs: showTrafficArcs,
                showDayNightShadow: showSolarGreyline,
                showCountryLabels: showCountryLabels,
                telemetryState: telemetryState,
                onSelectMarker: { marker in
                    selectedMarker = marker
                    selectedGridDetail = nil
                    withAnimation(.spring(response: 0.35)) { showStationCard = true }
                }
            )

        case .azimuthal:
            AzimuthalAndFlatMapCanvas(
                mode: selectedProjection,
                homeCoordinate: homeCoord,
                markers: markers,
                logSummaries: logSummaries,
                activeOnAirGrids: activeGrids,
                showDayNightShadow: showSolarGreyline,
                showGridLines: showGridOverlay,
                showTrafficArcs: showTrafficArcs,
                showCountryLabels: showCountryLabels,
                azimuthalRangeKm: azimuthalRangeKm,
                stationCallsign: appState.activeStationProfile?.callsign ?? "EP2AES",
                onSelectMarker: { marker in
                    selectedMarker = marker
                    selectedGridDetail = nil
                    withAnimation(.spring(response: 0.35)) { showStationCard = true }
                },
                onSelectGrid: { grid in
                    selectedGridDetail = grid
                    selectedMarker = nil
                    withAnimation(.spring(response: 0.35)) { showStationCard = true }
                }
            )
        }
    }

    // MARK: - Station Callout Card (HUD)

    private func stationCalloutCard(_ marker: Globe3DMarker) -> some View {
        let homeCoord = userHomeCoordinate
        let distKm = GeodesicMath.distanceKm(from: homeCoord, to: marker.coordinate)
        let distMiles = distKm * GeodesicMath.kmToMiles
        let spBearing = GeodesicMath.initialBearing(from: homeCoord, to: marker.coordinate)
        let lpBearing = GeodesicMath.longPathBearing(from: homeCoord, to: marker.coordinate)
        let cardinal = GeodesicMath.compassCardinal(for: spBearing)
        let sunTimes = SolarEphemeris.sunriseSunset(for: marker.coordinate)

        return VStack(alignment: .leading, spacing: 10) {
            // Header: Flag, Call, Close Button
            HStack(spacing: 8) {
                Text(marker.flag.isEmpty ? "🌐" : marker.flag)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 1) {
                    Text(marker.callsign)
                        .font(.title3.weight(.bold).monospaced())
                        .foregroundStyle(.primary)
                    if !marker.grid.isEmpty {
                        Text("Grid: \(marker.grid.uppercased()) · \(marker.band) \(marker.mode)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.cyan)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showStationCard = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Bearing & Distance Metric Cards
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Label("Short Path (SP)", systemImage: "location.north.line.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(spBearing))° \(cardinal) · \(Int(distKm)) km (\(Int(distMiles)) mi)")
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(.cyan)
                }

                GridRow {
                    Label("Long Path (LP)", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(lpBearing))° · \(Int(GeodesicMath.longPathDistanceKm(from: homeCoord, to: marker.coordinate))) km")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                GridRow {
                    Label("Sun Times", systemImage: "sunrise.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Rise: \(sunTimes.sunrise) | Set: \(sunTimes.sunset)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.orange)
                }

                if let snr = marker.snr {
                    GridRow {
                        Label("Signal Report", systemImage: "waveform.badge.magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(snr >= 0 ? "+\(snr)" : "\(snr)") dB")
                            .font(.caption.weight(.bold).monospaced())
                            .foregroundStyle(snr >= 0 ? .green : (snr > -15 ? .yellow : .red))
                    }
                }
            }

            Divider()

            // Action Buttons (Quick Log & Aim)
            HStack(spacing: 8) {
                Button {
                    appState.quickLogDraft.callsign = marker.callsign
                    appState.quickLogDraft.band = marker.band.isEmpty ? appState.quickLogDraft.band : marker.band
                    appState.quickLogDraft.mode = marker.mode.isEmpty ? appState.quickLogDraft.mode : marker.mode
                    appState.quickLogDraft.grid = marker.grid
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 0
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Quick Log")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)

                Button {
                    RotatorService.shared.turnTo(azimuth: spBearing)
                    appState.appendLog("Target \(marker.callsign) selected. Rotator steered to \(Int(spBearing))° \(cardinal).")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "location.north.line.fill")
                        Text("Turn Rotator \(Int(spBearing))°")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.cyan.opacity(0.4), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
    }

    // MARK: - Grid Summary Card (HUD on Grid Click)

    private func gridSummaryCard(_ grid: String) -> some View {
        let grid4 = String(grid.prefix(4)).uppercased()
        let logSummaries = MaidenheadGridEngine.aggregateLogbook(records: appState.qsoRecords)
        let summary = logSummaries[grid4]
        let isConf = summary?.isConfirmed == true
        let isWorked = summary != nil
        let homeCoord = userHomeCoordinate

        let box = MaidenheadGridEngine.boundingBox(for: grid4)
        let coord = box?.center ?? GeoCoordinate(latitude: 0, longitude: 0)
        let distKm = GeodesicMath.distanceKm(from: homeCoord, to: coord)
        let spBearing = GeodesicMath.initialBearing(from: homeCoord, to: coord)
        let cardinal = GeodesicMath.compassCardinal(for: spBearing)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.title2)
                    .foregroundStyle(isConf ? .green : (isWorked ? .orange : .red))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Grid Square: \(grid4)")
                        .font(.title3.weight(.bold).monospaced())
                        .foregroundStyle(.primary)
                    Text(isConf ? "🟢 Confirmed in Logbook" : (isWorked ? "🟠 Worked (Pending QSL)" : "🔴 Needed Grid (Never Worked)"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isConf ? .green : (isWorked ? .orange : .red))
                }

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showStationCard = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Label("Bearing & Range", systemImage: "location.north.line.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(spBearing))° \(cardinal) · \(Int(distKm)) km")
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(.cyan)
                }

                if let summary {
                    GridRow {
                        Label("Total Logged QSOs", systemImage: "list.number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(summary.qsoCount) contacts")
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                    }

                    if let lastCall = summary.lastWorkedCallsign {
                        GridRow {
                            Label("Last Worked Station", systemImage: "person.crop.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(lastCall)
                                .font(.caption.weight(.bold).monospaced())
                                .foregroundStyle(.green)
                        }
                    }

                    GridRow {
                        Label("Bands Worked", systemImage: "waveform.path")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(summary.bandsWorked.sorted().joined(separator: ", "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Button {
                    appState.quickLogDraft.grid = grid4
                    appState.selectedTab = 5
                    appState.operatorDeskSection = 0
                } label: {
                    Label("Log QSO for \(grid4)", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)

                Button {
                    RotatorService.shared.turnTo(azimuth: spBearing)
                    appState.appendLog("Grid \(grid4) selected. Rotator steered to \(Int(spBearing))° \(cardinal).")
                } label: {
                    Label("Aim \(Int(spBearing))°", systemImage: "location.north.line.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)

                Spacer()
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isConf ? Color.green.opacity(0.4) : Color.cyan.opacity(0.4), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
    }

    // MARK: - Bottom Grid Hunter & VUCC Footer HUD

    private var gridHunterFooter: some View {
        let logSummaries = MaidenheadGridEngine.aggregateLogbook(
            records: appState.qsoRecords,
            bandFilter: selectedBand,
            modeFilter: selectedMode
        )
        let totalWorked = logSummaries.count
        let totalConfirmed = logSummaries.values.filter(\.isConfirmed).count
        let onAirCount = onAirService.spots.count
        let recentQSOCount = min(50, appState.qsoRecords.count)

        return HStack(spacing: 16) {
            // Metric: Worked Grids
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("GRIDS WORKED")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(totalWorked)")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }

            Divider()
                .frame(height: 24)

            // Metric: Confirmed Grids
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("GRIDS CONFIRMED")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(totalConfirmed)")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.green)
                }
            }

            Divider()
                .frame(height: 24)

            // Metric: Live On-The-Air Telemetry
            HStack(spacing: 6) {
                Circle()
                    .fill(onAirCount > 0 ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ON-THE-AIR (LIVE)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(onAirCount) Receivers")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(onAirCount > 0 ? Color.green : Color.secondary)
                }
            }

            Divider()
                .frame(height: 24)

            // Metric: Recent QSOs
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LOGGED RECENT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(recentQSOCount) QSOs")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.cyan)
                }
            }

            Spacer()

            // VUCC Progress Indicator
            if selectedBand == "6M" || selectedBand == "2M" || selectedBand == "ALL" {
                let target = 100
                let progress = min(1.0, Double(totalConfirmed) / Double(target))
                VStack(alignment: .trailing, spacing: 3) {
                    Text("VUCC Target: \(totalConfirmed) / \(target) (\(Int(progress * 100))%)")
                        .font(.caption2.weight(.semibold).monospaced())
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 130)
                        .tint(.green)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.85))
    }

    // MARK: - Data Aggregation Helpers (Multi-Source Ingestion)

    private var userHomeCoordinate: GeoCoordinate {
        if let prof = appState.activeStationProfile {
            if !prof.grid.isEmpty, let box = MaidenheadGridEngine.boundingBox(for: prof.grid) {
                return box.center
            }
            if let lat = Double(prof.latitude), let lon = Double(prof.longitude) {
                return GeoCoordinate(latitude: lat, longitude: lon)
            }
        }
        // Default: Tehran, Iran (35.6892° N, 51.3890° E)
        return GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
    }

    private var activeMapMarkers: [Globe3DMarker] {
        var list: [Globe3DMarker] = []
        var seenCalls = Set<String>()

        // Layer 1: Live On-The-Air Telemetry (PSK Reporter signals hearing YOU)
        if selectedActivityLayer == .all || selectedActivityLayer == .onTheAir {
            for spot in onAirService.spots {
                let call = spot.listenerCall.uppercased()
                guard !call.isEmpty, !seenCalls.contains(call) else { continue }

                let coord: GeoCoordinate
                if !spot.listenerGrid.isEmpty, let box = MaidenheadGridEngine.boundingBox(for: spot.listenerGrid) {
                    coord = box.center
                } else {
                    coord = GeoCoordinate(latitude: 45.0, longitude: 10.0)
                }

                seenCalls.insert(call)
                list.append(Globe3DMarker(
                    callsign: call,
                    flag: spot.countryFlag,
                    coordinate: coord,
                    grid: spot.listenerGrid,
                    band: spot.band,
                    mode: spot.mode,
                    snr: spot.snr,
                    isHome: false,
                    timestamp: spot.timestamp
                ))
            }
        }

        // Layer 2: Recent Logged QSOs from User's Logbook (Showing where you have operated)
        if selectedActivityLayer == .all || selectedActivityLayer == .recentQSOs {
            for record in appState.qsoRecords.prefix(50) {
                let call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !call.isEmpty, !seenCalls.contains(call) else { continue }

                let grid = record["GRIDSQUARE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let coord: GeoCoordinate
                if grid.count >= 4, let box = MaidenheadGridEngine.boundingBox(for: grid) {
                    coord = box.center
                } else if let lat = Double(record["LAT"]), let lon = Double(record["LON"]) {
                    coord = GeoCoordinate(latitude: lat, longitude: lon)
                } else {
                    continue
                }

                seenCalls.insert(call)
                let flag = flagFromCallsignPrefix(call) ?? "🌐"
                list.append(Globe3DMarker(
                    callsign: call,
                    flag: flag,
                    coordinate: coord,
                    grid: grid,
                    band: record["BAND"],
                    mode: record["MODE"],
                    snr: nil,
                    isHome: false,
                    timestamp: Date()
                ))
            }
        }

        // Layer 3: Live WSJT-X / JTDX Decodes
        if selectedActivityLayer == .all || selectedActivityLayer == .liveTraffic {
            for dec in appState.wsjtxListener.liveDecodes {
                let call = dec.callerCallsign.isEmpty ? dec.targetCallsign : dec.callerCallsign
                guard !call.isEmpty, !seenCalls.contains(call) else { continue }

                let grid = dec.grid
                guard !grid.isEmpty, let box = MaidenheadGridEngine.boundingBox(for: grid) else { continue }

                seenCalls.insert(call)
                let flag = flagFromCallsignPrefix(call) ?? "🌐"
                list.append(Globe3DMarker(
                    callsign: call,
                    flag: flag,
                    coordinate: box.center,
                    grid: grid,
                    band: dec.mode,
                    mode: dec.mode,
                    snr: Int(dec.snr),
                    isHome: false,
                    timestamp: dec.receivedAt
                ))
            }

            // Layer 4: DX Cluster Spots
            for spot in appState.dxClusterClient.spots.prefix(30) {
                let call = spot.callsign.uppercased()
                guard !call.isEmpty, !seenCalls.contains(call) else { continue }

                let flag = flagFromCallsignPrefix(call) ?? "🌐"
                let coord: GeoCoordinate
                if !spot.grid.isEmpty, let box = MaidenheadGridEngine.boundingBox(for: spot.grid) {
                    coord = box.center
                } else {
                    continue
                }

                seenCalls.insert(call)
                list.append(Globe3DMarker(
                    callsign: call,
                    flag: flag,
                    coordinate: coord,
                    grid: spot.grid,
                    band: spot.band,
                    mode: spot.mode,
                    snr: nil,
                    isHome: false,
                    timestamp: spot.spottedAt
                ))
            }
        }

        return list
    }

    private func checkForWantedGridAlerts(_ decodes: [WSJTXLiveDecode]) {
        guard audioAlertOnNewGrid else { return }
        let logSummaries = MaidenheadGridEngine.aggregateLogbook(records: appState.qsoRecords)

        for dec in decodes.prefix(5) {
            guard !dec.grid.isEmpty else { continue }
            let grid4 = String(dec.grid.prefix(4)).uppercased()
            if logSummaries[grid4] == nil {
                appState.playActivitySound(.success)
                appState.appendLog("🔥 NEW WANTED GRID DETECTED: \(grid4) on air from \(dec.callerCallsign)!")
                break
            }
        }
    }
}

// MARK: - Isolated Telemetry HUD View (Prevents Parent Re-Renders)

public struct TelemetryHUDBarView: View {
    @ObservedObject var telemetryState: MapTelemetryState

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.north.circle.fill")
                .foregroundStyle(.cyan)
            Text(telemetryState.hoverText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.4), lineWidth: 1.0))
        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}
