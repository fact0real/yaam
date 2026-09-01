//
//  GridTrackerMapView.swift
//  YAAM
//
//  Native MapKit-Powered GridTracker Workspace (Zero-Flicker & Low-CPU Optimized)
//  Displays high-resolution physical/vector maps, Maidenhead Field overlays,
//  classic drop pins, solar greyline terminator, and telemetry HUD.
//

import AppKit
import Combine
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Dedicated Telemetry State (Zero-Re-Render HUD)

@MainActor
public final class MapTelemetryState: ObservableObject {
    @Published public var hoverText: String = "Move cursor over map to inspect coordinates, distance, bearing & grid"

    public init() {}
}

// MARK: - GridTracker Annotation Model

public final class GridTrackerStationAnnotation: NSObject, MKAnnotation {
    public let coordinate: CLLocationCoordinate2D
    public let title: String?
    public let subtitle: String?
    public let marker: Globe3DMarker?
    public let grid: String
    public let isHome: Bool
    public let isConfirmed: Bool

    public init(
        coordinate: CLLocationCoordinate2D,
        title: String?,
        subtitle: String?,
        marker: Globe3DMarker? = nil,
        grid: String,
        isHome: Bool = false,
        isConfirmed: Bool = false
    ) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.marker = marker
        self.grid = grid
        self.isHome = isHome
        self.isConfirmed = isConfirmed
        super.init()
    }
}

// MARK: - Custom Maidenhead Grid Overlay

public final class MaidenheadGridOverlay: NSObject, MKOverlay {
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    public var boundingMapRect: MKMapRect {
        MKMapRect.world
    }
}

// MARK: - Solar Terminator Overlay

public final class SolarTerminatorOverlay: NSObject, MKOverlay {
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    public var boundingMapRect: MKMapRect {
        MKMapRect.world
    }
}

// MARK: - GridTracker MapKit View (SwiftUI Wrapper)

public struct GridTrackerMapView: NSViewRepresentable {
    public var homeCoordinate: GeoCoordinate
    public var markers: [Globe3DMarker]
    public var logSummaries: [String: GridLogSummary]
    public var mapType: MKMapType
    public var showDayNightShadow: Bool
    public var showGridLines: Bool
    public var showTrafficArcs: Bool
    public var telemetryState: MapTelemetryState
    public var onSelectMarker: (Globe3DMarker) -> Void
    public var onSelectGrid: (String) -> Void

    public init(
        homeCoordinate: GeoCoordinate,
        markers: [Globe3DMarker],
        logSummaries: [String: GridLogSummary],
        mapType: MKMapType = .standard,
        showDayNightShadow: Bool = true,
        showGridLines: Bool = true,
        showTrafficArcs: Bool = true,
        telemetryState: MapTelemetryState,
        onSelectMarker: @escaping (Globe3DMarker) -> Void,
        onSelectGrid: @escaping (String) -> Void
    ) {
        self.homeCoordinate = homeCoordinate
        self.markers = markers
        self.logSummaries = logSummaries
        self.mapType = mapType
        self.showDayNightShadow = showDayNightShadow
        self.showGridLines = showGridLines
        self.showTrafficArcs = showTrafficArcs
        self.telemetryState = telemetryState
        self.onSelectMarker = onSelectMarker
        self.onSelectGrid = onSelectGrid
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = mapType
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false

        // Set initial region centered on Europe / Middle East / Asia
        let center = CLLocationCoordinate2D(latitude: homeCoordinate.latitude, longitude: homeCoordinate.longitude)
        let span = MKCoordinateSpan(latitudeDelta: 65, longitudeDelta: 100)
        mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)

