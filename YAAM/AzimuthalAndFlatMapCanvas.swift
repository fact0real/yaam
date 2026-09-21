//
//  AzimuthalAndFlatMapCanvas.swift
//  YAAM
//
//  High-Precision NS6T-Style 2D Vector Canvas for Azimuthal Equidistant Great-Circle Map
//  Authentic sky-blue ocean, crisp white continents, curved latitude/longitude graticule mesh,
//  center station badge, active beam heading arrow, 360° calibrated outer compass dial,
//  and real-time solar greyline terminator with subsolar ☀️ marker.
//

import Combine
import CoreGraphics
import SwiftUI

public struct AzimuthalAndFlatMapCanvas: View {
    public var mode: MapProjectionMode
    public var homeCoordinate: GeoCoordinate
    public var markers: [Globe3DMarker]
    public var logSummaries: [String: GridLogSummary]
    public var activeOnAirGrids: Set<String>
    public var showDayNightShadow: Bool
    public var showGridLines: Bool
    public var showTrafficArcs: Bool
    public var showCountryLabels: Bool
    public var showAuroralOval: Bool
    public var showSatelliteTracks: Bool
    public var showDRAPLayer: Bool
    public var showBalloonTracks: Bool
    public var azimuthalRangeKm: Double
    public var stationCallsign: String
    public var onSelectMarker: (Globe3DMarker) -> Void
    public var onSelectGrid: (String) -> Void

    @ObservedObject private var rotatorService = RotatorService.shared
    @ObservedObject private var satEngine = SatelliteTrackingEngine.shared
    @ObservedObject private var auroraEngine = AuroralOvalEngine.shared
    @ObservedObject private var drapEngine = DRAPAbsorptionEngine.shared
    @ObservedObject private var balloonEngine = APRSBalloonTrackingEngine.shared
    @State private var liveDate = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    @AppStorage("azimuthMapTheme") private var selectedThemeRaw: String = AzimuthMapTheme.shackNight.rawValue
    @AppStorage("antennaBeamwidth") private var antennaBeamwidth: Double = 60.0
    @AppStorage("showLongPathRays") private var showLongPathRays: Bool = true
    @AppStorage("clusterSpotAging") private var clusterSpotAging: Bool = true

    private var currentTheme: AzimuthMapTheme {
        AzimuthMapTheme(rawValue: selectedThemeRaw) ?? .shackNight
    }

    public init(
        mode: MapProjectionMode,
        homeCoordinate: GeoCoordinate,
        markers: [Globe3DMarker],
        logSummaries: [String: GridLogSummary],
        activeOnAirGrids: Set<String>,
        showDayNightShadow: Bool = true,
        showGridLines: Bool = true,
        showTrafficArcs: Bool = true,
        showCountryLabels: Bool = true,
        showAuroralOval: Bool = true,
        showSatelliteTracks: Bool = true,
        showDRAPLayer: Bool = true,
        showBalloonTracks: Bool = true,
        azimuthalRangeKm: Double = 20015.0,
        stationCallsign: String = "EP2AES",
        onSelectMarker: @escaping (Globe3DMarker) -> Void,
        onSelectGrid: @escaping (String) -> Void
    ) {
        self.mode = mode
        self.homeCoordinate = homeCoordinate
        self.markers = markers
        self.logSummaries = logSummaries
        self.activeOnAirGrids = activeOnAirGrids
        self.showDayNightShadow = showDayNightShadow
        self.showGridLines = showGridLines
        self.showTrafficArcs = showTrafficArcs
        self.showCountryLabels = showCountryLabels
        self.showAuroralOval = showAuroralOval
        self.showSatelliteTracks = showSatelliteTracks
        self.showDRAPLayer = showDRAPLayer
        self.showBalloonTracks = showBalloonTracks
        self.azimuthalRangeKm = azimuthalRangeKm
        self.stationCallsign = stationCallsign
        self.onSelectMarker = onSelectMarker
        self.onSelectGrid = onSelectGrid
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let subSolar = SolarEphemeris.calculate(at: liveDate)
            let subLunar = LunarEphemeris.calculate(at: liveDate)
            let terminatorPoints = SolarEphemeris.terminatorCoordinates(at: liveDate, stepDegrees: 2.0)

            ZStack(alignment: .bottomLeading) {
                // Outer Canvas Background matching theme
                WorldVectorGeography.colorCanvasBackground(for: currentTheme)
                    .ignoresSafeArea()

                Canvas { context, canvasSize in
                    if mode == .azimuthal {
                        drawAzimuthalMap(
                            context: context,
                            size: canvasSize,
                            home: homeCoordinate,
                            subSolar: subSolar,
                            subLunar: subLunar,
                            terminator: terminatorPoints
                        )
                    } else {
                        drawEquirectangularMap(
                            context: context,
                            size: canvasSize,
                            home: homeCoordinate,
                            subSolar: subSolar,
                            subLunar: subLunar,
                            terminator: terminatorPoints
                        )
                    }
                }
                .drawingGroup()

                // Live UTC GMT Clock & Station Profile Watermark (Bottom-Leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedGMT(liveDate))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(currentTheme == .classicLight ? Color(red: 0.15, green: 0.20, blue: 0.25) : Color(red: 0.70, green: 0.80, blue: 0.90))

                    let grid = MaidenheadGridEngine.locator(from: homeCoordinate)
                    Text("\(stationCallsign.isEmpty ? "EP2AES" : stationCallsign) · \(grid) · Great-Circle")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.secondary)
                }
                .padding(.leading, 18)
                .padding(.bottom, 14)

