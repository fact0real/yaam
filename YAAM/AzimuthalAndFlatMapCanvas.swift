//
//  AzimuthalAndFlatMapCanvas.swift
//  YAAM
//
//  High-Performance 2D Vector Canvas for Azimuthal Equidistant & GridTracker Maps.
//  Includes precise Vector Country Boundaries, Country Flags & Labels, Range Zoom,
//  and Decluttered Smart Station Badges.
//

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
    public var onSelectMarker: (Globe3DMarker) -> Void
    public var onSelectGrid: (String) -> Void

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
        azimuthalRangeKm: Double = 8000.0,
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
        self.onSelectMarker = onSelectMarker
        self.onSelectGrid = onSelectGrid
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let subSolar = SolarEphemeris.calculate(at: Date())
            let terminatorPoints = SolarEphemeris.terminatorCoordinates(at: Date(), stepDegrees: 3.0)

            ZStack {
                // Base Background
                Color(red: 0.04, green: 0.07, blue: 0.13)

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

                // Interactive Smart Pins Overlay (Decluttered & Distinct)
                pinsOverlay(size: size)

                // Map Compass & Legend Watermark
                mapWatermark(size: size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleCanvasTap(location: location, size: size)
            }
        }
    }

    private func handleCanvasTap(location: CGPoint, size: CGSize) {
        if mode == .gridTracker {
            let lon = (location.x / size.width) * 360.0 - 180.0
            let lat = 90.0 - (location.y / size.height) * 180.0
            let grid4 = MaidenheadGridEngine.locator(from: GeoCoordinate(latitude: lat, longitude: lon))
            onSelectGrid(grid4)
        }
    }

    // MARK: - Equirectangular & GridTracker Drawing

    private func drawEquirectangularMap(
        context: GraphicsContext,
        size: CGSize,
        home: GeoCoordinate,
        subSolar: SubSolarPosition,
        terminator: [GeoCoordinate]
    ) {
        let w = size.width
        let h = size.height

        func screenPoint(lat: Double, lon: Double) -> CGPoint {
            let x = (lon + 180.0) / 360.0 * w
            let y = (90.0 - lat) / 180.0 * h
            return CGPoint(x: x, y: y)
        }

        // 1. Draw GridTracker Maidenhead Colored Tiles
        if showGridLines {
            drawMaidenheadGridTiles(context: context, size: size, toScreen: screenPoint)
        }

        // 2. Draw High-Precision Country Boundaries
        drawVectorCountriesEquirectangular(context: context, toScreen: screenPoint)

        // 3. Solar Terminator & Night Shading Overlay
        if showDayNightShadow {
            drawSolarTerminatorShade(context: context, size: size, subSolar: subSolar, terminator: terminator, toScreen: screenPoint)
        }

        // 4. Draw Traffic Arcs
        if showTrafficArcs {
            drawGreatCircleTrafficArcs(context: context, home: home, toScreen: screenPoint)
        }

        // 5. Country Names & Flags
        if showCountryLabels {
            drawCountryLabelsEquirectangular(context: context, toScreen: screenPoint)
        }

        // 6. Home Station Beacon Pulse
        let homePt = screenPoint(lat: home.latitude, lon: home.longitude)
        context.fill(
            Path(ellipseIn: CGRect(x: homePt.x - 7, y: homePt.y - 7, width: 14, height: 14)),
            with: .color(.green.opacity(0.85))
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: homePt.x - 12, y: homePt.y - 12, width: 24, height: 24)),
            with: .color(.green.opacity(0.5)),
            lineWidth: 1.5
        )

        // 7. Sun Position Pin
        let sunPt = screenPoint(lat: subSolar.latitude, lon: subSolar.longitude)
        context.fill(
            Path(ellipseIn: CGRect(x: sunPt.x - 8, y: sunPt.y - 8, width: 16, height: 16)),
            with: .color(.yellow.opacity(0.85))
        )
        context.draw(Text("☀️").font(.system(size: 14)), at: sunPt, anchor: .center)
    }

    // MARK: - Azimuthal Equidistant Drawing (Antenna Beam Heading)

    private func drawAzimuthalMap(
        context: GraphicsContext,
        size: CGSize,
        home: GeoCoordinate,
        subSolar: SubSolarPosition,
        terminator: [GeoCoordinate]
    ) {
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let maxRadius = min(size.width, size.height) / 2.0 - 24.0
        let maxDistKm: Double = max(3000.0, azimuthalRangeKm)

        func azimuthalPoint(lat: Double, lon: Double) -> CGPoint {
            let target = GeoCoordinate(latitude: lat, longitude: lon)
            let distKm = GeodesicMath.distanceKm(from: home, to: target)
            let bearingDeg = GeodesicMath.initialBearing(from: home, to: target)
            let bearingRad = (bearingDeg - 90.0) * .pi / 180.0

            let r = (distKm / maxDistKm) * Double(maxRadius)
            let x = center.x + CGFloat(r * cos(bearingRad))
            let y = center.y + CGFloat(r * sin(bearingRad))
            return CGPoint(x: x, y: y)
        }

        // 1. Concentric Distance Range Rings
        let rangeSteps = [maxDistKm * 0.25, maxDistKm * 0.50, maxDistKm * 0.75, maxDistKm]
        for dist in rangeSteps {
            let r = CGFloat((dist / maxDistKm) * Double(maxRadius))
            let ringPath = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            context.stroke(ringPath, with: .color(.cyan.opacity(0.20)), lineWidth: 1)

            let labelPt = CGPoint(x: center.x + 4, y: center.y - r + 8)
            context.draw(
                Text("\(Int(dist)) km").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.cyan.opacity(0.65)),
                at: labelPt,
                anchor: .leading
            )
        }

        // 2. Radial Beam Heading Degree Lines (Every 30°)
        for deg in stride(from: 0, to: 360, by: 30) {
            let rad = (Double(deg) - 90.0) * .pi / 180.0
            let pEdge = CGPoint(
                x: center.x + CGFloat(Double(maxRadius) * cos(rad)),
                y: center.y + CGFloat(Double(maxRadius) * sin(rad))
            )
            var line = Path()
            line.move(to: center)
            line.addLine(to: pEdge)
            context.stroke(line, with: .color(.cyan.opacity(0.12)), lineWidth: 1)

            let cardinal = GeodesicMath.compassCardinal(for: Double(deg))
            let labelPt = CGPoint(
                x: center.x + CGFloat(Double(maxRadius + 14) * cos(rad)),
                y: center.y + CGFloat(Double(maxRadius + 14) * sin(rad))
            )
            context.draw(
                Text("\(deg)° \(cardinal)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.cyan.opacity(0.85)),
                at: labelPt,
                anchor: .center
            )
        }

        // 3. Draw High-Precision Country Outlines in Azimuthal Projection
        drawVectorCountriesAzimuthal(context: context, toScreen: azimuthalPoint, center: center, maxRadius: maxRadius)

        // 4. Country Names & Flags in Azimuthal
        if showCountryLabels {
            drawCountryLabelsAzimuthal(context: context, toScreen: azimuthalPoint, center: center, maxRadius: maxRadius)
        }

        // 5. Great Circle Solar Terminator Curve
        if showDayNightShadow {
            var termPath = Path()
            var started = false
            for pt in terminator {
                let screenPt = azimuthalPoint(lat: pt.latitude, lon: pt.longitude)
                let distFromCenter = hypot(screenPt.x - center.x, screenPt.y - center.y)
                if distFromCenter <= maxRadius + 20 {
                    if !started {
                        termPath.move(to: screenPt)
                        started = true
                    } else {
                        termPath.addLine(to: screenPt)
                    }
                }
            }
            context.stroke(termPath, with: .color(.orange.opacity(0.75)), lineWidth: 1.8)
        }

        // 6. Direct Radial Beam Lines to DX Stations
        if showTrafficArcs {
            for m in markers.prefix(30) {
                let targetPt = azimuthalPoint(lat: m.coordinate.latitude, lon: m.coordinate.longitude)
                let distFromCenter = hypot(targetPt.x - center.x, targetPt.y - center.y)
                if distFromCenter <= maxRadius + 30 {
                    var beam = Path()
                    beam.move(to: center)
                    beam.addLine(to: targetPt)
                    context.stroke(beam, with: .color(colorForBand(m.band).opacity(0.65)), lineWidth: 1.5)
                }
            }
        }

        // 7. Center Home Antenna Beacon
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)),
            with: .color(.green)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - 13, y: center.y - 13, width: 26, height: 26)),
            with: .color(.green.opacity(0.6)),
            lineWidth: 2
        )
    }

    // MARK: - Country Geometry & Labels Drawing

    private func drawVectorCountriesEquirectangular(context: GraphicsContext, toScreen: (Double, Double) -> CGPoint) {
        for poly in WorldVectorGeography.countryBoundaries {
            guard poly.coordinates.count >= 3 else { continue }
            var path = Path()
            path.move(to: toScreen(poly.coordinates[0].latitude, poly.coordinates[0].longitude))
            for pt in poly.coordinates.dropFirst() {
                path.addLine(to: toScreen(pt.latitude, pt.longitude))
            }
            path.closeSubpath()
            context.fill(path, with: .color(Color(red: 0.12, green: 0.22, blue: 0.26).opacity(0.6)))
            context.stroke(path, with: .color(Color(red: 0.28, green: 0.70, blue: 0.85).opacity(0.75)), lineWidth: 1.2)
        }
    }

    private func drawCountryLabelsEquirectangular(context: GraphicsContext, toScreen: (Double, Double) -> CGPoint) {
        for c in WorldVectorGeography.countries {
            let pt = toScreen(c.center.latitude, c.center.longitude)
            context.draw(
                Text("\(c.flag) \(c.name)").font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.85)),
                at: pt,
                anchor: .center
            )
        }
    }

    private func drawVectorCountriesAzimuthal(
        context: GraphicsContext,
        toScreen: (Double, Double) -> CGPoint,
        center: CGPoint,
        maxRadius: CGFloat
    ) {
        for poly in WorldVectorGeography.countryBoundaries {
            guard poly.coordinates.count >= 3 else { continue }
            var path = Path()
            var started = false

            for pt in poly.coordinates {
                let p = toScreen(pt.latitude, pt.longitude)
                let dist = hypot(p.x - center.x, p.y - center.y)
                if dist <= maxRadius + 40 {
                    if !started {
                        path.move(to: p)
                        started = true
                    } else {
                        path.addLine(to: p)
                    }
                }
            }

            if started {
                context.fill(path, with: .color(Color(red: 0.12, green: 0.22, blue: 0.26).opacity(0.55)))
                context.stroke(path, with: .color(Color(red: 0.28, green: 0.70, blue: 0.85).opacity(0.80)), lineWidth: 1.2)
            }
        }
    }

    private func drawCountryLabelsAzimuthal(
        context: GraphicsContext,
        toScreen: (Double, Double) -> CGPoint,
        center: CGPoint,
        maxRadius: CGFloat
    ) {
        for c in WorldVectorGeography.countries {
            let pt = toScreen(c.center.latitude, c.center.longitude)
            let dist = hypot(pt.x - center.x, pt.y - center.y)
            if dist <= maxRadius - 10 {
                context.draw(
                    Text("\(c.flag) \(c.name)").font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.9)),
                    at: pt,
                    anchor: .center
                )
            }
        }
    }

    // MARK: - Maidenhead Field Labels (LM, JN, KO...)

    private func drawMaidenheadFieldLabels(
        context: GraphicsContext,
        size: CGSize,
        toScreen: (Double, Double) -> CGPoint
    ) {
        for fieldLat in 0..<18 {
            for fieldLon in 0..<18 {
                let minLon = Double(fieldLon) * 20.0 - 180.0
                let minLat = Double(fieldLat) * 10.0 - 90.0
                let centerPt = toScreen(minLat + 5.0, minLon + 10.0)

                let charA = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(fieldLon))))
                let charB = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(fieldLat))))
                let text = "\(charA)\(charB)"

                context.draw(
                    Text(text)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(Color(red: 0.15, green: 0.55, blue: 0.75).opacity(0.85)),
                    at: centerPt,
                    anchor: .center
                )
            }
        }
    }

    // MARK: - Maidenhead Tile Rendering

    private func drawMaidenheadGridTiles(
        context: GraphicsContext,
        size: CGSize,
        toScreen: (Double, Double) -> CGPoint
    ) {
        if showGridLines {
            drawMaidenheadFieldLabels(context: context, size: size, toScreen: toScreen)
        }

        for (grid4, summary) in logSummaries {
            guard let box = MaidenheadGridEngine.boundingBox(for: grid4) else { continue }
            let pTopLeft = toScreen(box.maxLat, box.minLon)
            let pBottomRight = toScreen(box.minLat, box.maxLon)

            let tileRect = CGRect(
                x: min(pTopLeft.x, pBottomRight.x),
                y: min(pTopLeft.y, pBottomRight.y),
                width: max(2, abs(pBottomRight.x - pTopLeft.x)),
                height: max(2, abs(pBottomRight.y - pTopLeft.y))
            )

            let color: Color
            if activeOnAirGrids.contains(grid4) {
                color = .cyan
            } else if summary.isConfirmed {
                color = .green
            } else {
                color = .orange
            }

            context.fill(Path(tileRect), with: .color(color.opacity(0.35)))
            context.stroke(Path(tileRect), with: .color(color.opacity(0.75)), lineWidth: 0.8)
        }
    }

    private func drawSolarTerminatorShade(
        context: GraphicsContext,
        size: CGSize,
        subSolar: SubSolarPosition,
        terminator: [GeoCoordinate],
        toScreen: (Double, Double) -> CGPoint
    ) {
        guard terminator.count >= 2 else { return }
        var termPath = Path()
        let first = terminator[0]
        termPath.move(to: toScreen(first.latitude, first.longitude))
        for pt in terminator.dropFirst() {
            termPath.addLine(to: toScreen(pt.latitude, pt.longitude))
        }
        context.stroke(termPath, with: .color(.orange.opacity(0.85)), lineWidth: 2.0)
    }

    private func drawGreatCircleTrafficArcs(
        context: GraphicsContext,
        home: GeoCoordinate,
        toScreen: (Double, Double) -> CGPoint
    ) {
        for m in markers.prefix(35) {
            let waypoints = GeodesicMath.greatCircleWaypoints(from: home, to: m.coordinate, count: 20)
            guard waypoints.count >= 2 else { continue }

            var path = Path()
            let p0 = toScreen(waypoints[0].latitude, waypoints[0].longitude)
            path.move(to: p0)

            for i in 1..<waypoints.count {
                let p = toScreen(waypoints[i].latitude, waypoints[i].longitude)
                if abs(p.x - toScreen(waypoints[i - 1].latitude, waypoints[i - 1].longitude).x) < 400 {
                    path.addLine(to: p)
                } else {
                    path.move(to: p)
                }
            }

            let c = colorForBand(m.band)
            context.stroke(path, with: .color(c.opacity(0.7)), lineWidth: 1.4)
        }
    }

    // MARK: - Smart Decluttered Pins Overlay

    @ViewBuilder
    private func pinsOverlay(size: CGSize) -> some View {
        let arranged = arrangePins(size: size)
        ForEach(arranged) { item in
            Button {
                onSelectMarker(item.marker)
            } label: {
                HStack(spacing: 3) {
                    Text(item.marker.flag.isEmpty ? "🌐" : item.marker.flag)
                        .font(.system(size: 11))
                    Text(item.marker.callsign)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(colorForBand(item.marker.band), lineWidth: 1.0)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .position(item.screenPosition)
        }
    }

    private struct ArrangedPin: Identifiable {
        let id = UUID()
        let marker: Globe3DMarker
        var screenPosition: CGPoint
    }

    private func arrangePins(size: CGSize) -> [ArrangedPin] {
        var list: [ArrangedPin] = []
        var occupied: [CGPoint] = []

        for m in markers.prefix(25) {
            var pt = calculateScreenPosition(m.coordinate, size: size)

            // Collision avoidance: fan out overlapping pins
            for occ in occupied {
                let dist = hypot(pt.x - occ.x, pt.y - occ.y)
                if dist < 26.0 {
                    pt.y += 18.0
                    pt.x += 12.0
                }
            }

            occupied.append(pt)
            list.append(ArrangedPin(marker: m, screenPosition: pt))
        }
        return list
    }

    private func calculateScreenPosition(_ coord: GeoCoordinate, size: CGSize) -> CGPoint {
        if mode == .azimuthal {
            let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
            let maxRadius = min(size.width, size.height) / 2.0 - 24.0
            let maxDistKm: Double = max(3000.0, azimuthalRangeKm)

            let distKm = GeodesicMath.distanceKm(from: homeCoordinate, to: coord)
            let bearingDeg = GeodesicMath.initialBearing(from: homeCoordinate, to: coord)
            let bearingRad = (bearingDeg - 90.0) * .pi / 180.0

            let r = (distKm / maxDistKm) * Double(maxRadius)
            let x = center.x + CGFloat(r * cos(bearingRad))
            let y = center.y + CGFloat(r * sin(bearingRad))
            return CGPoint(x: x, y: y)
        } else {
            let x = (coord.longitude + 180.0) / 360.0 * size.width
            let y = (90.0 - coord.latitude) / 180.0 * size.height
            return CGPoint(x: x, y: y)
        }
    }

    private func mapWatermark(size: CGSize) -> some View {
        VStack {
            Spacer()
            HStack {
                Text(mode == .azimuthal ? "📡 Azimuthal Equidistant · Range \(Int(azimuthalRangeKm)) km" : "🗺 GridTracker 2D · \(markers.count) Active Spots")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.7))
                    .padding(6)
                    .background(.ultraThinMaterial.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                    .padding(10)
                Spacer()
            }
        }
    }

    private func colorForBand(_ band: String) -> Color {
        let b = band.uppercased()
        if b == "160M" || b == "80M" { return .red }
        if b == "40M" || b == "30M" { return .orange }
        if b == "20M" || b == "17M" { return .green }
        if b == "15M" || b == "12M" { return .cyan }
        if b == "10M" || b == "6M" { return .purple }
        return .mint
    }
}