        context.coordinator.mapView = mapView
        context.coordinator.setupTrackingArea(mapView)
        context.coordinator.refreshAll(force: true)
        return mapView
    }

    public func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        if mapView.mapType != mapType {
            mapView.mapType = mapType
        }
        context.coordinator.refreshAll(force: false)
    }

    // MARK: - Coordinator (MapKit Engine)

    public class Coordinator: NSObject, MKMapViewDelegate {
        var parent: GridTrackerMapView
        weak var mapView: MKMapView?
        private var trackingArea: NSTrackingArea?

        private var lastAnnotationsSignature: String = ""
        private var lastOverlaysSignature: String = ""
        private var lastHoverUpdate: TimeInterval = 0

        init(_ parent: GridTrackerMapView) {
            self.parent = parent
            super.init()
        }

        func setupTrackingArea(_ view: NSView) {
            if let trackingArea {
                view.removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: view.bounds,
                options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            view.addTrackingArea(area)
            self.trackingArea = area
        }

        @objc func mouseMoved(with event: NSEvent) {
            let now = ProcessInfo.processInfo.systemUptime
            // Throttle mouse hover calculation to 20Hz (every 50ms) to conserve CPU
            guard now - lastHoverUpdate > 0.05, let mapView else { return }
            lastHoverUpdate = now

            let point = mapView.convert(event.locationInWindow, from: nil)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)

            let home = parent.homeCoordinate
            let target = GeoCoordinate(latitude: coord.latitude, longitude: coord.longitude)
            let distKm = GeodesicMath.distanceKm(from: home, to: target)
            let bearing = GeodesicMath.initialBearing(from: home, to: target)
            let grid = MaidenheadGridEngine.locator(from: target)
            let miles = distKm * GeodesicMath.kmToMiles
            let cardinal = GeodesicMath.compassCardinal(for: bearing)

            parent.telemetryState.hoverText = String(
                format: "%.3f, %.3f · %.0f mi (%.0f km) · %.0f° %@ · %@",
                coord.latitude, coord.longitude, miles, distKm, bearing, cardinal, grid
            )
        }

        func refreshAll(force: Bool) {
            updateOverlays(force: force)
            updateAnnotations(force: force)
        }

        private func updateOverlays(force: Bool) {
            guard let mapView else { return }

            let overlaySig = "\(parent.showGridLines):\(parent.showDayNightShadow):\(parent.showTrafficArcs):\(parent.markers.prefix(30).count)"
            if !force && overlaySig == lastOverlaysSignature { return }
            lastOverlaysSignature = overlaySig

            mapView.removeOverlays(mapView.overlays)

            if parent.showGridLines {
                mapView.addOverlay(MaidenheadGridOverlay(), level: .aboveRoads)
            }

            if parent.showDayNightShadow {
                mapView.addOverlay(SolarTerminatorOverlay(), level: .aboveRoads)
            }

            if parent.showTrafficArcs {
                let home = parent.homeCoordinate
                for m in parent.markers.prefix(30) {
                    let waypoints = GeodesicMath.greatCircleWaypoints(from: home, to: m.coordinate, count: 20)
                    var coords = waypoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    let polyline = MKPolyline(coordinates: &coords, count: coords.count)
                    mapView.addOverlay(polyline, level: .aboveLabels)
                }
            }
        }

        private func updateAnnotations(force: Bool) {
            guard let mapView else { return }

            let annSig = "\(parent.homeCoordinate.latitude):\(parent.homeCoordinate.longitude):\(parent.markers.count):\(parent.logSummaries.count)"
            if !force && annSig == lastAnnotationsSignature { return }
            lastAnnotationsSignature = annSig

            mapView.removeAnnotations(mapView.annotations)

            var annotations: [MKAnnotation] = []

            // A. Home Station Annotation
            let homeCoord = CLLocationCoordinate2D(latitude: parent.homeCoordinate.latitude, longitude: parent.homeCoordinate.longitude)
            let homeAnn = GridTrackerStationAnnotation(
                coordinate: homeCoord,
                title: "📡 HOME [EP2AES]",
                subtitle: "Tehran, Iran · LM55",
                grid: "LM55",
                isHome: true,
                isConfirmed: true
            )
            annotations.append(homeAnn)

            // B. Active Station Markers / Decodes
            var seenGrids = Set<String>()
            for m in parent.markers.prefix(40) {
                let coord = CLLocationCoordinate2D(latitude: m.coordinate.latitude, longitude: m.coordinate.longitude)
                let ann = GridTrackerStationAnnotation(
                    coordinate: coord,
                    title: "\(m.flag) \(m.callsign)",
                    subtitle: "\(m.grid) · \(m.band) \(m.mode) \(m.snr.map { "\($0) dB" } ?? "")",
                    marker: m,
                    grid: m.grid,
                    isHome: false,
                    isConfirmed: true
                )
                annotations.append(ann)
                if !m.grid.isEmpty {
                    seenGrids.insert(String(m.grid.prefix(4)).uppercased())
                }
            }

            // C. Worked Logbook Grids (Drop Pins for Top Worked Squares)
            for (grid4, summary) in parent.logSummaries where !seenGrids.contains(grid4) {
                guard let box = MaidenheadGridEngine.boundingBox(for: grid4) else { continue }
                let center = box.center
                let coord = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)

                let ann = GridTrackerStationAnnotation(
                    coordinate: coord,
                    title: "\(grid4) · \(summary.lastWorkedCallsign ?? "Worked")",
                    subtitle: "\(summary.qsoCount) QSOs · \(summary.isConfirmed ? "🟢 Confirmed" : "🟠 Worked")",
                    grid: grid4,
                    isHome: false,
                    isConfirmed: summary.isConfirmed
                )
                annotations.append(ann)
            }

            mapView.addAnnotations(annotations)
        }

        // MARK: - MKMapViewDelegate

        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let customAnn = annotation as? GridTrackerStationAnnotation else { return nil }

            let identifier = customAnn.isHome ? "HomeStationPin" : "GridTrackerPin"
            var pinView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

            if pinView == nil {
                pinView = MKMarkerAnnotationView(annotation: customAnn, reuseIdentifier: identifier)
                pinView?.canShowCallout = true
            } else {
                pinView?.annotation = customAnn
            }

            if customAnn.isHome {
                pinView?.markerTintColor = NSColor.systemGreen
                pinView?.glyphImage = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "Home")
                pinView?.displayPriority = .required
            } else {
                pinView?.markerTintColor = customAnn.isConfirmed ? NSColor.systemRed : NSColor.systemOrange
                pinView?.glyphText = "📍"
                pinView?.displayPriority = .defaultHigh
            }

            return pinView
        }

        public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let customAnn = view.annotation as? GridTrackerStationAnnotation {
                if let m = customAnn.marker {
                    parent.onSelectMarker(m)
                } else if !customAnn.grid.isEmpty {
                    parent.onSelectGrid(customAnn.grid)
                }
            }
        }

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let gridOverlay = overlay as? MaidenheadGridOverlay {
                return MaidenheadGridRenderer(overlay: gridOverlay)
            }

            if let solarOverlay = overlay as? SolarTerminatorOverlay {
                return SolarTerminatorRenderer(overlay: solarOverlay)
            }

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = NSColor.systemYellow.withAlphaComponent(0.8)
                renderer.lineWidth = 2.0
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - High-Performance Maidenhead Grid Renderer (Fields & 4-Char Squares)