                // Station Greyline Telemetry HUD Widget (Bottom-Trailing)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        stationGreylineHUD
                    }
                }
                .padding(.trailing, 18)
                .padding(.bottom, 14)

                // Floating Glassmorphism HUD Controls in Azimuth Mode
                if mode == .azimuthal {
                    VStack {
                        HStack {
                            floatingRotatorHUD
                            Spacer()
                            floatingControlsHUD
                        }
                        Spacer()
                    }
                }
            }
            .contentShape(Rectangle())
            .onReceive(timer) { newDate in
                liveDate = newDate
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        handleCanvasTap(location: value.location, size: size)
                    }
            )
        }
    }

    private func formattedGMT(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func handleCanvasTap(location: CGPoint, size: CGSize) {
        if mode == .azimuthal {
            let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
            let outerDialRadius = min(size.width, size.height) / 2.0 - 16.0
            let mapRadius = outerDialRadius - 28.0
            let maxDistKm: Double = max(3000.0, azimuthalRangeKm)

            // 1. Check if user tapped directly on or near an active DX spot marker
            for marker in markers.prefix(45) {
                let target = marker.coordinate
                let distKm = GeodesicMath.distanceKm(from: homeCoordinate, to: target)
                let bearingDeg = GeodesicMath.initialBearing(from: homeCoordinate, to: target)
                let bearingRad = (bearingDeg - 90.0) * .pi / 180.0
                let r = (distKm / maxDistKm) * Double(mapRadius)
                let mx = center.x + CGFloat(r * cos(bearingRad))
                let my = center.y + CGFloat(r * sin(bearingRad))
                if hypot(location.x - mx, location.y - my) <= 16.0 {
                    onSelectMarker(marker)
                    return
                }
            }

            // 2. Otherwise: Click-to-Rotate Antenna to clicked bearing
            let dx = location.x - center.x
            let dy = location.y - center.y
            var bearing = atan2(dy, dx) * 180.0 / .pi + 90.0
            if bearing < 0 { bearing += 360.0 }
            rotatorService.turnTo(azimuth: bearing)
        } else if mode == .gridTracker {
            let lon = (location.x / size.width) * 360.0 - 180.0
            let lat = 90.0 - (location.y / size.height) * 180.0
            let grid4 = MaidenheadGridEngine.locator(from: GeoCoordinate(latitude: lat, longitude: lon))
            onSelectGrid(grid4)
        }
    }

    // MARK: - Floating Glassmorphism HUD Overlays

    private var floatingControlsHUD: some View {
        HStack(spacing: 6) {
            // Theme Switcher Menu
            Menu {
                ForEach(AzimuthMapTheme.allCases) { theme in
                    Button {
                        selectedThemeRaw = theme.rawValue
                    } label: {
                        HStack {
                            Label(theme.rawValue, systemImage: theme.icon)
                            if currentTheme == theme { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: currentTheme.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 26, height: 26)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
            }
            .menuStyle(.borderlessButton)
            .help("Azimuth Map Theme: Shack Night / Classic / Night Vision")

            // Beamwidth Menu
            Menu {
                Text("Antenna Beamwidth Cone").font(.caption).foregroundColor(.secondary)
                Divider()
                ForEach([30.0, 45.0, 60.0, 90.0, 120.0], id: \.self) { bw in
                    Button("\(Int(bw))° (\(beamwidthDesc(bw)))") {
                        antennaBeamwidth = bw
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("\(Int(antennaBeamwidth))°")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal, 7)
                .frame(height: 26)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
            }
            .menuStyle(.borderlessButton)
            .help("Antenna Beamwidth Angle")

            // Short Path / Long Path Toggle
            Button {
                showLongPathRays.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.swap")
                    Text(showLongPathRays ? "SP+LP" : "SP")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .frame(height: 26)
                .background(showLongPathRays ? Color.cyan.opacity(0.2) : Color.clear)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(showLongPathRays ? Color.cyan.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .help("Toggle Short Path (SP) & Long Path (LP) Reverse Rays")

            // Spot Aging Decay Toggle
            Button {
                clusterSpotAging.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Decay")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .frame(height: 26)
                .background(clusterSpotAging ? Color.orange.opacity(0.2) : Color.clear)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(clusterSpotAging ? Color.orange.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .help("Toggle Temporal Spot Aging Decay (0-30 min)")
        }
        .padding(.top, 10)
        .padding(.trailing, 14)
    }

    private var floatingRotatorHUD: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.north.line.fill")
                .rotationEffect(.degrees(rotatorService.currentAzimuth))
                .foregroundColor(rotatorService.isRotating ? .orange : .cyan)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(String(format: "%03d°", Int(rotatorService.currentAzimuth)))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                    Text(GeodesicMath.compassCardinal(for: rotatorService.currentAzimuth))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                if rotatorService.isRotating {
                    Text("Turning: \(Int(rotatorService.targetAzimuth))°")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.orange)
                } else {
                    Text("Click map to rotate")
                        .font(.system(size: 7.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Divider().frame(height: 16)

            // Quick Cardinal Buttons
            HStack(spacing: 2) {
                ForEach([("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)], id: \.0) { card, deg in
                    Button(card) {
                        rotatorService.turnTo(azimuth: deg)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .frame(width: 18, height: 18)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.2), lineWidth: 0.8))
        .padding(.top, 10)
        .padding(.leading, 14)
    }

    private func beamwidthDesc(_ bw: Double) -> String {
        switch Int(bw) {
        case 30: return "Narrow Yagi"
        case 45: return "Monoband"
        case 60: return "Tribander/Hex"
        case 90: return "Dipole"
        case 120: return "Broad"
        default: return "\(Int(bw))°"
        }
    }

    // MARK: - Azimuthal Equidistant Map Drawing

    private func drawAzimuthalMap(
        context: GraphicsContext,
        size: CGSize,
        home: GeoCoordinate,
        subSolar: SubSolarPosition,
        subLunar: SubLunarPosition,
        terminator: [GeoCoordinate]
    ) {
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let outerDialRadius = min(size.width, size.height) / 2.0 - 16.0
        let mapRadius = outerDialRadius - 28.0
        let maxDistKm: Double = max(3000.0, azimuthalRangeKm)

        func azimuthalPoint(lat: Double, lon: Double) -> CGPoint {
            let target = GeoCoordinate(latitude: lat, longitude: lon)
            let distKm = GeodesicMath.distanceKm(from: home, to: target)
            let bearingDeg = GeodesicMath.initialBearing(from: home, to: target)
            let bearingRad = (bearingDeg - 90.0) * .pi / 180.0

            let r = (distKm / maxDistKm) * Double(mapRadius)
            let x = center.x + CGFloat(r * cos(bearingRad))
            let y = center.y + CGFloat(r * sin(bearingRad))
            return CGPoint(x: x, y: y)
        }

        // 1. Fill Ocean Base Disc (Dynamic Theme Color)
        let mapDisc = Path(ellipseIn: CGRect(x: center.x - mapRadius, y: center.y - mapRadius, width: mapRadius * 2, height: mapRadius * 2))
        context.fill(mapDisc, with: .color(WorldVectorGeography.colorOcean(for: currentTheme)))
        context.stroke(mapDisc, with: .color(WorldVectorGeography.colorDialRing(for: currentTheme)), lineWidth: 1.5)

        // 2. Concentric Distance Range Rings (5,000 km, 10,000 km, 15,000 km, 20,000 km)
        let distanceSteps: [Double] = [5000.0, 10000.0, 15000.0, 20000.0].filter { $0 <= maxDistKm }
        for dist in distanceSteps {
            let r = CGFloat((dist / maxDistKm) * Double(mapRadius))
            let ringPath = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            context.stroke(ringPath, with: .color(Color.white.opacity(0.25)), lineWidth: 0.8)
        }

        // 3. Curved Lat / Lon Graticule Mesh
        if showGridLines {
            let graticules = WorldVectorGeography.generateGraticuleLines()
            for line in graticules {
                var path = Path()
                var started = false
                for coord in line.coordinates {
                    let pt = azimuthalPoint(lat: coord.latitude, lon: coord.longitude)
                    let dist = hypot(pt.x - center.x, pt.y - center.y)
                    if dist <= mapRadius {
                        if !started {
                            path.move(to: pt)
                            started = true
                        } else {
                            path.addLine(to: pt)
                        }
                    } else {
                        started = false
                    }
                }
                context.stroke(
                    path,
                    with: .color(WorldVectorGeography.colorGraticule(for: currentTheme)),
                    lineWidth: line.isMajor ? 1.0 : 0.6
                )
            }
        }

        // 4. High-Resolution Continents & Island Polygons with Coastal Outlines
        for poly in WorldVectorGeography.landmassPolygons {
            guard poly.coordinates.count >= 3 else { continue }
            var path = Path()
            var started = false

            for pt in poly.coordinates {
                let p = azimuthalPoint(lat: pt.latitude, lon: pt.longitude)
                let distFromCenter = hypot(p.x - center.x, p.y - center.y)
                if distFromCenter <= mapRadius + 2.0 {
                    if !started {
                        path.move(to: p)
                        started = true
                    } else {
                        path.addLine(to: p)
                    }
                }
            }

            if started {
                path.closeSubpath()
                context.fill(path, with: .color(WorldVectorGeography.colorLand(for: currentTheme)))
                context.stroke(path, with: .color(WorldVectorGeography.colorLandStroke(for: currentTheme)), lineWidth: 1.0)
            }
        }

        // 5. Internal Country Borders
        for border in WorldVectorGeography.countryBorders {
            var path = Path()
            var started = false
            for pt in border.coordinates {
                let p = azimuthalPoint(lat: pt.latitude, lon: pt.longitude)
                let dist = hypot(p.x - center.x, p.y - center.y)
                if dist <= mapRadius {
                    if !started {
                        path.move(to: p)
                        started = true
                    } else {
                        path.addLine(to: p)
                    }
                }
            }
            context.stroke(
                path,
                with: .color(WorldVectorGeography.colorBorder(for: currentTheme)),
                style: StrokeStyle(lineWidth: 0.6, dash: [3, 2])
            )
        }

        // 6. Day / Night Solar Greyline Terminator Shadow (Civil / Nautical Twilight Gradients)
        if showDayNightShadow {
            drawAzimuthalSolarNightShadow(
                context: context,
                center: center,
                mapRadius: mapRadius,
                subSolar: subSolar,
                toScreen: azimuthalPoint
            )
        }

        // 7. Subsolar Point (☀️) and Sublunar Point (🌙)
        let sunPt = azimuthalPoint(lat: subSolar.latitude, lon: subSolar.longitude)
        let sunDist = hypot(sunPt.x - center.x, sunPt.y - center.y)
        if sunDist <= mapRadius {
            context.draw(
                Text("☀️")
                    .font(.system(size: 20)),
                at: sunPt,
                anchor: .center
            )
        }

        let moonPt = azimuthalPoint(lat: subLunar.latitude, lon: subLunar.longitude)
        let moonDist = hypot(moonPt.x - center.x, moonPt.y - center.y)
        if moonDist <= mapRadius {
            context.draw(
                Text("🌙")
                    .font(.system(size: 16)),
                at: moonPt,
                anchor: .center
            )
            context.draw(
                Text("\(Int(subLunar.phasePercent * 100))%")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.cyan),
                at: CGPoint(x: moonPt.x, y: moonPt.y + 11),
                anchor: .center
            )
        }

        // 7b. Real-Time NOAA OVATION Auroral Oval Overlay
        if showAuroralOval {
            drawAuroralOval(
                context: context,
                center: center,
                mapRadius: mapRadius,
                toScreen: azimuthalPoint
            )
        }

        // 7c. Active Amateur Satellite Ground Track & Footprint
        if showSatelliteTracks {
            drawSatelliteTelemetry(
                context: context,
                center: center,
                mapRadius: mapRadius,
                toScreen: azimuthalPoint
            )
        }

        // 7d. NOAA D-RAP Ionospheric Absorption Heatmap
        if showDRAPLayer {
            drawDRAPLayer(
                context: context,
                center: center,
                mapRadius: mapRadius,
                toScreen: azimuthalPoint
            )
        }

        // 7e. APRS & High-Altitude Balloon Tracking
        if showBalloonTracks {
            drawBalloonTelemetry(
                context: context,
                center: center,
                mapRadius: mapRadius,
                toScreen: azimuthalPoint
            )
        }

        // 8. Antenna Beamwidth Cone (From Center Origin to Perimeter)
        drawAntennaBeamwidthCone(
            context: context,
            center: center,
            mapRadius: mapRadius
        )

        // 9. Country Labels & Major DXCC Entities with Collision Avoidance
        if showCountryLabels {
            drawCountryLabelsWithCollisionAvoidance(
                context: context,
                center: center,
                mapRadius: mapRadius,
                toScreen: azimuthalPoint
            )
        }

        // 10. Great Circle Traffic Rays (Band Color-Coded SP & LP) + Temporal Spot Decay
        if showTrafficArcs {
            drawTrafficRaysAndMarkers(
                context: context,
                center: center,
                mapRadius: mapRadius,
                home: home,
                toScreen: azimuthalPoint
            )
        }

        // 11. Active Rotator Beam Heading Needle & Target Needle
        drawRotatorNeedles(
            context: context,
            center: center,
            mapRadius: mapRadius,
            outerDialRadius: outerDialRadius
        )

        // 12. Center Station Callout Badge (Authentic Themed Badge)
        drawCenterStationCalloutBadge(
            context: context,
            center: center,
            home: home
        )

        // 13. Calibrated 360° Compass Dial Bezel
        drawCompassDial(
            context: context,
            center: center,
            innerRadius: mapRadius,
            outerRadius: outerDialRadius
        )
    }

    // MARK: - Antenna Beamwidth Cone Rendering

    private func drawAntennaBeamwidthCone(
        context: GraphicsContext,
        center: CGPoint,
        mapRadius: CGFloat
    ) {
        let beamAzimuth = rotatorService.currentAzimuth
        let halfBeam = antennaBeamwidth / 2.0
        let startAngleDeg = beamAzimuth - halfBeam - 90.0
        let endAngleDeg = beamAzimuth + halfBeam - 90.0
        let coneRadius = Double(mapRadius) * 0.98

        var conePath = Path()
        conePath.move(to: center)
        conePath.addArc(
            center: center,
            radius: CGFloat(coneRadius),
            startAngle: Angle(degrees: startAngleDeg),
            endAngle: Angle(degrees: endAngleDeg),
            clockwise: false
        )
        conePath.closeSubpath()

        let coneColor: Color
        switch currentTheme {
        case .shackNight:
            coneColor = Color(red: 0.18, green: 0.80, blue: 0.95).opacity(0.18)
        case .classicLight:
            coneColor = Color(red: 0.98, green: 0.70, blue: 0.15).opacity(0.24)
        case .nightVision:
            coneColor = Color(red: 1.00, green: 0.20, blue: 0.20).opacity(0.22)
        }
        context.fill(conePath, with: .color(coneColor))

        // Radial Boundary Lines
        let p1 = CGPoint(
            x: center.x + CGFloat(coneRadius * cos(startAngleDeg * .pi / 180.0)),
            y: center.y + CGFloat(coneRadius * sin(startAngleDeg * .pi / 180.0))
        )
        var line1 = Path()
        line1.move(to: center)
        line1.addLine(to: p1)
        context.stroke(line1, with: .color(coneColor.opacity(0.55)), lineWidth: 1.0)

        let p2 = CGPoint(
            x: center.x + CGFloat(coneRadius * cos(endAngleDeg * .pi / 180.0)),
            y: center.y + CGFloat(coneRadius * sin(endAngleDeg * .pi / 180.0))
        )
        var line2 = Path()
        line2.move(to: center)
        line2.addLine(to: p2)
        context.stroke(line2, with: .color(coneColor.opacity(0.55)), lineWidth: 1.0)
    }

    // MARK: - Country Labels with Collision Avoidance

    private func drawCountryLabelsWithCollisionAvoidance(
        context: GraphicsContext,
        center: CGPoint,
        mapRadius: CGFloat,
        toScreen: (Double, Double) -> CGPoint
    ) {
        var occupiedRects: [CGRect] = []

        // Register center station badge exclusion zone
        let badgeWidth: CGFloat = 116.0
        let badgeHeight: CGFloat = 52.0
        let centerBox = CGRect(
            x: center.x - badgeWidth / 2.0 - 6.0,
            y: center.y - badgeHeight - 16.0,
            width: badgeWidth + 12.0,
            height: badgeHeight + 22.0
        )
        occupiedRects.append(centerBox)

        // Sort by priority (1: Major countries, 2: Secondary, 3: Small islands)
        let sortedCountries = WorldVectorGeography.countries.sorted { $0.priority < $1.priority }

        for country in sortedCountries {
            let pt = toScreen(country.center.latitude, country.center.longitude)
            let dist = hypot(pt.x - center.x, pt.y - center.y)
            guard dist <= mapRadius - 14.0 else { continue }

            let labelPos = CGPoint(x: pt.x + country.labelOffset.x, y: pt.y + country.labelOffset.y)

            // Test Full Label Box
            let fullWidth: CGFloat = 46.0
            let fullHeight: CGFloat = 20.0
            let fullBox = CGRect(x: labelPos.x - fullWidth / 2.0, y: labelPos.y - fullHeight / 2.0, width: fullWidth, height: fullHeight)

            let collidesFull = occupiedRects.contains { $0.intersects(fullBox) }

            if !collidesFull {
                // Draw Full Label (Name + Prefix)
                context.draw(
                    Text("\(country.name)\n\(country.primaryPrefix)")
                        .font(.system(size: 8.0, weight: .bold))
                        .foregroundColor(WorldVectorGeography.colorLabelText(for: currentTheme)),
                    at: labelPos,
                    anchor: .center
                )
                occupiedRects.append(fullBox.insetBy(dx: -3, dy: -2))
            } else {
                // Collision occurred! Try compact prefix badge pill
                let badgeW: CGFloat = 22.0
                let badgeH: CGFloat = 12.0
                let badgeBox = CGRect(x: labelPos.x - badgeW / 2.0, y: labelPos.y - badgeH / 2.0, width: badgeW, height: badgeH)

                let collidesBadge = occupiedRects.contains { $0.intersects(badgeBox) }
                if !collidesBadge {
                    let pill = Path(roundedRect: badgeBox, cornerRadius: 2.5)
                    context.fill(pill, with: .color(WorldVectorGeography.colorCanvasBackground(for: currentTheme).opacity(0.85)))
                    context.stroke(pill, with: .color(WorldVectorGeography.colorBorder(for: currentTheme)), lineWidth: 0.6)

                    context.draw(
                        Text(country.primaryPrefix)
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundColor(WorldVectorGeography.colorLabelText(for: currentTheme)),
                        at: labelPos,
                        anchor: .center
                    )
                    occupiedRects.append(badgeBox.insetBy(dx: -2, dy: -1))
                }
            }
        }
    }

    // MARK: - Traffic Rays (Band-Colored SP & LP) & Spot Aging

    private func drawTrafficRaysAndMarkers(
        context: GraphicsContext,
        center: CGPoint,
        mapRadius: CGFloat,
        home: GeoCoordinate,
        toScreen: (Double, Double) -> CGPoint
    ) {
        for m in markers.prefix(45) {
            let targetPt = toScreen(m.coordinate.latitude, m.coordinate.longitude)
            let dist = hypot(targetPt.x - center.x, targetPt.y - center.y)
            guard dist <= mapRadius else { continue }

            let bandColor = WorldVectorGeography.bandColor(for: m.band)
            let ageSeconds = max(0, liveDate.timeIntervalSince(m.timestamp))

            // Temporal Spot Decay
            let alpha: Double
            let isFresh: Bool
            if clusterSpotAging {
                if ageSeconds < 180 { // < 3 mins
                    alpha = 1.0
                    isFresh = ageSeconds < 60
                } else if ageSeconds < 600 { // < 10 mins
                    alpha = 0.80
                    isFresh = false
                } else if ageSeconds < 1200 { // < 20 mins
                    alpha = 0.50
                    isFresh = false
                } else if ageSeconds < 1800 { // < 30 mins
                    alpha = 0.28
                    isFresh = false
                } else {
                    alpha = 0.12
                    isFresh = false
                }
            } else {
                alpha = 0.85
                isFresh = false
            }

            // Evaluate Greyline Propagation Duct Alignment
            let (isGreylineDuct, _) = SolarEphemeris.isPathInGreyline(from: home, to: m.coordinate, at: liveDate)

            // Greyline Duct Wide Amber Glow Behind Ray
            if isGreylineDuct {
                var ductGlow = Path()
                ductGlow.move(to: center)
                ductGlow.addLine(to: targetPt)
                context.stroke(
                    ductGlow,
                    with: .color(Color(red: 1.0, green: 0.78, blue: 0.22).opacity(alpha * 0.65)),
                    lineWidth: 4.2
                )
            }

            // Short Path (SP) Ray - Solid Line
            var spBeam = Path()
            spBeam.move(to: center)
            spBeam.addLine(to: targetPt)
            context.stroke(spBeam, with: .color(bandColor.opacity(alpha * 0.85)), lineWidth: 1.6)

            // Long Path (LP) Ray - Dashed Line in 180° Reverse Bearing
            if showLongPathRays {
                let spBearing = GeodesicMath.initialBearing(from: home, to: m.coordinate)
                let lpBearing = (spBearing + 180.0).truncatingRemainder(dividingBy: 360.0)
                let lpRad = (lpBearing - 90.0) * .pi / 180.0
                let lpEnd = CGPoint(
                    x: center.x + CGFloat(Double(mapRadius) * cos(lpRad)),
                    y: center.y + CGFloat(Double(mapRadius) * sin(lpRad))
                )
                var lpBeam = Path()
                lpBeam.move(to: center)
                lpBeam.addLine(to: lpEnd)
                context.stroke(
                    lpBeam,
                    with: .color(bandColor.opacity(alpha * 0.40)),
                    style: StrokeStyle(lineWidth: 1.0, dash: [4, 4])
                )
            }

            // Spot Marker Target Dot
            let markerRect = CGRect(x: targetPt.x - 4, y: targetPt.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: markerRect), with: .color(bandColor.opacity(alpha)))
            context.stroke(
                Path(ellipseIn: markerRect),
                with: .color(Color.white.opacity(alpha * 0.9)),
                lineWidth: 1.2
            )

            // Greyline Duct Pulsing Halo Ring
            if isGreylineDuct {
                let ductR: CGFloat = 8.5 + 2.5 * sin(liveDate.timeIntervalSinceReferenceDate * 3.5)
                let ductRect = CGRect(x: targetPt.x - ductR, y: targetPt.y - ductR, width: ductR * 2, height: ductR * 2)
                context.stroke(
                    Path(ellipseIn: ductRect),
                    with: .color(Color(red: 1.0, green: 0.82, blue: 0.28).opacity(alpha * 0.90)),
                    lineWidth: 1.6
                )
            } else if isFresh {
                // Pulsing Ring for Fresh (< 60s) Spots
                let pulseR = 6.0 + 2.5 * sin(liveDate.timeIntervalSinceReferenceDate * 4.0)
                let pulseRect = CGRect(x: targetPt.x - pulseR, y: targetPt.y - pulseR, width: pulseR * 2, height: pulseR * 2)
                context.stroke(Path(ellipseIn: pulseRect), with: .color(bandColor.opacity(0.85)), lineWidth: 1.0)
            }
        }
    }

    // MARK: - Rotator Needles (Active Azimuth & Target Heading)

    private func drawRotatorNeedles(
        context: GraphicsContext,
        center: CGPoint,
        mapRadius: CGFloat,
        outerDialRadius: CGFloat
    ) {
        let beamAzimuth = rotatorService.currentAzimuth
        let beamRad = (beamAzimuth - 90.0) * .pi / 180.0
        let targetAzimuth = rotatorService.targetAzimuth

        // Target Heading Indicator (if rotating or differs from current heading)
        if rotatorService.isRotating || abs(targetAzimuth - beamAzimuth) > 1.5 {
            let targetRad = (targetAzimuth - 90.0) * .pi / 180.0
            let targetDist = Double(mapRadius) * 0.95
            let targetPt = CGPoint(
                x: center.x + CGFloat(targetDist * cos(targetRad)),
                y: center.y + CGFloat(targetDist * sin(targetRad))
            )
            var targetLine = Path()
            targetLine.move(to: center)
            targetLine.addLine(to: targetPt)
            context.stroke(
                targetLine,
                with: .color(Color.cyan.opacity(0.75)),
                style: StrokeStyle(lineWidth: 1.4, dash: [4, 3])
            )

            let markerTip = CGPoint(
                x: center.x + CGFloat(Double(outerDialRadius - 4) * cos(targetRad)),
                y: center.y + CGFloat(Double(outerDialRadius - 4) * sin(targetRad))
            )
            context.draw(
                Text("🎯")
                    .font(.system(size: 11)),
                at: markerTip,
                anchor: .center
            )
        }

        // Active Rotator Heading Needle
        let needleLen = Double(mapRadius) * 0.90
        let needleTailLen = 16.0
        let needleTip = CGPoint(
            x: center.x + CGFloat(needleLen * cos(beamRad)),
            y: center.y + CGFloat(needleLen * sin(beamRad))
        )
        let needleTail = CGPoint(
            x: center.x - CGFloat(needleTailLen * cos(beamRad)),
            y: center.y - CGFloat(needleTailLen * sin(beamRad))
        )

        let needleColor: Color = currentTheme == .nightVision ? Color.red : Color(red: 0.95, green: 0.25, blue: 0.20)

        var needleLine = Path()
        needleLine.move(to: needleTail)
        needleLine.addLine(to: needleTip)
        context.stroke(needleLine, with: .color(needleColor), lineWidth: 2.2)

        // Arrowhead at tip
        let headLen: CGFloat = 13.0
        let headAngle: CGFloat = 0.38
        let arrowPt1 = CGPoint(
            x: needleTip.x - headLen * CGFloat(cos(beamRad - Double(headAngle))),
            y: needleTip.y - headLen * CGFloat(sin(beamRad - Double(headAngle)))
        )
        let arrowPt2 = CGPoint(
            x: needleTip.x - headLen * CGFloat(cos(beamRad + Double(headAngle))),
            y: needleTip.y - headLen * CGFloat(sin(beamRad + Double(headAngle)))
        )
        var arrowHead = Path()
        arrowHead.move(to: needleTip)
        arrowHead.addLine(to: arrowPt1)
        arrowHead.addLine(to: arrowPt2)
        arrowHead.closeSubpath()
        context.fill(arrowHead, with: .color(needleColor))
    }

    // MARK: - Center Station Callout Badge

    private func drawCenterStationCalloutBadge(
        context: GraphicsContext,
        center: CGPoint,
        home: GeoCoordinate
    ) {
        let badgeWidth: CGFloat = 114.0
        let badgeHeight: CGFloat = 46.0
        let badgeRect = CGRect(
            x: center.x - badgeWidth / 2.0,
            y: center.y - badgeHeight - 12.0,
            width: badgeWidth,
            height: badgeHeight
        )

        // Drop Shadow
        let shadowRect = badgeRect.offsetBy(dx: 0, dy: 2)
        context.fill(
            Path(roundedRect: shadowRect, cornerRadius: 5),
            with: .color(Color.black.opacity(0.30))
        )

        var badgeBg: Color
        var badgeStroke: Color
        var callColor: Color
        var subColor: Color

        let isRover = RoverModeEngine.shared.isRoverActive
        if isRover {
            badgeBg = Color(red: 0.14, green: 0.08, blue: 0.02)
            badgeStroke = Color.orange
            callColor = Color(red: 1.0, green: 0.75, blue: 0.2)
            subColor = Color(red: 0.95, green: 0.85, blue: 0.65)
        } else {
            switch currentTheme {
            case .shackNight:
                badgeBg = Color(red: 0.08, green: 0.12, blue: 0.18)
                badgeStroke = Color(red: 0.22, green: 0.74, blue: 0.97)
                callColor = Color(red: 0.95, green: 0.98, blue: 1.00)
                subColor = Color(red: 0.65, green: 0.75, blue: 0.85)
            case .classicLight:
                badgeBg = Color(red: 0.93, green: 0.96, blue: 1.00)
                badgeStroke = Color(red: 0.20, green: 0.40, blue: 0.70)
                callColor = Color(red: 0.05, green: 0.10, blue: 0.25)
                subColor = Color(red: 0.25, green: 0.35, blue: 0.45)
            case .nightVision:
                badgeBg = Color(red: 0.18, green: 0.02, blue: 0.02)
                badgeStroke = Color(red: 0.90, green: 0.20, blue: 0.20)
                callColor = Color(red: 1.00, green: 0.80, blue: 0.80)
                subColor = Color(red: 0.85, green: 0.40, blue: 0.40)
            }
        }

        let badgePath = Path(roundedRect: badgeRect, cornerRadius: 5)
        context.fill(badgePath, with: .color(badgeBg))
        context.stroke(badgePath, with: .color(badgeStroke), lineWidth: 1.2)

        // Badge Callout Arrow downwards
        var pointer = Path()
        pointer.move(to: CGPoint(x: center.x - 6, y: badgeRect.maxY))
        pointer.addLine(to: CGPoint(x: center.x, y: badgeRect.maxY + 7))
        pointer.addLine(to: CGPoint(x: center.x + 6, y: badgeRect.maxY))
        pointer.closeSubpath()
        context.fill(pointer, with: .color(badgeBg))
        context.stroke(pointer, with: .color(badgeStroke), lineWidth: 1.2)

        // Callsign Text
        let stationCall = stationCallsign.isEmpty ? "EP2AES" : stationCallsign
        context.draw(
            Text(stationCall)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(callColor),
            at: CGPoint(x: center.x, y: badgeRect.minY + 12),
            anchor: .center
        )

        // Grid & Location Subtitle
        let grid = MaidenheadGridEngine.locator(from: home)
        let latStr = String(format: "%.2f°%@", abs(home.latitude), home.latitude >= 0 ? "N" : "S")
        let lonStr = String(format: "%.2f°%@", abs(home.longitude), home.longitude >= 0 ? "E" : "W")

        context.draw(
            Text("\(grid) · \(latStr) \(lonStr)")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(subColor),
            at: CGPoint(x: center.x, y: badgeRect.minY + 26),
            anchor: .center
        )

        context.draw(
            Text(isRover ? "⚡️ ROVER ORIGIN" : "Center Origin")
                .font(.system(size: 7.5, weight: isRover ? .bold : .regular))
                .foregroundColor(isRover ? Color.orange : subColor.opacity(0.8)),
            at: CGPoint(x: center.x, y: badgeRect.minY + 37),
            anchor: .center
        )

        // Center Pin Dot
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)),
            with: .color(badgeStroke)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)),
            with: .color(Color.white),
            lineWidth: 1.2
        )
    }

    // MARK: - 360° Calibrated Compass Dial Bezel

    private func drawCompassDial(
        context: GraphicsContext,
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) {
        let dialColor = WorldVectorGeography.colorDialRing(for: currentTheme)
        let dialTextColor = WorldVectorGeography.colorDialText(for: currentTheme)

        // Outer Dial Background Ring
        let bezelRing = Path { p in
            p.addEllipse(in: CGRect(x: center.x - outerRadius, y: center.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2))
        }
        context.stroke(bezelRing, with: .color(dialColor), lineWidth: 1.4)

        // Inner Divider Line
        let innerRing = Path { p in
            p.addEllipse(in: CGRect(x: center.x - innerRadius, y: center.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2))
        }
        context.stroke(innerRing, with: .color(dialColor.opacity(0.7)), lineWidth: 1.0)

        // 360 Degree Ticks & Labels
        for deg in 0..<360 {
            let rad = (Double(deg) - 90.0) * .pi / 180.0
            let isMajor = deg % 10 == 0
            let isMedium = deg % 5 == 0

            let tickLen: CGFloat = isMajor ? 9.0 : (isMedium ? 5.5 : 2.5)
            let pOuter = CGPoint(x: center.x + CGFloat(Double(outerRadius) * cos(rad)), y: center.y + CGFloat(Double(outerRadius) * sin(rad)))
            let pInner = CGPoint(x: center.x + CGFloat(Double(outerRadius - tickLen) * cos(rad)), y: center.y + CGFloat(Double(outerRadius - tickLen) * sin(rad)))

            var tickPath = Path()
            tickPath.move(to: pInner)
            tickPath.addLine(to: pOuter)
            context.stroke(tickPath, with: .color(dialColor), lineWidth: isMajor ? 1.2 : 0.6)

            if isMajor {
                let textRadius = outerRadius + 13.0
                let labelPt = CGPoint(x: center.x + CGFloat(Double(textRadius) * cos(rad)), y: center.y + CGFloat(Double(textRadius) * sin(rad)))
                context.draw(
                    Text("\(deg)°")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(dialTextColor),
                    at: labelPt,
                    anchor: .center
                )
            }
        }
    }

    // MARK: - Solar Night Shadow & Glowing Golden Greyline Ribbon

    private func drawAzimuthalSolarNightShadow(
        context: GraphicsContext,
        center: CGPoint,
        mapRadius: CGFloat,
        subSolar: SubSolarPosition,
        toScreen: (Double, Double) -> CGPoint
    ) {
        let maxDistKm: Double = max(3000.0, azimuthalRangeKm)
        let angularSteps = 90 // every 4 degrees
        let radialSteps = 24  // 24 rings from center to perimeter

        let dAngle = 360.0 / Double(angularSteps)
        let dRadius = Double(mapRadius) / Double(radialSteps)

        var nightPath = Path()
        var nauticalPath = Path()
        var civilPath = Path()

        let homeLatRad = homeCoordinate.latitude * .pi / 180.0
        let homeLonRad = homeCoordinate.longitude * .pi / 180.0
        let sunDecRad = subSolar.latitude * .pi / 180.0
        let sunLonRad = subSolar.longitude * .pi / 180.0

        for rIdx in 0..<radialSteps {
            let r0 = Double(rIdx) * dRadius
            let r1 = Double(rIdx + 1) * dRadius
            let rMid = (r0 + r1) * 0.5
            let distKm = (rMid / Double(mapRadius)) * maxDistKm
            let distRad = distKm / GeodesicMath.earthRadiusKm

            for aIdx in 0..<angularSteps {
                let az0 = Double(aIdx) * dAngle
                let az1 = Double(aIdx + 1) * dAngle
                let azMid = (az0 + az1) * 0.5
                let azMidRad = azMid * .pi / 180.0

                // Direct geodesic formula to find lat/lon of cell center
                let sinLat = sin(homeLatRad) * cos(distRad) + cos(homeLatRad) * sin(distRad) * cos(azMidRad)
                let ptLatRad = asin(max(-1.0, min(1.0, sinLat)))
                let y = sin(azMidRad) * sin(distRad) * cos(homeLatRad)
                let x = cos(distRad) - sin(homeLatRad) * sin(ptLatRad)
                let dLonRad = atan2(y, x)
                let ptLonRad = homeLonRad + dLonRad

                // Solar elevation
                let sinAlt = sin(ptLatRad) * sin(sunDecRad) + cos(ptLatRad) * cos(sunDecRad) * cos(ptLonRad - sunLonRad)
                let altDeg = asin(max(-1.0, min(1.0, sinAlt))) * 180.0 / .pi

                if altDeg < 0.0 {
                    let ang0Rad = (az0 - 90.0) * .pi / 180.0
                    let ang1Rad = (az1 - 90.0) * .pi / 180.0

                    let p0 = CGPoint(x: center.x + CGFloat(r0 * cos(ang0Rad)), y: center.y + CGFloat(r0 * sin(ang0Rad)))
                    let p1 = CGPoint(x: center.x + CGFloat(r0 * cos(ang1Rad)), y: center.y + CGFloat(r0 * sin(ang1Rad)))
                    let p2 = CGPoint(x: center.x + CGFloat(r1 * cos(ang1Rad)), y: center.y + CGFloat(r1 * sin(ang1Rad)))
                    let p3 = CGPoint(x: center.x + CGFloat(r1 * cos(ang0Rad)), y: center.y + CGFloat(r1 * sin(ang0Rad)))

                    var quad = Path()
                    quad.move(to: p0)
                    quad.addLine(to: p1)
                    quad.addLine(to: p2)
                    quad.addLine(to: p3)
                    quad.closeSubpath()

                    if altDeg >= -6.0 {
                        civilPath.addPath(quad)
                    } else if altDeg >= -12.0 {
                        nauticalPath.addPath(quad)
                    } else {
                        nightPath.addPath(quad)
                    }
                }
            }
        }

        // Fill Night Shadow Tiers
        let deepNightColor: Color
        let nauticalColor: Color
        let civilColor: Color

        switch currentTheme {
        case .shackNight:
            deepNightColor = Color(red: 0.02, green: 0.03, blue: 0.08).opacity(0.60)
            nauticalColor = Color(red: 0.06, green: 0.08, blue: 0.22).opacity(0.42)
            civilColor = Color(red: 0.28, green: 0.16, blue: 0.06).opacity(0.28)
        case .classicLight:
            deepNightColor = Color(red: 0.05, green: 0.08, blue: 0.16).opacity(0.45)
            nauticalColor = Color(red: 0.10, green: 0.15, blue: 0.28).opacity(0.30)
            civilColor = Color(red: 0.35, green: 0.25, blue: 0.10).opacity(0.20)
        case .nightVision:
            deepNightColor = Color(red: 0.04, green: 0.00, blue: 0.00).opacity(0.65)
            nauticalColor = Color(red: 0.15, green: 0.02, blue: 0.02).opacity(0.45)
            civilColor = Color(red: 0.30, green: 0.05, blue: 0.05).opacity(0.30)
        }

        context.fill(nightPath, with: .color(deepNightColor))
        context.fill(nauticalPath, with: .color(nauticalColor))
        context.fill(civilPath, with: .color(civilColor))

        // Draw Glowing Golden / Amber Greyline Ribbon along the Terminator
        let termCoords = SolarEphemeris.terminatorCoordinates(at: liveDate, stepDegrees: 1.5)
        var ribbonPath = Path()
        var ribbonStarted = false
        var lastPt: CGPoint?

        for coord in termCoords {
            let pt = toScreen(coord.latitude, coord.longitude)
            let dist = hypot(pt.x - center.x, pt.y - center.y)

            if dist <= mapRadius + 2.0 {
                if let lp = lastPt, hypot(pt.x - lp.x, pt.y - lp.y) > mapRadius * 0.4 {
                    ribbonPath.move(to: pt)
                } else if !ribbonStarted {
                    ribbonPath.move(to: pt)
                    ribbonStarted = true
                } else {
                    ribbonPath.addLine(to: pt)
                }
                lastPt = pt
            } else {
                ribbonStarted = false
                lastPt = nil
            }
        }

        // Twilight Ribbon: Amber outer halo + Gold core + Bright filament center
        context.stroke(
            ribbonPath,
            with: .color(Color(red: 1.0, green: 0.72, blue: 0.18).opacity(0.35)),
            lineWidth: 7.0
        )
        context.stroke(
            ribbonPath,
            with: .color(Color(red: 1.0, green: 0.85, blue: 0.32).opacity(0.80)),
            lineWidth: 2.4
        )
        context.stroke(
            ribbonPath,
            with: .color(Color(red: 1.0, green: 0.96, blue: 0.70).opacity(0.95)),
            lineWidth: 1.0
        )
    }

    // MARK: - Equirectangular 2D Map (Flat GridTracker)

    private func drawEquirectangularMap(
        context: GraphicsContext,
        size: CGSize,
        home: GeoCoordinate,
        subSolar: SubSolarPosition,
        subLunar: SubLunarPosition,
        terminator: [GeoCoordinate]
    ) {
        func toFlatScreen(lat: Double, lon: Double) -> CGPoint {
            let x = ((lon + 180.0) / 360.0) * size.width
            let y = ((90.0 - lat) / 180.0) * size.height
            return CGPoint(x: x, y: y)
        }

        // 1. Ocean Background
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(WorldVectorGeography.colorOcean(for: currentTheme)))

        // 2. Lat / Lon Graticule Grid
        if showGridLines {
            for lat in stride(from: -75.0, through: 75.0, by: 15.0) {
                let y = ((90.0 - lat) / 180.0) * size.height
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(p, with: .color(Color.white.opacity(abs(lat) < 0.1 ? 0.50 : 0.25)), lineWidth: abs(lat) < 0.1 ? 1.0 : 0.5)
            }
            for lon in stride(from: -180.0, through: 180.0, by: 30.0) {
                let x = ((lon + 180.0) / 360.0) * size.width
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(p, with: .color(Color.white.opacity(abs(lon) < 0.1 ? 0.50 : 0.25)), lineWidth: abs(lon) < 0.1 ? 1.0 : 0.5)
            }
        }

        // 3. Landmass Polygons
        for poly in WorldVectorGeography.landmassPolygons {
            guard poly.coordinates.count >= 3 else { continue }
            var path = Path()
            var started = false

            for pt in poly.coordinates {
                let p = toFlatScreen(lat: pt.latitude, lon: pt.longitude)
                if !started {
                    path.move(to: p)
                    started = true
                } else {
                    path.addLine(to: p)
                }
            }

            if started {
                path.closeSubpath()
                context.fill(path, with: .color(WorldVectorGeography.colorLand(for: currentTheme)))
                context.stroke(path, with: .color(WorldVectorGeography.colorLandStroke(for: currentTheme)), lineWidth: 0.9)
            }
        }

        // 4. Day / Night Solar Terminator Shadow & Glowing Greyline Ribbon
        if showDayNightShadow {
            drawFlatSolarNightShadowAndGreyline(
                context: context,
                size: size,
                subSolar: subSolar,
                toScreen: toFlatScreen
            )
        }

        // 5. Home QTH Indicator
        let homePt = toFlatScreen(lat: home.latitude, lon: home.longitude)
        context.fill(Path(ellipseIn: CGRect(x: homePt.x - 6, y: homePt.y - 6, width: 12, height: 12)), with: .color(Color.green))
        context.stroke(Path(ellipseIn: CGRect(x: homePt.x - 6, y: homePt.y - 6, width: 12, height: 12)), with: .color(Color.white), lineWidth: 2)

        // 6. Auroral Oval Overlay
        if showAuroralOval {
            drawFlatAuroralOval(context: context, toScreen: toFlatScreen)
        }

        // 7. Satellite Tracking
        if showSatelliteTracks {
            drawFlatSatelliteTelemetry(context: context, size: size, toScreen: toFlatScreen)
        }

        // 8. NOAA D-RAP Ionospheric Absorption Layer
        if showDRAPLayer {
            drawFlatDRAPLayer(context: context, toScreen: toFlatScreen)
        }

        // 9. APRS & High-Altitude Balloon Tracking
        if showBalloonTracks {
            drawFlatBalloonTelemetry(context: context, toScreen: toFlatScreen)
        }

        // 10. Great Circle Traffic Rays & Spot Markers
        if showTrafficArcs {
            drawFlatTrafficRaysAndMarkers(
                context: context,
                size: size,
                home: home,
                toScreen: toFlatScreen
            )
        }

        // 11. Subsolar (☀️) and Sublunar (🌙) Markers on Flat Map
        let sunPt = toFlatScreen(lat: subSolar.latitude, lon: subSolar.longitude)
        context.draw(Text("☀️").font(.system(size: 18)), at: sunPt, anchor: .center)

        let moonPt = toFlatScreen(lat: subLunar.latitude, lon: subLunar.longitude)
        context.draw(Text("🌙").font(.system(size: 14)), at: moonPt, anchor: .center)
        context.draw(
            Text("\(Int(subLunar.phasePercent * 100))%")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundColor(Color.cyan),
            at: CGPoint(x: moonPt.x, y: moonPt.y + 10),
            anchor: .center
        )
    }

    // MARK: - Flat Map Vector Greyline & Night Polygon

    private func drawFlatSolarNightShadowAndGreyline(
        context: GraphicsContext,
        size: CGSize,
        subSolar: SubSolarPosition,
        toScreen: (Double, Double) -> CGPoint
    ) {
        let decRad = subSolar.latitude * .pi / 180.0
        let sunLonRad = subSolar.longitude * .pi / 180.0
        let isSummerNorth = subSolar.latitude >= 0
        let step = 1.0

        // 1. Vector Night Polygon
        var nightPath = Path()
        let startLat = termLat(lonDeg: -180.0, decRad: decRad, sunLonRad: sunLonRad)
        nightPath.move(to: toScreen(startLat, -180.0))

        var lonDeg = -180.0
        while lonDeg <= 180.0 {
            let lat = termLat(lonDeg: lonDeg, decRad: decRad, sunLonRad: sunLonRad)
            nightPath.addLine(to: toScreen(lat, lonDeg))
            lonDeg += step
        }

        if isSummerNorth {
            // South pole is in darkness
            nightPath.addLine(to: CGPoint(x: size.width, y: size.height))
            nightPath.addLine(to: CGPoint(x: 0, y: size.height))
        } else {
            // North pole is in darkness
            nightPath.addLine(to: CGPoint(x: size.width, y: 0))
            nightPath.addLine(to: CGPoint(x: 0, y: 0))
        }
        nightPath.closeSubpath()

        let flatNightColor: Color
        switch currentTheme {
        case .shackNight:
            flatNightColor = Color(red: 0.02, green: 0.03, blue: 0.08).opacity(0.55)
        case .classicLight:
            flatNightColor = Color(red: 0.05, green: 0.08, blue: 0.16).opacity(0.40)
        case .nightVision:
            flatNightColor = Color(red: 0.05, green: 0.00, blue: 0.00).opacity(0.60)
        }
        context.fill(nightPath, with: .color(flatNightColor))

        // 2. Civil Twilight (-6°) Ribbon Band
        var civilBand = Path()
        civilBand.move(to: toScreen(startLat, -180.0))

        lonDeg = -180.0
        while lonDeg <= 180.0 {
            let lat = termLat(lonDeg: lonDeg, decRad: decRad, sunLonRad: sunLonRad)
            civilBand.addLine(to: toScreen(lat, lonDeg))
            lonDeg += step
        }

        lonDeg = 180.0
        while lonDeg >= -180.0 {
            let lat = twilightLat(elevationDeg: -6.0, lonDeg: lonDeg, decRad: decRad, sunLonRad: sunLonRad)
            civilBand.addLine(to: toScreen(lat, lonDeg))
            lonDeg -= step
        }
        civilBand.closeSubpath()
        context.fill(civilBand, with: .color(Color(red: 1.0, green: 0.72, blue: 0.20).opacity(0.18)))

        // 3. Glowing Golden Greyline Terminator Ribbon
        var ribbonPath = Path()
        ribbonPath.move(to: toScreen(startLat, -180.0))
        lonDeg = -180.0 + step
        while lonDeg <= 180.0 {
            let lat = termLat(lonDeg: lonDeg, decRad: decRad, sunLonRad: sunLonRad)
            ribbonPath.addLine(to: toScreen(lat, lonDeg))
            lonDeg += step
        }

        // Amber outer glow
        context.stroke(
            ribbonPath,
            with: .color(Color(red: 1.0, green: 0.75, blue: 0.20).opacity(0.35)),
            lineWidth: 8.0
        )
        // Golden core ribbon
        context.stroke(
            ribbonPath,
            with: .color(Color(red: 1.0, green: 0.85, blue: 0.32).opacity(0.85)),
            lineWidth: 2.4
        )
        // Bright filament center
        context.stroke(
            ribbonPath,
            with: .color(Color(red: 1.0, green: 0.96, blue: 0.70).opacity(0.95)),
            lineWidth: 1.0
        )
    }

    private func termLat(lonDeg: Double, decRad: Double, sunLonRad: Double) -> Double {
        let lonRad = lonDeg * .pi / 180.0
        let deltaLon = lonRad - sunLonRad
        if abs(tan(decRad)) < 1e-6 {
            return cos(deltaLon) > 0 ? -90.0 : 90.0
        }
        let termLatRad = atan(-cos(deltaLon) / tan(decRad))
        return termLatRad * 180.0 / .pi
    }

    private func twilightLat(elevationDeg: Double, lonDeg: Double, decRad: Double, sunLonRad: Double) -> Double {
        let lonRad = lonDeg * .pi / 180.0
        let deltaLon = lonRad - sunLonRad
        let sinH = sin(elevationDeg * .pi / 180.0)
        let A = sin(decRad)
        let B = cos(decRad) * cos(deltaLon)
        let R = sqrt(A * A + B * B)
        if R < 1e-6 { return 0.0 }
        if abs(sinH / R) <= 1.0 {
            let alpha = atan2(B, A)
            let phi1 = (asin(sinH / R) - alpha) * 180.0 / .pi
            var norm1 = phi1
            while norm1 > 180 { norm1 -= 360 }
            while norm1 < -180 { norm1 += 360 }

            let phi2 = (.pi - asin(sinH / R) - alpha) * 180.0 / .pi
            var norm2 = phi2
            while norm2 > 180 { norm2 -= 360 }
            while norm2 < -180 { norm2 += 360 }

            let termLatDeg = termLat(lonDeg: lonDeg, decRad: decRad, sunLonRad: sunLonRad)

            let valid1 = abs(norm1) <= 90.0
            let valid2 = abs(norm2) <= 90.0

            if valid1 && valid2 {
                return abs(norm1 - termLatDeg) < abs(norm2 - termLatDeg) ? norm1 : norm2
            } else if valid1 {
                return norm1
            } else if valid2 {
                return norm2
            } else {
                return termLatDeg > 0 ? 90.0 : -90.0
            }
        } else {
            return sinH > 0 ? (A >= 0 ? 90.0 : -90.0) : (A >= 0 ? -90.0 : 90.0)
        }
    }

    private func drawFlatTrafficRaysAndMarkers(
        context: GraphicsContext,
        size: CGSize,
        home: GeoCoordinate,
        toScreen: (Double, Double) -> CGPoint
    ) {
        for m in markers.prefix(40) {
            let targetPt = toScreen(m.coordinate.latitude, m.coordinate.longitude)
            let bandColor = WorldVectorGeography.bandColor(for: m.band)
            let ageSeconds = max(0, liveDate.timeIntervalSince(m.timestamp))

            let alpha: Double
            let isFresh: Bool
            if clusterSpotAging {
                if ageSeconds < 180 { alpha = 1.0; isFresh = ageSeconds < 60 }
                else if ageSeconds < 600 { alpha = 0.80; isFresh = false }
                else if ageSeconds < 1200 { alpha = 0.50; isFresh = false }
                else { alpha = 0.25; isFresh = false }
            } else {
                alpha = 0.85
                isFresh = false
            }

            let (isGreylineDuct, _) = SolarEphemeris.isPathInGreyline(from: home, to: m.coordinate, at: liveDate)

            // Great Circle Waypoints on Flat Map
            let waypoints = GeodesicMath.greatCircleWaypoints(from: home, to: m.coordinate, count: 20)
            if waypoints.count >= 2 {
                var rayPath = Path()
                var started = false
                var prevLon: Double?

                for wp in waypoints {
                    if let pl = prevLon, abs(wp.longitude - pl) > 180.0 {
                        // Anti-meridian crossing discontinuity
                        started = false
                    }
                    let pt = toScreen(wp.latitude, wp.longitude)
                    if !started {
                        rayPath.move(to: pt)
                        started = true
                    } else {
                        rayPath.addLine(to: pt)
                    }
                    prevLon = wp.longitude
                }

                if isGreylineDuct {
                    context.stroke(
                        rayPath,
                        with: .color(Color(red: 1.0, green: 0.78, blue: 0.22).opacity(alpha * 0.65)),
                        lineWidth: 3.5
                    )
                }

                context.stroke(
                    rayPath,
                    with: .color(bandColor.opacity(alpha * 0.80)),
                    lineWidth: 1.4
                )
            }

            // Spot Target Dot
            let markerRect = CGRect(x: targetPt.x - 3.5, y: targetPt.y - 3.5, width: 7, height: 7)
            context.fill(Path(ellipseIn: markerRect), with: .color(bandColor.opacity(alpha)))
            context.stroke(Path(ellipseIn: markerRect), with: .color(Color.white.opacity(alpha * 0.9)), lineWidth: 1.0)

            if isGreylineDuct {
                let ductR: CGFloat = 7.5 + 2.0 * sin(liveDate.timeIntervalSinceReferenceDate * 3.5)
                let ductRect = CGRect(x: targetPt.x - ductR, y: targetPt.y - ductR, width: ductR * 2, height: ductR * 2)
                context.stroke(Path(ellipseIn: ductRect), with: .color(Color(red: 1.0, green: 0.82, blue: 0.28).opacity(alpha * 0.85)), lineWidth: 1.2)
            } else if isFresh {
                let pulseR: CGFloat = 5.5 + 2.0 * sin(liveDate.timeIntervalSinceReferenceDate * 4.0)
                let pulseRect = CGRect(x: targetPt.x - pulseR, y: targetPt.y - pulseR, width: pulseR * 2, height: pulseR * 2)
                context.stroke(Path(ellipseIn: pulseRect), with: .color(bandColor.opacity(0.85)), lineWidth: 1.0)
            }
        }
    }

    // MARK: - Station Greyline Telemetry HUD

    private var stationGreylineHUD: some View {
        let solarStatus = SolarEphemeris.stationSolarStatus(for: homeCoordinate, at: liveDate)
        let isGreyline = solarStatus.isGreylineActive
        let ductPercent = Int(solarStatus.lowBandDuctingEfficiency * 100)

        let circleFill: Color = isGreyline
            ? Color(red: 1.0, green: 0.78, blue: 0.25).opacity(0.25)
            : (solarStatus.elevationDeg > 0 ? Color.yellow.opacity(0.20) : Color.indigo.opacity(0.20))

        let titleText: String = isGreyline ? "GREYLINE ACTIVE" : solarStatus.illumination.rawValue.uppercased()
        let titleColor: Color = isGreyline
            ? Color(red: 1.0, green: 0.82, blue: 0.30)
            : (currentTheme == .classicLight ? Color.primary : Color.white)

        let bgFill: Color = (currentTheme == .classicLight)
            ? Color.white.opacity(0.88)
            : Color(red: 0.06, green: 0.08, blue: 0.14).opacity(0.85)

        let strokeColor: Color = isGreyline
            ? Color(red: 1.0, green: 0.75, blue: 0.25).opacity(0.70)
            : (currentTheme == .classicLight ? Color.gray.opacity(0.30) : Color.white.opacity(0.15))

        let shadowColor: Color = isGreyline
            ? Color(red: 1.0, green: 0.75, blue: 0.20).opacity(0.35)
            : Color.black.opacity(0.25)

        return HStack(spacing: 8) {
            // Solar State Icon & Pulse Glow
            ZStack {
                Circle()
                    .fill(circleFill)
                    .frame(width: 26, height: 26)

                if isGreyline {
                    Text("🌅")
                        .font(.system(size: 13))
                } else if solarStatus.elevationDeg > 0 {
                    Text("☀️")
                        .font(.system(size: 13))
                } else {
                    Text("🌙")
                        .font(.system(size: 13))
                }
            }

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 5) {
                    Text(titleText)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(titleColor)

                    Text(String(format: "%+.1f°", solarStatus.elevationDeg))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.secondary)

                    if isGreyline {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.78, blue: 0.22))
                            .frame(width: 5, height: 5)
                    }
                }

                HStack(spacing: 6) {
                    Text(solarStatus.countdownText)
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.secondary)

                    if isGreyline {
                        Text("•")
                            .font(.system(size: 7))
                            .foregroundColor(Color.secondary)
                        Text("Duct \(ductPercent)% (160/80m)")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.25))
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(bgFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(strokeColor, lineWidth: isGreyline ? 1.2 : 0.8)
                )
                .shadow(
                    color: shadowColor,
                    radius: isGreyline ? 6 : 4,
                    x: 0,
                    y: 2
                )
        )
    }

    // MARK: - Auroral Oval Drawing

    private func drawAuroralOval(
        context: GraphicsContext,
        center: CGPoint,
        mapRadius: CGFloat,
        toScreen: (Double, Double) -> CGPoint
    ) {
        let b = auroraEngine.boundary
        let rings = [b.northernOuterRing, b.northernInnerRing, b.southernOuterRing, b.southernInnerRing]

        for ring in rings {
            guard ring.count >= 2 else { continue }
            var p = Path()
            var started = false

            for pt in ring {
                let screenPt = toScreen(pt.latitude, pt.longitude)
                let dist = hypot(screenPt.x - center.x, screenPt.y - center.y)
                if dist <= mapRadius {
                    if !started {
                        p.move(to: screenPt)
                        started = true
                    } else {
                        p.addLine(to: screenPt)
                    }
                } else {
                    started = false
                }
            }

            let color = auroraEngine.isStormActive
                ? Color(red: 1.0, green: 0.2, blue: 0.8).opacity(0.65)
                : Color(red: 0.1, green: 0.95, blue: 0.45).opacity(0.50)
            context.stroke(p, with: .color(color), lineWidth: auroraEngine.isStormActive ? 2.5 : 1.5)
        }
    }

    private func drawFlatAuroralOval(
        context: GraphicsContext,
        toScreen: (Double, Double) -> CGPoint
    ) {
        let b = auroraEngine.boundary
        let rings = [b.northernOuterRing, b.northernInnerRing, b.southernOuterRing, b.southernInnerRing]

        for ring in rings {
            guard ring.count >= 2 else { continue }
            var p = Path()
            var started = false
            for pt in ring {
                let screenPt = toScreen(pt.latitude, pt.longitude)
                if !started {
                    p.move(to: screenPt)
                    started = true
                } else {
                    p.addLine(to: screenPt)
                }
            }
            let color = auroraEngine.isStormActive
                ? Color(red: 1.0, green: 0.2, blue: 0.8).opacity(0.65)
                : Color(red: 0.1, green: 0.95, blue: 0.45).opacity(0.50)
            context.stroke(p, with: .color(color), lineWidth: auroraEngine.isStormActive ? 2.0 : 1.2)
        }
    }

    // MARK: - Satellite Orbit & Footprint Drawing

    private func drawSatelliteTelemetry(
        context: GraphicsContext,
        center: CGPoint,
        mapRadius: CGFloat,
        toScreen: (Double, Double) -> CGPoint
    ) {
        guard let sat = satEngine.selectedSatellite,
              let telem = satEngine.currentTelemetry else { return }

        // 1. Ground Track
        let waypoints = satEngine.groundTrackWaypoints
        if waypoints.count >= 2 {
            var path = Path()
            var started = false
            for pt in waypoints {
                let screenPt = toScreen(pt.latitude, pt.longitude)
                let dist = hypot(screenPt.x - center.x, screenPt.y - center.y)
                if dist <= mapRadius {
                    if !started {
                        path.move(to: screenPt)
                        started = true
                    } else {
                        path.addLine(to: screenPt)
                    }
                } else {
                    started = false
                }
            }
            context.stroke(
                path,
                with: .color(Color(red: 0.2, green: 0.75, blue: 1.0).opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
            )
        }

        // 2. Radio Footprint Circle
        let footprintCoords = generateFootprintRing(centerCoord: telem.coordinate, radiusKm: telem.footprintRadiusKm)
        if footprintCoords.count >= 3 {
            var footPath = Path()
            var started = false
            for pt in footprintCoords {
                let screenPt = toScreen(pt.latitude, pt.longitude)
                let dist = hypot(screenPt.x - center.x, screenPt.y - center.y)
                if dist <= mapRadius {
                    if !started {
                        footPath.move(to: screenPt)
                        started = true
                    } else {
                        footPath.addLine(to: screenPt)
                    }
                } else {
                    started = false
                }
            }
            let footColor = telem.isLineOfSight
                ? Color.green.opacity(0.40)
                : Color.cyan.opacity(0.25)
            context.stroke(footPath, with: .color(footColor), lineWidth: telem.isLineOfSight ? 2.0 : 1.0)
        }

        // 3. Sub-Satellite Marker & Label
        let satPt = toScreen(telem.coordinate.latitude, telem.coordinate.longitude)
        let satDist = hypot(satPt.x - center.x, satPt.y - center.y)
        if satDist <= mapRadius {
            let satDot = Path(ellipseIn: CGRect(x: satPt.x - 5, y: satPt.y - 5, width: 10, height: 10))
            context.fill(satDot, with: .color(Color.yellow))
            context.stroke(satDot, with: .color(Color.white), lineWidth: 1.5)

            context.draw(
                Text("🛰 \(sat.id)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.yellow),
                at: CGPoint(x: satPt.x, y: satPt.y - 10),
                anchor: .center
            )
        }
    }

    private func drawFlatSatelliteTelemetry(
        context: GraphicsContext,
        size: CGSize,
        toScreen: (Double, Double) -> CGPoint
    ) {
        guard let sat = satEngine.selectedSatellite,
              let telem = satEngine.currentTelemetry else { return }

        // Ground track
        let waypoints = satEngine.groundTrackWaypoints
        if waypoints.count >= 2 {
            var path = Path()
            var started = false
            for pt in waypoints {
                let screenPt = toScreen(pt.latitude, pt.longitude)
                if !started {
                    path.move(to: screenPt)
                    started = true
                } else {
                    path.addLine(to: screenPt)
                }
            }
            context.stroke(
                path,
                with: .color(Color(red: 0.2, green: 0.75, blue: 1.0).opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
            )
        }

        // Sub-satellite marker
        let satPt = toScreen(telem.coordinate.latitude, telem.coordinate.longitude)
        let satDot = Path(ellipseIn: CGRect(x: satPt.x - 5, y: satPt.y - 5, width: 10, height: 10))
        context.fill(satDot, with: .color(Color.yellow))
        context.stroke(satDot, with: .color(Color.white), lineWidth: 1.5)

        context.draw(
            Text("🛰 \(sat.id)")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundColor(Color.yellow),
            at: CGPoint(x: satPt.x, y: satPt.y - 10),
            anchor: .center
        )
    }

    private func generateFootprintRing(centerCoord: GeoCoordinate, radiusKm: Double) -> [GeoCoordinate] {
        var ring: [GeoCoordinate] = []
        let angularDist = radiusKm / GeodesicMath.earthRadiusKm
        let lat1 = centerCoord.latitude * .pi / 180.0
        let lon1 = centerCoord.longitude * .pi / 180.0

        for b in stride(from: 0.0, through: 360.0, by: 15.0) {
            let brng = b * .pi / 180.0
            let lat2 = asin(sin(lat1) * cos(angularDist) + cos(lat1) * sin(angularDist) * cos(brng))
            let lon2 = lon1 + atan2(sin(brng) * sin(angularDist) * cos(lat1), cos(angularDist) - sin(lat1) * sin(lat2))
            ring.append(GeoCoordinate(latitude: lat2 * 180.0 / .pi, longitude: lon2 * 180.0 / .pi))
        }
        return ring
    }

    // MARK: - NOAA D-RAP Ionospheric Absorption Overlay

    private func drawDRAPLayer(
        context: GraphicsContext,
        center: CGPoint,
        mapRadius: CGFloat,
        toScreen: (Double, Double) -> CGPoint
    ) {
        let snap = drapEngine.snapshot
        guard !snap.affectedPoints.isEmpty else { return }

        for pt in snap.affectedPoints {
            let screenPt = toScreen(pt.coordinate.latitude, pt.coordinate.longitude)
            let dist = hypot(screenPt.x - center.x, screenPt.y - center.y)
            guard dist <= mapRadius else { continue }

            let intensity = min(1.0, pt.absorbedFrequencyMHz / 20.0)
            let color = Color.red.opacity(0.18 + intensity * 0.25)
            let disc = Path(ellipseIn: CGRect(x: screenPt.x - 14, y: screenPt.y - 14, width: 28, height: 28))
            context.fill(disc, with: .color(color))
        }
    }

    private func drawFlatDRAPLayer(
        context: GraphicsContext,
        toScreen: (Double, Double) -> CGPoint
    ) {
        let snap = drapEngine.snapshot
        guard !snap.affectedPoints.isEmpty else { return }

        for pt in snap.affectedPoints {
            let screenPt = toScreen(pt.coordinate.latitude, pt.coordinate.longitude)
            let intensity = min(1.0, pt.absorbedFrequencyMHz / 20.0)
            let color = Color.red.opacity(0.18 + intensity * 0.25)
            let disc = Path(ellipseIn: CGRect(x: screenPt.x - 12, y: screenPt.y - 12, width: 24, height: 24))
            context.fill(disc, with: .color(color))
        }
    }

    // MARK: - APRS High-Altitude Balloon Tracking

    private func drawBalloonTelemetry(
        context: GraphicsContext,
        center: CGPoint,
        mapRadius: CGFloat,
        toScreen: (Double, Double) -> CGPoint
    ) {
        for b in balloonEngine.balloons {
            if b.flightTrail.count >= 2 {
                var path = Path()
                var started = false
                for pt in b.flightTrail {
                    let screenPt = toScreen(pt.latitude, pt.longitude)
                    let dist = hypot(screenPt.x - center.x, screenPt.y - center.y)
                    if dist <= mapRadius {
                        if !started {
                            path.move(to: screenPt)
                            started = true
                        } else {
                            path.addLine(to: screenPt)
                        }
                    } else {
                        started = false
                    }
                }
                context.stroke(
                    path,
                    with: .color(Color.yellow.opacity(0.65)),
                    style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])
                )
            }

            let bPt = toScreen(b.coordinate.latitude, b.coordinate.longitude)
            let dist = hypot(bPt.x - center.x, bPt.y - center.y)
            if dist <= mapRadius {
                let balloonDisc = Path(ellipseIn: CGRect(x: bPt.x - 4, y: bPt.y - 4, width: 8, height: 8))
                context.fill(balloonDisc, with: .color(Color.white))
                context.stroke(balloonDisc, with: .color(Color.orange), lineWidth: 2)

                context.draw(
                    Text("🎈 \(b.callsign) (\(Int(b.altitudeMeters))m)")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.orange),
                    at: CGPoint(x: bPt.x, y: bPt.y - 9),
                    anchor: .center
                )
            }
        }
    }

    private func drawFlatBalloonTelemetry(
        context: GraphicsContext,
        toScreen: (Double, Double) -> CGPoint
    ) {
        for b in balloonEngine.balloons {
            if b.flightTrail.count >= 2 {
                var path = Path()
                var started = false
                for pt in b.flightTrail {
                    let screenPt = toScreen(pt.latitude, pt.longitude)
                    if !started {
                        path.move(to: screenPt)
                        started = true
                    } else {
                        path.addLine(to: screenPt)
                    }
                }
                context.stroke(
                    path,
                    with: .color(Color.yellow.opacity(0.65)),
                    style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])
                )
            }

            let bPt = toScreen(b.coordinate.latitude, b.coordinate.longitude)
            let balloonDisc = Path(ellipseIn: CGRect(x: bPt.x - 4, y: bPt.y - 4, width: 8, height: 8))
            context.fill(balloonDisc, with: .color(Color.white))
            context.stroke(balloonDisc, with: .color(Color.orange), lineWidth: 2)

            context.draw(
                Text("🎈 \(b.callsign) (\(Int(b.altitudeMeters))m)")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.orange),
                at: CGPoint(x: bPt.x, y: bPt.y - 9),
                anchor: .center
            )
        }
    }
}

