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
    public var azimuthalRangeKm: Double
    public var stationCallsign: String
    public var onSelectMarker: (Globe3DMarker) -> Void
    public var onSelectGrid: (String) -> Void

    @ObservedObject private var rotatorService = RotatorService.shared
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
                            terminator: terminatorPoints
                        )
                    }
                }
                .drawingGroup()

                // Live UTC GMT Clock & Station Profile Watermark
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

            // Pulsing Ring for Fresh (< 60s) Spots
            if isFresh {
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

        let badgeBg: Color
        let badgeStroke: Color
        let callColor: Color
        let subColor: Color

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
            Text("Center Origin")
                .font(.system(size: 7.5, weight: .regular))
                .foregroundColor(subColor.opacity(0.8)),
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

    // MARK: - Solar Night Shadow Polygon

    private func drawAzimuthalSolarNightShadow(
        context: GraphicsContext,
        center: CGPoint,
        mapRadius: CGFloat,
        subSolar: SubSolarPosition,
        toScreen: (Double, Double) -> CGPoint
    ) {
        let sampleStep = 8.0
        for lat in stride(from: -85.0, through: 85.0, by: sampleStep) {
            for lon in stride(from: -180.0, through: 180.0, by: sampleStep) {
                let coord = GeoCoordinate(latitude: lat, longitude: lon)
                let sunElev = SolarEphemeris.solarElevation(for: coord, at: liveDate)
                if sunElev < 0 { // In night / twilight zone
                    let pt = toScreen(lat, lon)
                    let dist = hypot(pt.x - center.x, pt.y - center.y)
                    if dist <= mapRadius {
                        let cellSize = CGFloat((sampleStep / 180.0) * Double(mapRadius) * 1.5)
                        // Realistic Civil / Nautical / Astronomical twilight gradation
                        let alpha: Double
                        if sunElev >= -6.0 {
                            alpha = 0.20 // Civil Twilight
                        } else if sunElev >= -12.0 {
                            alpha = 0.35 // Nautical Twilight
                        } else {
                            alpha = 0.48 // Astronomical Night
                        }

                        let shadowColor: Color
                        switch currentTheme {
                        case .shackNight:
                            shadowColor = Color(red: 0.02, green: 0.03, blue: 0.06).opacity(alpha)
                        case .classicLight:
                            shadowColor = Color(red: 0.05, green: 0.08, blue: 0.14).opacity(alpha)
                        case .nightVision:
                            shadowColor = Color(red: 0.04, green: 0.00, blue: 0.00).opacity(alpha)
                        }

                        context.fill(
                            Path(ellipseIn: CGRect(x: pt.x - cellSize / 2.0, y: pt.y - cellSize / 2.0, width: cellSize, height: cellSize)),
                            with: .color(shadowColor)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Equirectangular 2D Map (Flat GridTracker)

    private func drawEquirectangularMap(
        context: GraphicsContext,
        size: CGSize,
        home: GeoCoordinate,
        subSolar: SubSolarPosition,
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

        // 4. Day / Night Solar Terminator Shadow
        if showDayNightShadow {
            for lat in stride(from: -85.0, through: 85.0, by: 10.0) {
                for lon in stride(from: -180.0, through: 180.0, by: 10.0) {
                    let coord = GeoCoordinate(latitude: lat, longitude: lon)
                    let elev = SolarEphemeris.solarElevation(for: coord, at: liveDate)
                    if elev < 0 {
                        let pt = toFlatScreen(lat: lat, lon: lon)
                        let w = size.width / 36.0
                        let h = size.height / 18.0
                        let alpha = elev < -6.0 ? 0.40 : 0.20
                        context.fill(
                            Path(CGRect(x: pt.x - w / 2, y: pt.y - h / 2, width: w, height: h)),
                            with: .color(Color(red: 0.05, green: 0.08, blue: 0.15).opacity(alpha))
                        )
                    }
                }
            }
        }

        // 5. Home QTH Indicator
        let homePt = toFlatScreen(lat: home.latitude, lon: home.longitude)
        context.fill(Path(ellipseIn: CGRect(x: homePt.x - 6, y: homePt.y - 6, width: 12, height: 12)), with: .color(Color.green))
        context.stroke(Path(ellipseIn: CGRect(x: homePt.x - 6, y: homePt.y - 6, width: 12, height: 12)), with: .color(Color.white), lineWidth: 2)
    }
}