public final class MaidenheadGridRenderer: MKOverlayRenderer {
    public override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let zoom = Double(zoomScale)

        // 1. Draw 2-Character Maidenhead Field Lines (Every 20° lon, 10° lat)
        context.saveGState()
        context.setStrokeColor(NSColor(white: 0.15, alpha: 0.75).cgColor)
        context.setLineWidth(CGFloat(1.2 / zoom))

        // Latitude Field Lines (-80° to +80°)
        for lat in stride(from: -80.0, through: 80.0, by: 10.0) {
            let start = MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: -180.0))
            let end = MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: 180.0))
            let pt1 = point(for: start)
            let pt2 = point(for: end)
            context.move(to: pt1)
            context.addLine(to: pt2)
        }

        // Longitude Field Lines (-180° to +180°)
        for lon in stride(from: -180.0, through: 180.0, by: 20.0) {
            let start = MKMapPoint(CLLocationCoordinate2D(latitude: 85.0, longitude: lon))
            let end = MKMapPoint(CLLocationCoordinate2D(latitude: -85.0, longitude: lon))
            let pt1 = point(for: start)
            let pt2 = point(for: end)
            context.move(to: pt1)
            context.addLine(to: pt2)
        }
        context.strokePath()

        // 2. Draw Bold 2-Character Field Labels (LM, JN, KO, etc.)
        let fontSize = CGFloat(16.0 / zoom)
        if fontSize > 5.0 && fontSize < 60.0 {
            let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(red: 0.10, green: 0.35, blue: 0.55, alpha: 0.85)
            ]

            for fieldLat in 0..<18 {
                for fieldLon in 0..<18 {
                    let minLon = Double(fieldLon) * 20.0 - 180.0
                    let minLat = Double(fieldLat) * 10.0 - 90.0
                    let centerCoord = CLLocationCoordinate2D(latitude: minLat + 5.0, longitude: minLon + 10.0)
                    let centerPt = point(for: MKMapPoint(centerCoord))

                    let charA = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(fieldLon))))
                    let charB = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(fieldLat))))
                    let text = "\(charA)\(charB)"

                    let str = NSAttributedString(string: text, attributes: attrs)
                    let strSize = str.size()

                    let textRect = CGRect(
                        x: centerPt.x - strSize.width / 2.0,
                        y: centerPt.y - strSize.height / 2.0,
                        width: strSize.width,
                        height: strSize.height
                    )

                    context.saveGState()
                    let ctLine = CTLineCreateWithAttributedString(str)
                    context.textPosition = CGPoint(x: textRect.minX, y: textRect.maxY)
                    CTLineDraw(ctLine, context)
                    context.restoreGState()
                }
            }
        }

        context.restoreGState()
    }
}

// MARK: - Solar Terminator Overlay Renderer

public final class SolarTerminatorRenderer: MKOverlayRenderer {
    public override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let zoom = Double(zoomScale)
        let subSolar = SolarEphemeris.calculate(at: Date())
        let terminator = SolarEphemeris.terminatorCoordinates(at: Date(), stepDegrees: 2.0)
        guard terminator.count >= 3 else { return }

        context.saveGState()

        // 1. Draw Day/Night Terminator Boundary Stroke
        context.setStrokeColor(NSColor.systemOrange.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(CGFloat(2.0 / zoom))

        var started = false
        for coord in terminator {
            let mapPoint = MKMapPoint(CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude))
            let pt = point(for: mapPoint)
            if !started {
                context.move(to: pt)
                started = true
            } else {
                context.addLine(to: pt)
            }
        }
        context.strokePath()

        // 2. Draw Sun Icon at Subsolar Point
        let sunPoint = point(for: MKMapPoint(CLLocationCoordinate2D(latitude: subSolar.latitude, longitude: subSolar.longitude)))
        let sunRadius = CGFloat(8.0 / zoom)
        context.setFillColor(NSColor.systemYellow.cgColor)
        context.fillEllipse(in: CGRect(x: sunPoint.x - sunRadius, y: sunPoint.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2))

        context.restoreGState()
    }
}
