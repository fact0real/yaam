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
            let terminatorPoints = SolarEphemeris.terminatorCoordinates(at: liveDate, stepDegrees: 2.0)

            ZStack(alignment: .bottomLeading) {
                // Outer Canvas Background
                Color(red: 0.96, green: 0.97, blue: 0.98)

                Canvas { context, canvasSize in
                    if mode == .azimuthal {
                        drawAzimuthalMap(
                            context: context,
                            size: canvasSize,
                            home: homeCoordinate,
                            subSolar: subSolar,
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

                // Live UTC GMT Clock Watermark (matching reference diagram)
                Text(formattedGMT(liveDate))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.15, green: 0.20, blue: 0.25))
                    .padding(.leading, 18)
                    .padding(.bottom, 14)
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

    // MARK: - Azimuthal Equidistant Map Drawing (Matching NS6T Reference Image)

    private func drawAzimuthalMap(
        context: GraphicsContext,
        size: CGSize,
        home: GeoCoordinate,
        subSolar: SubSolarPosition,
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

        // 1. Fill Ocean Base Disc (NS6T Sky Blue)
        let mapDisc = Path(ellipseIn: CGRect(x: center.x - mapRadius, y: center.y - mapRadius, width: mapRadius * 2, height: mapRadius * 2))
        context.fill(mapDisc, with: .color(WorldVectorGeography.colorOcean))
        context.stroke(mapDisc, with: .color(Color(red: 0.15, green: 0.25, blue: 0.35)), lineWidth: 1.5)

        // 2. Concentric Distance Range Rings (5,000 km, 10,000 km, 15,000 km, 20,000 km)
        let distanceSteps: [Double] = [5000.0, 10000.0, 15000.0, 20000.0].filter { $0 <= maxDistKm }
        for dist in distanceSteps {
            let r = CGFloat((dist / maxDistKm) * Double(mapRadius))
            let ringPath = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            context.stroke(ringPath, with: .color(Color.white.opacity(0.35)), lineWidth: 0.8)
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
                    with: .color(line.isMajor ? WorldVectorGeography.colorGraticuleMajor : WorldVectorGeography.colorGraticule),
                    lineWidth: line.isMajor ? 1.0 : 0.6
                )
            }
        }

        // 4. High-Resolution Crisp White Landmass Polygons with Dark Navy Coastlines
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
                context.fill(path, with: .color(WorldVectorGeography.colorLand))
                context.stroke(path, with: .color(WorldVectorGeography.colorLandStroke), lineWidth: 1.0)
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
            context.stroke(path, with: .color(WorldVectorGeography.colorBorder), style: StrokeStyle(lineWidth: 0.6, dash: [3, 2]))
        }

        // 6. Day / Night Solar Greyline Terminator Dark Shadow
        if showDayNightShadow {
            drawAzimuthalSolarNightShadow(
                context: context,
                center: center,
                mapRadius: mapRadius,
                subSolar: subSolar,
                toScreen: azimuthalPoint
            )
        }

        // 7. Subsolar Point Sun Symbol ☀️
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

        // 8. Country Labels & Major DXCC Entities
        if showCountryLabels {
            for country in WorldVectorGeography.countries {
                let pt = azimuthalPoint(lat: country.center.latitude, lon: country.center.longitude)
                let dist = hypot(pt.x - center.x, pt.y - center.y)
                if dist <= mapRadius - 12.0 {
                    let labelText = "\(country.name)\n\(country.primaryPrefix)"
                    context.draw(
                        Text(labelText)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Color(red: 0.12, green: 0.16, blue: 0.22)),
                        at: CGPoint(x: pt.x + country.labelOffset.x, y: pt.y + country.labelOffset.y),
                        anchor: .center
                    )
                }
            }
        }

        // 9. Great Circle Direct Traffic Arcs & Contacts
        if showTrafficArcs {
            for m in markers.prefix(35) {
                let targetPt = azimuthalPoint(lat: m.coordinate.latitude, lon: m.coordinate.longitude)
                let dist = hypot(targetPt.x - center.x, targetPt.y - center.y)
                if dist <= mapRadius {
                    var beam = Path()
                    beam.move(to: center)
                    beam.addLine(to: targetPt)
                    context.stroke(beam, with: .color(Color.yellow.opacity(0.80)), lineWidth: 1.6)

                    context.fill(
                        Path(ellipseIn: CGRect(x: targetPt.x - 3.5, y: targetPt.y - 3.5, width: 7, height: 7)),
                        with: .color(Color.red)
                    )
                }
            }
        }

        // 10. Active Rotator Beam Heading Arrow (NS6T Red Heading Arrow)
        let beamAzimuth = rotatorService.currentAzimuth
        let beamRad = (beamAzimuth - 90.0) * .pi / 180.0
        let beamLen = Double(mapRadius) * 0.85
        let arrowEnd = CGPoint(
            x: center.x + CGFloat(beamLen * cos(beamRad)),
            y: center.y + CGFloat(beamLen * sin(beamRad))
        )

        var beamLine = Path()
        beamLine.move(to: center)
        beamLine.addLine(to: arrowEnd)
        context.stroke(beamLine, with: .color(Color.red), lineWidth: 2.4)

        // Arrowhead at the tip
        let headLen: CGFloat = 14.0
        let headAngle: CGFloat = 0.40
        let arrowPt1 = CGPoint(
            x: arrowEnd.x - headLen * CGFloat(cos(beamRad - Double(headAngle))),
            y: arrowEnd.y - headLen * CGFloat(sin(beamRad - Double(headAngle)))
        )
        let arrowPt2 = CGPoint(
            x: arrowEnd.x - headLen * CGFloat(cos(beamRad + Double(headAngle))),
            y: arrowEnd.y - headLen * CGFloat(sin(beamRad + Double(headAngle)))
        )
        var arrowHead = Path()
        arrowHead.move(to: arrowEnd)
        arrowHead.addLine(to: arrowPt1)
        arrowHead.addLine(to: arrowPt2)
        arrowHead.closeSubpath()
        context.fill(arrowHead, with: .color(Color.red))

        // 11. Center Station Callout Badge (NS6T Authentic Callout Box)
        drawCenterStationCalloutBadge(
            context: context,
            center: center,
            home: home
        )

        // 12. Calibrated 360° Compass Dial Bezel
        drawCompassDial(
            context: context,
            center: center,
            innerRadius: mapRadius,
            outerRadius: outerDialRadius
        )
    }

    // MARK: - Center Station Callout Badge (Matching NS6T Reference)

    private func drawCenterStationCalloutBadge(
        context: GraphicsContext,
        center: CGPoint,
        home: GeoCoordinate
    ) {
        let badgeWidth: CGFloat = 110.0
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
            with: .color(Color.black.opacity(0.25))
        )

        // Gradient Background (White to Light Cyan-Blue)
        context.fill(
            Path(roundedRect: badgeRect, cornerRadius: 5),
            with: .color(Color(red: 0.93, green: 0.96, blue: 1.00))
        )
        context.stroke(
            Path(roundedRect: badgeRect, cornerRadius: 5),
            with: .color(Color(red: 0.20, green: 0.40, blue: 0.70)),
            lineWidth: 1.2
        )

        // Badge Callout Arrow downwards
        var pointer = Path()
        pointer.move(to: CGPoint(x: center.x - 6, y: badgeRect.maxY))
        pointer.addLine(to: CGPoint(x: center.x, y: badgeRect.maxY + 7))
        pointer.addLine(to: CGPoint(x: center.x + 6, y: badgeRect.maxY))
        pointer.closeSubpath()
        context.fill(pointer, with: .color(Color(red: 0.93, green: 0.96, blue: 1.00)))
        context.stroke(pointer, with: .color(Color(red: 0.20, green: 0.40, blue: 0.70)), lineWidth: 1.2)

        // Callsign Text
        let stationCall = stationCallsign.isEmpty ? "EP2AES" : stationCallsign
        context.draw(
            Text(stationCall)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(red: 0.05, green: 0.10, blue: 0.25)),
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
                .foregroundColor(Color(red: 0.25, green: 0.35, blue: 0.45)),
            at: CGPoint(x: center.x, y: badgeRect.minY + 26),
            anchor: .center
        )

        context.draw(
            Text("Center Origin")
                .font(.system(size: 7.5, weight: .regular))
                .foregroundColor(Color.secondary),
            at: CGPoint(x: center.x, y: badgeRect.minY + 37),
            anchor: .center
        )

        // Center Pin Dot
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)),
            with: .color(Color.red)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)),
            with: .color(Color.white),
            lineWidth: 1.5
        )
    }

    // MARK: - 360° Calibrated Compass Dial Bezel

    private func drawCompassDial(
        context: GraphicsContext,
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) {
        // Outer Dial Background Ring
        let bezelRing = Path { p in
            p.addEllipse(in: CGRect(x: center.x - outerRadius, y: center.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2))
        }
        context.stroke(bezelRing, with: .color(Color(red: 0.20, green: 0.30, blue: 0.40)), lineWidth: 1.5)

        // Inner Divider Line
        let innerRing = Path { p in
            p.addEllipse(in: CGRect(x: center.x - innerRadius, y: center.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2))
        }
        context.stroke(innerRing, with: .color(Color(red: 0.20, green: 0.30, blue: 0.40)), lineWidth: 1.0)

        // 360 Degree Ticks & Labels
        for deg in 0..<360 {
            let rad = (Double(deg) - 90.0) * .pi / 180.0
            let isMajor = deg % 10 == 0
            let isMedium = deg % 5 == 0

            let tickLen: CGFloat = isMajor ? 10.0 : (isMedium ? 6.0 : 3.0)
            let pOuter = CGPoint(x: center.x + CGFloat(Double(outerRadius) * cos(rad)), y: center.y + CGFloat(Double(outerRadius) * sin(rad)))
            let pInner = CGPoint(x: center.x + CGFloat(Double(outerRadius - tickLen) * cos(rad)), y: center.y + CGFloat(Double(outerRadius - tickLen) * sin(rad)))

            var tickPath = Path()
            tickPath.move(to: pInner)
            tickPath.addLine(to: pOuter)
            context.stroke(tickPath, with: .color(Color(red: 0.15, green: 0.20, blue: 0.30)), lineWidth: isMajor ? 1.4 : 0.7)

            if isMajor {
                let textRadius = outerRadius + 14.0
                let labelPt = CGPoint(x: center.x + CGFloat(Double(textRadius) * cos(rad)), y: center.y + CGFloat(Double(textRadius) * sin(rad)))
                context.draw(
                    Text("\(deg)°")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25)),
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
                        let alpha = sunElev < -6.0 ? 0.44 : 0.22
                        context.fill(
                            Path(ellipseIn: CGRect(x: pt.x - cellSize / 2.0, y: pt.y - cellSize / 2.0, width: cellSize, height: cellSize)),
                            with: .color(Color(red: 0.05, green: 0.08, blue: 0.14).opacity(alpha))
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
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(WorldVectorGeography.colorOcean))

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
                context.fill(path, with: .color(WorldVectorGeography.colorLand))
                context.stroke(path, with: .color(WorldVectorGeography.colorLandStroke), lineWidth: 0.9)
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
