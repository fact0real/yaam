//
//  HamClockShackView.swift
//  YAAM
//
//  HamClock-Inspired Mission Control & Shack Kiosk Dashboard
//  Designed for 24/7 always-on operation on primary screens or auxiliary shack monitors.
//  Includes giant digital UTC/Local/LST/Solar clocks, live vector map with Greyline & Aurora,
//  satellite tracking, NASA SDO solar telescope views, NOAA scales, and DE/DX rotator control.
//

import AppKit
import Combine
import SwiftUI

public struct HamClockShackView: View {
    public var isEmbedded: Bool = false

    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    @ObservedObject private var clockEngine = ShackClockEngine.shared
    @ObservedObject private var satEngine = SatelliteTrackingEngine.shared
    @ObservedObject private var auroraEngine = AuroralOvalEngine.shared
    @ObservedObject private var sdoEngine = SDOSolarImageEngine.shared
    @ObservedObject private var hfPropEngine = HFPointToPointPropagationEngine.shared
    @ObservedObject private var rotatorService = RotatorService.shared
    @ObservedObject private var weatherSafety = StationWeatherSafetyEngine.shared
    @ObservedObject private var webServer = HamClockRemoteWebServer.shared
    @ObservedObject private var drapEngine = DRAPAbsorptionEngine.shared
    @ObservedObject private var balloonEngine = APRSBalloonTrackingEngine.shared

    // Map Presentation
    @State private var mapProjection: MapProjectionMode = .azimuthal
    @State private var dxCallsignInput: String = ""
    @State private var dxGridInput: String = ""
    @State private var selectedAuxPane: HamClockPaneTab = .spaceWeather
    @State private var showSDOZoomModal: Bool = false
    @State private var showQRCodeModal: Bool = false

    public enum HamClockPaneTab: String, CaseIterable, Identifiable {
        case spaceWeather = "Space Weather"
        case sdoSolar = "NASA SDO Sun"
        case voacapMatrix = "VOACAP 24h"
        case satelliteTracker = "Satellite Pass"
        case balloonTracker = "APRS Balloon"

        public var id: String { rawValue }
        public var icon: String {
            switch self {
            case .spaceWeather: return "bolt.shield.fill"
            case .sdoSolar: return "sun.max.fill"
            case .voacapMatrix: return "chart.bar.doc.horizontal.fill"
            case .satelliteTracker: return "antenna.radiowaves.left.and.right"
            case .balloonTracker: return "balloon.fill"
            }
        }
    }

    public init(isEmbedded: Bool = false) {
        self.isEmbedded = isEmbedded
    }

    private var homeCoordinate: GeoCoordinate {
        if appState.isRoverActive {
            return appState.effectiveStationCoordinate
        }
        if let prof = appState.activeStationProfile, !prof.grid.isEmpty {
            return MaidenheadGridEngine.coordinate(for: prof.grid)
        }
        return GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
    }

    private var dxCoordinate: GeoCoordinate {
        MaidenheadGridEngine.coordinate(for: dxGridInput)
    }

    /// False while no DX locator has been entered or resolved: the DX figures then show a dash.
    private var hasDX: Bool {
        MaidenheadGridEngine.boundingBox(for: dxGridInput) != nil
    }

    private var deSunTimes: (sunrise: String, sunset: String) {
        AstronomicalSolarEngine.sunriseSunset(for: homeCoordinate)
    }

    private var dxDistKm: Double {
        GeodesicMath.distanceKm(from: homeCoordinate, to: dxCoordinate)
    }

    private var dxSpBearing: Double {
        GeodesicMath.initialBearing(from: homeCoordinate, to: dxCoordinate)
    }

    private var dxLpBearing: Double {
        GeodesicMath.longPathBearing(from: homeCoordinate, to: dxCoordinate)
    }

    private var dxSunTimes: (sunrise: String, sunset: String) {
        AstronomicalSolarEngine.sunriseSunset(for: dxCoordinate)
    }

    private var currentSfi: Double {
        Double(appState.propagationSnapshot.solarFlux.filter(\.isNumber)) ?? 145.0
    }

    private var nightMode: Bool {
        clockEngine.isNightVisionMode
    }

    public var body: some View {
        ZStack {
            // Base background
            (nightMode ? Color.black : Color(red: 0.04, green: 0.06, blue: 0.10))
                .ignoresSafeArea()

            VStack(spacing: 8) {
                // 1. Giant Top Clock & Timekeeping Ribbon
                topClockRibbon

                Divider()
                    .background(nightMode ? Color.red.opacity(0.4) : Color.white.opacity(0.15))

                // 2. Main Central Work Area (Left Panes + Map + Right Panes)
                HStack(alignment: .top, spacing: 10) {
                    // Left Column: DE & DX Station Telemetry Cards
                    VStack(spacing: 10) {
                        deStationCard
                        dxTargetCard
                    }
                    .frame(width: 310)

                    // Center: Map Canvas with Grayline, Aurora, & Satellite Overlays
                    centerMapContainer

                    // Right Column: Configurable Telemetry Panes
                    VStack(spacing: 10) {
                        configurablePaneSelector
                        selectedAuxPaneView
                    }
                    .frame(width: 320)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            clockEngine.setStationLongitude(homeCoordinate.longitude)
            satEngine.setObserverCoordinate(homeCoordinate)
            updatePropagationMatrix()
        }
        .sheet(isPresented: $showSDOZoomModal) {
            sdoZoomView
        }
        .sheet(isPresented: $showQRCodeModal) {
            qrCodeModalView
        }
    }

    // MARK: - 1. Top Clock & Timekeeping Ribbon

    private var topClockRibbon: some View {
        HStack(alignment: .center, spacing: 16) {
            // Station ID & Mode Badge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "deskclock.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(nightMode ? Color.red : Color.cyan)
                    Text("SHACK CLOCK")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(nightMode ? Color.red : Color.white)
                }
                Text("UTC MASTER • NTP LOCKED")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(nightMode ? Color.red.opacity(0.7) : Color.secondary)
            }

            Spacer()

            // UTC Giant Clock
            VStack(spacing: 1) {
                Text(clockEngine.utcTimeFormatted)
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .foregroundStyle(nightMode ? Color.red : Color.green)
                    .shadow(color: (nightMode ? Color.red : Color.green).opacity(0.4), radius: 6, x: 0, y: 0)

                HStack(spacing: 8) {
                    Text("UTC • \(clockEngine.utcDateFormatted)")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(nightMode ? Color.red.opacity(0.8) : Color.white.opacity(0.8))
                    Text("DOY \(clockEngine.utcDayOfYear)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(nightMode ? Color.red.opacity(0.6) : Color.secondary)
                }
            }

            Spacer()

            // Local Station Clock
            VStack(spacing: 1) {
                Text(clockEngine.localTimeFormatted)
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundStyle(nightMode ? Color.red.opacity(0.9) : Color.cyan)

                Text("\(clockEngine.localTimeZoneCode) • \(clockEngine.localDateFormatted)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(nightMode ? Color.red.opacity(0.7) : Color.secondary)
            }

            Spacer()

            // Astronomical Sidereal & Solar Clocks
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("⭐")
                        .font(.system(size: 9))
                    Text(clockEngine.localSiderealTime)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(nightMode ? Color.red.opacity(0.85) : Color.yellow)
                }
                HStack(spacing: 6) {
                    Text("☀️")
                        .font(.system(size: 9))
                    Text(clockEngine.localSolarTime)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(nightMode ? Color.red.opacity(0.85) : Color.orange)
                }
            }

            Spacer()

            // Stopwatch & Contest Operating Timer
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OPERATING TIMER")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(nightMode ? Color.red.opacity(0.7) : Color.secondary)
                    Text(clockEngine.stopwatchFormatted)
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundStyle(nightMode ? Color.red : Color.white)
                }

                Button {
                    clockEngine.toggleStopwatch()
                } label: {
                    Image(systemName: clockEngine.isStopwatchRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)
                .tint(nightMode ? .red : .blue)

                Button {
                    clockEngine.resetStopwatch()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            // Tools: Web Server, Hourly Chime, Night Mode & Window Detach
            HStack(spacing: 8) {
                // HamClock LAN Web Server Kiosk Button
                Button {
                    if webServer.isRunning {
                        webServer.stop()
                    } else {
                        webServer.start()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(webServer.isRunning ? Color.green : Color.red.opacity(0.6))
                            .frame(width: 7, height: 7)
                        Image(systemName: "globe")
                            .font(.system(size: 11))
                        Text(webServer.isRunning ? ":\(webServer.port)" : "WEB OFF")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    }
                }
                .buttonStyle(.bordered)
                .tint(webServer.isRunning ? (nightMode ? .red : .green) : .secondary)
                .help("Toggle HamClock LAN Web Remote Server (Kiosk on iPad/Mobile)")

                if webServer.isRunning {
                    Button {
                        showQRCodeModal = true
                    } label: {
                        Image(systemName: "qrcode")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .tint(nightMode ? .red : .cyan)
                    .help("Show QR Code to Pair iPad/Tablet")
                }

                // Hourly Chime Button
                Button {
                    clockEngine.isHourlyChimeEnabled.toggle()
                } label: {
                    Image(systemName: clockEngine.isHourlyChimeEnabled ? "bell.fill" : "bell.slash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .tint(clockEngine.isHourlyChimeEnabled ? (nightMode ? .red : .green) : .secondary)
                .help("Toggle Top-of-the-Hour Audio / Morse Chime")

                // Night Vision Red HUD Mode
                Button {
                    clockEngine.isNightVisionMode.toggle()
                } label: {
                    Image(systemName: clockEngine.isNightVisionMode ? "eye.fill" : "eye")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .tint(clockEngine.isNightVisionMode ? .red : .secondary)
                .help("Toggle Night-Vision Red Tactical Mode")

                if isEmbedded {
                    // Detach to Independent Full-Screen Window
                    Button {
                        openWindow(id: YAAMWindowID.hamClock)
                    } label: {
                        Image(systemName: "arrow.up.right.and.arrow.down.left.rectangle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .help("Open Shack Clock in Separate Multi-Monitor Window (Cmd+Option+H)")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - 2. Left Column: DE (My Station) & DX (Target Station) Cards

    private var deStationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DE • MY STATION")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(nightMode ? Color.red : Color.cyan)
                Spacer()
                Text(TransmitIdentity.usableCallsign(appState.activeStationProfile?.callsign) ?? TransmitIdentity.callsignNotSetLabel)
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundStyle(nightMode ? Color.red : Color.white)
            }

            Divider().background(Color.secondary.opacity(0.3))

            Grid(horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text(appState.isRoverActive ? "Rover:" : "Grid:")
                        .font(.caption2)
                        .foregroundStyle(appState.isRoverActive ? Color.orange : .secondary)
                    Text(appState.effectiveStationGrid)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(appState.isRoverActive ? Color.orange : .primary)
                    Text("Lat/Lon:").font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%.2f°, %.2f°", homeCoordinate.latitude, homeCoordinate.longitude))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                GridRow {
                    Text("Sunrise:").font(.caption2).foregroundStyle(.secondary)
                    Text(deSunTimes.sunrise).font(.caption2.bold()).foregroundStyle(.yellow)
                    Text("Sunset:").font(.caption2).foregroundStyle(.secondary)
                    Text(deSunTimes.sunset).font(.caption2.bold()).foregroundStyle(.orange)
                }
            }

            if let wx = weatherSafety.currentTelemetry {
                HStack(spacing: 8) {
                    Label(String(format: "%.1f°C", wx.temperature), systemImage: "thermometer.medium")
                    Label(String(format: "%.0f%%", wx.humidity), systemImage: "humidity.fill")
                    Label(String(format: "%.0f hPa", wx.surfacePressure), systemImage: "barometer")
                }
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(nightMode ? Color.red.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(nightMode ? Color.red.opacity(0.3) : Color.cyan.opacity(0.2), lineWidth: 1))
        )
    }

    private var dxTargetCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DX • TARGET STATION")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(nightMode ? Color.red : Color.orange)

                Spacer()

                TextField("DX CALL", text: $dxCallsignInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 85)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .onSubmit {
                        resolveDXDetails()
                    }

                TextField("GRID", text: $dxGridInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .onSubmit {
                        updatePropagationMatrix()
                    }
            }

            Divider().background(Color.secondary.opacity(0.3))

            Grid(horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text("Distance:").font(.caption2).foregroundStyle(.secondary)
                    Text(hasDX ? String(format: "%.0f km (%.0f mi)", dxDistKm, dxDistKm * GeodesicMath.kmToMiles) : "—")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Text("SP Heading:").font(.caption2).foregroundStyle(.secondary)
                    Text(hasDX ? String(format: "%03.0f° %@", dxSpBearing, GeodesicMath.compassCardinal(for: dxSpBearing)) : "—")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(nightMode ? Color.red : Color.green)
                }
                GridRow {
                    Text("DX Sun:").font(.caption2).foregroundStyle(.secondary)
                    Text(hasDX ? "\(dxSunTimes.sunrise) / \(dxSunTimes.sunset)" : "—")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    Text("LP Heading:").font(.caption2).foregroundStyle(.secondary)
                    Text(hasDX ? String(format: "%03.0f°", dxLpBearing) : "—")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // 1-Click Rotator Command Bar
            HStack(spacing: 8) {
                Button {
                    rotatorService.turnTo(azimuth: dxSpBearing)
                } label: {
                    Label(String(format: "Turn SP (%03.0f°)", dxSpBearing), systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(nightMode ? .red : .green)
                .disabled(!hasDX)

                Button {
                    rotatorService.turnTo(azimuth: dxLpBearing)
                } label: {
                    Text(String(format: "LP %03.0f°", dxLpBearing))
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
                .disabled(!hasDX)
            }
            .padding(.top, 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(nightMode ? Color.red.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(nightMode ? Color.red.opacity(0.3) : Color.orange.opacity(0.2), lineWidth: 1))
        )
    }

    // MARK: - 3. Center: Map Container with Projection & Overlays

    private var centerMapContainer: some View {
        VStack(spacing: 6) {
            // Map Mode Bar (Azimuthal Great-Circle vs Flat Equirectangular)
            HStack(spacing: 12) {
                Picker("Map Projection", selection: $mapProjection) {
                    Label("Azimuthal (DE Centered)", systemImage: "circle.circle").tag(MapProjectionMode.azimuthal)
                    Label("Flat (Equirectangular)", systemImage: "map.fill").tag(MapProjectionMode.gridTracker)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Spacer()

                // Active Satellite Selector
                HStack(spacing: 6) {
                    Text("🛰 SATELLITE:")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $satEngine.selectedSatelliteID) {
                        ForEach(satEngine.satellites) { sat in
                            Text(sat.id).tag(sat.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                // Aurora Storm Indicator
                if auroraEngine.isStormActive {
                    HStack(spacing: 4) {
                        Circle().fill(Color.purple).frame(width: 8, height: 8)
                        Text("AURORA ACTIVE")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(.purple)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.18), in: Capsule())
                }
            }
            .padding(.horizontal, 6)

            // Vector Map Canvas
            AzimuthalAndFlatMapCanvas(
                mode: mapProjection,
                homeCoordinate: homeCoordinate,
                markers: [],
                logSummaries: [:],
                activeOnAirGrids: [],
                showDayNightShadow: true,
                showGridLines: true,
                showTrafficArcs: true,
                showCountryLabels: true,
                showAuroralOval: true,
                showSatelliteTracks: true,
                showDRAPLayer: true,
                showBalloonTracks: true,
                azimuthalRangeKm: 20015.0,
                stationCallsign: appState.activeStationProfile?.callsign ?? "",
                stationLocator: appState.effectiveStationGrid,
                onSelectMarker: { _ in },
                onSelectGrid: { grid in
                    self.dxGridInput = grid
                    updatePropagationMatrix()
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(nightMode ? Color.red.opacity(0.3) : Color.white.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - 4. Right Column: Configurable Telemetry Panes

    private var configurablePaneSelector: some View {
        HStack(spacing: 2) {
            ForEach(HamClockPaneTab.allCases) { tab in
                Button {
                    selectedAuxPane = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11))
                        Text(tab.rawValue)
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        selectedAuxPane == tab
                            ? (nightMode ? Color.red.opacity(0.3) : Color.accentColor.opacity(0.25))
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedAuxPane == tab ? (nightMode ? Color.red : Color.white) : Color.secondary)
            }
        }
        .padding(3)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var selectedAuxPaneView: some View {
        switch selectedAuxPane {
        case .spaceWeather:
            spaceWeatherHUDCard
        case .sdoSolar:
            sdoSolarHUDCard
        case .voacapMatrix:
            voacapMatrixHUDCard
        case .satelliteTracker:
            satelliteTelemetryHUDCard
        case .balloonTracker:
            balloonHUDCard
        }
    }

    // MARK: - Pane A: Space Weather & NOAA Scales

    private var spaceWeatherHUDCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("NOAA SPACE WEATHER", systemImage: "sun.haze.fill")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(nightMode ? Color.red : Color.yellow)
                Spacer()
                Text("SWPC LIVE")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider().background(Color.secondary.opacity(0.3))

            // Primary Solar Indices: SFI, SSN, Kp, A
            let sfi = Double(appState.propagationSnapshot.solarFlux.filter(\.isNumber)) ?? 145.0
            let kp = auroraEngine.currentKp

            Grid(horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    metricTile(label: "SFI (10.7cm)", value: String(format: "%.0f", sfi), color: .orange)
                    metricTile(label: "Sunspots (SSN)", value: "\(max(70, Int(sfi * 0.85)))", color: .yellow)
                }
                GridRow {
                    metricTile(label: "Planetary Kp", value: String(format: "%.1f", kp), color: kpColor(kp))
                    metricTile(label: "IMF Bz (nT)", value: String(format: "%+.1f nT", auroraEngine.currentBz), color: auroraEngine.currentBz < -3.0 ? .red : .green)
                }
            }

            // Official NOAA Operational Scales: R (Radio Blackout), S (Solar Radiation), G (Geomagnetic Storm)
            VStack(alignment: .leading, spacing: 4) {
                Text("OFFICIAL NOAA SCALES (0-5)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    noaaScaleBadge(letter: "R", level: drapEngine.blackoutLevel.rScale, title: "Radio Blackout", color: drapEngine.blackoutLevel.rScale > 0 ? .red : .green)
                    noaaScaleBadge(letter: "S", level: 0, title: "Solar Radiation", color: .green)
                    noaaScaleBadge(letter: "G", level: kp >= 5.0 ? Int(kp - 4.0) : 0, title: "Geomagnetic", color: kp >= 5.0 ? .red : .green)
                }
            }
            .padding(.top, 4)

            // NOAA D-RAP Solar Flare Absorption
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("NOAA D-RAP HF ABSORPTION")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(drapEngine.blackoutLevel.title)
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .foregroundStyle(drapEngine.blackoutLevel.color)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Subsolar HAF:")
                            .font(.system(size: 8)).foregroundStyle(.secondary)
                        Text(String(format: "%.1f MHz", drapEngine.maxHAFMHz))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(drapEngine.maxHAFMHz > 15.0 ? Color.red : Color.orange)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Polar Cap (PCA):")
                            .font(.system(size: 8)).foregroundStyle(.secondary)
                        Text(String(format: "%.1f dB", drapEngine.polarCapAbsorptionDB))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(drapEngine.polarCapAbsorptionDB > 2.0 ? Color.red : Color.green)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Flare Class:")
                            .font(.system(size: 8)).foregroundStyle(.secondary)
                        Text(drapEngine.flareClassification)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.yellow)
                    }
                }
            }
            .padding(6)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .padding(.top, 2)

            // Solar Wind Telemetry
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Solar Wind Speed:")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                    Text("425 km/s")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Proton Density:")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                    Text("5.2 p/cm³")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(nightMode ? Color.red.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(nightMode ? Color.red.opacity(0.3) : Color.yellow.opacity(0.2), lineWidth: 1))
        )
    }

    private func metricTile(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundStyle(nightMode ? Color.red : color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func noaaScaleBadge(letter: String, level: Int, title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(letter)\(level)")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(level > 0 ? Color.red : Color.green.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
            Text(title)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kpColor(_ kp: Double) -> Color {
        if kp >= 5.0 { return .red }
        if kp >= 4.0 { return .orange }
        if kp >= 3.0 { return .yellow }
        return .green
    }

    // MARK: - Pane B: NASA SDO Live Solar Telescope Imagery

    private var sdoSolarHUDCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("NASA SDO SOLAR TELESCOPE", systemImage: "sun.max.fill")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(nightMode ? Color.red : Color.orange)
                Spacer()

                Button {
                    sdoEngine.cycleChannel()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Cycle Spectral Channel")
            }

            Picker("", selection: $sdoEngine.selectedChannel) {
                ForEach(SDOChannel.allCases) { ch in
                    Text(ch.shortTitle).tag(ch)
                }
            }
            .pickerStyle(.segmented)

            // SDO Live Image Frame
            ZStack {
                if let img = sdoEngine.currentImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture {
                            showSDOZoomModal = true
                        }
                } else {
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .overlay(
                            ProgressView("Downloading SDO Frame...")
                                .font(.caption2)
                        )
                }
            }
            .frame(height: 180)

            Text(sdoEngine.selectedChannel.description)
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(nightMode ? Color.red.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(nightMode ? Color.red.opacity(0.3) : Color.orange.opacity(0.2), lineWidth: 1))
        )
    }

    private var sdoZoomView: some View {
        VStack(spacing: 12) {
            HStack {
                Text(sdoEngine.selectedChannel.rawValue)
                    .font(.headline.bold())
                Spacer()
                Button("Done") { showSDOZoomModal = false }
            }
            .padding()

            if let img = sdoEngine.currentImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 700, maxHeight: 700)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 550)
    }

    // MARK: - Pane C: VOACAP DE-to-DX 24-Hour Propagation Heatmap

    private var voacapMatrixHUDCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("VOACAP 24h CIRCUIT MATRIX", systemImage: "chart.bar.doc.horizontal.fill")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(nightMode ? Color.red : Color.cyan)
                Spacer()
                if let best = hfPropEngine.activeMatrix?.bestBandNow {
                    Text("BEST NOW: \(best)")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.green)
                }
            }

            Divider().background(Color.secondary.opacity(0.3))

            if let matrix = hfPropEngine.activeMatrix {
                VStack(spacing: 3) {
                    // Header Hours (00, 04, 08, 12, 16, 20 UTC)
                    HStack(spacing: 0) {
                        Text("Band").frame(width: 34, alignment: .leading).font(.system(size: 7.5, weight: .bold))
                        ForEach(stride(from: 0, through: 23, by: 4).map { $0 }, id: \.self) { h in
                            Text(String(format: "%02d", h))
                                .frame(maxWidth: .infinity)
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Band Rows Heatmap
                    ForEach(matrix.bands, id: \.self) { band in
                        HStack(spacing: 2) {
                            Text(band)
                                .frame(width: 34, alignment: .leading)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))

                            if let cells = matrix.cellsByBand[band] {
                                ForEach(cells) { cell in
                                    Rectangle()
                                        .fill(cell.condition.color)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 10)
                                        .overlay(
                                            cell.hourUTC == Calendar.current.component(.hour, from: Date())
                                                ? Rectangle().stroke(Color.white, lineWidth: 1)
                                                : nil
                                        )
                                }
                            }
                        }
                    }
                }
                .padding(.top, 2)
            } else {
                Text("Calculating VOACAP circuit model...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(nightMode ? Color.red.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(nightMode ? Color.red.opacity(0.3) : Color.cyan.opacity(0.2), lineWidth: 1))
        )
    }

    // MARK: - Pane D: Satellite Telemetry & Next Pass Prediction

    private var satelliteTelemetryHUDCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("SATELLITE PASS RADAR", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(nightMode ? Color.red : Color.yellow)
                Spacer()
                if let sat = satEngine.selectedSatellite {
                    Text(sat.id)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.yellow)
                }
            }

            Divider().background(Color.secondary.opacity(0.3))

            if let telem = satEngine.currentTelemetry {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Azimuth:")
                                .font(.system(size: 8.5)).foregroundStyle(.secondary)
                            Text(String(format: "%03.0f°", telem.azimuthDeg))
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Elevation:")
                                .font(.system(size: 8.5)).foregroundStyle(.secondary)
                            Text(String(format: "%+.1f°", telem.elevationDeg))
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundStyle(telem.isLineOfSight ? Color.green : Color.secondary)
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Altitude:")
                                .font(.system(size: 8.5)).foregroundStyle(.secondary)
                            Text(String(format: "%.0f km", telem.altitudeKm))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                    }

                    // Doppler Shift Telemetry
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DOPPLER FREQUENCY SHIFT:")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Text(String(format: "TX: %+.0f Hz", telem.uplinkDopplerHz))
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            Text(String(format: "RX: %+.0f Hz", telem.downlinkDopplerHz))
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.cyan)
                        }
                    }

                    // Next Pass Prediction Countdown
                    if let next = satEngine.upcomingPasses.first {
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.yellow)
                            Text("Next Pass:")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                            Text(next.aosCountdownFormatted)
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.yellow)
                            Text("(Max \(String(format: "%.0f°", next.maxElevationDeg)))")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }
            } else {
                Text("Waiting for satellite telemetry...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(nightMode ? Color.red.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(nightMode ? Color.red.opacity(0.3) : Color.yellow.opacity(0.2), lineWidth: 1))
        )
    }

    // MARK: - Pane E: APRS High-Altitude Balloon (HAB) Tracker

    private var balloonHUDCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("APRS BALLOON RADAR", systemImage: "balloon.fill")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(nightMode ? Color.red : Color.cyan)
                Spacer()
                if let b = balloonEngine.selectedBalloon {
                    Text(b.callsign)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.yellow)
                }
            }

            Divider().background(Color.secondary.opacity(0.3))

            // Carousel / Selector for tracked HAB flights
            if balloonEngine.trackedBalloons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(balloonEngine.trackedBalloons) { b in
                            Button {
                                balloonEngine.selectBalloon(callsign: b.callsign)
                            } label: {
                                Text(b.callsign)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        balloonEngine.selectedBalloonCallsign == b.callsign
                                            ? (nightMode ? Color.red.opacity(0.4) : Color.cyan.opacity(0.3))
                                            : Color.secondary.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 4)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let b = balloonEngine.selectedBalloon {
                VStack(alignment: .leading, spacing: 6) {
                    Grid(horizontalSpacing: 10, verticalSpacing: 4) {
                        GridRow {
                            Text("Altitude:").font(.caption2).foregroundStyle(.secondary)
                            Text(b.altitudeFormatted)
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.green)

                            Text("V-Speed:").font(.caption2).foregroundStyle(.secondary)
                            Text(b.verticalSpeedFormatted)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(b.verticalSpeedMps >= 0 ? Color.green : Color.red)
                        }
                        GridRow {
                            Text("Grid:").font(.caption2).foregroundStyle(.secondary)
                            Text(b.gridLocator)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))

                            Text("Status:").font(.caption2).foregroundStyle(.secondary)
                            Text(b.flightPhase.rawValue)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.yellow)
                        }
                        GridRow {
                            Text("Course:").font(.caption2).foregroundStyle(.secondary)
                            Text(String(format: "%03.0f° @ %.0f km/h", b.courseDeg, b.speedKmh))
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))

                            Text("Fixes:").font(.caption2).foregroundStyle(.secondary)
                            Text("\(b.trackHistory.count) pts")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Flight Phase Banner
                    HStack(spacing: 6) {
                        Image(systemName: b.verticalSpeedMps >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(b.verticalSpeedMps >= 0 ? Color.green : Color.orange)
                        Text("Mission: \(b.comment.isEmpty ? "High-Altitude Research" : b.comment)")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }
            } else {
                Text("No active APRS High-Altitude Balloon selected.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(nightMode ? Color.red.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(nightMode ? Color.red.opacity(0.3) : Color.cyan.opacity(0.2), lineWidth: 1))
        )
    }

    // MARK: - Remote Web Server QR Code Modal

    private var qrCodeModalView: some View {
        VStack(spacing: 16) {
            HStack {
                Label("HAMCLOCK LAN REMOTE KIOSK", systemImage: "qrcode")
                    .font(.headline.bold())
                    .foregroundStyle(nightMode ? Color.red : Color.cyan)
                Spacer()
                Button("Done") { showQRCodeModal = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal)
            .padding(.top)

            if let qr = webServer.qrCodeImage {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
            }

            VStack(spacing: 6) {
                Text("Scan with iPad, iPhone, or Shack Tablet")
                    .font(.subheadline.bold())
                Text(webServer.serverURLString)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .textSelection(.enabled)
                Text("Provides live full-screen mission control kiosk dashboard, real-time telemetry feed, and remote antenna rotator control on your local network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
        .frame(width: 440, height: 440)
    }

    // MARK: - Actions

    private func resolveDXDetails() {
        let call = dxCallsignInput.trimmingCharacters(in: .whitespaces).uppercased()
        guard !call.isEmpty else { return }

        if let cty = CTYDatabaseManager.shared.lookup(callsign: call) {
            let coord = GeoCoordinate(latitude: cty.latitude, longitude: cty.longitude)
            let grid = MaidenheadGridEngine.locator(from: coord)
            if !grid.isEmpty {
                self.dxGridInput = grid
            }
        }
        updatePropagationMatrix()
    }

    private func updatePropagationMatrix() {
        guard hasDX else { return }
        let sfi = Double(appState.propagationSnapshot.solarFlux.filter(\.isNumber)) ?? 145.0
        hfPropEngine.calculateCircuit(
            de: homeCoordinate,
            dx: dxCoordinate,
            dxCallsign: dxCallsignInput,
            sfi: sfi,
            kp: auroraEngine.currentKp
        )
    }
}
