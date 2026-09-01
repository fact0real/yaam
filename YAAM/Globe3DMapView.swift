//
//  Globe3DMapView.swift
//  YAAM
//
//  Native Apple Maps Photorealistic 3D Globe & Satellite Hybrid Engine
//  High-resolution terrain, dark ocean bathymetry, crisp country borders,
//  sleek translucent city badges, and glowing geodesic great-circle traffic arcs.
//

import AppKit
import Combine
import CoreLocation
import MapKit
import SwiftUI

// MARK: - 3D Globe Station Annotation

public final class Globe3DStationAnnotation: NSObject, MKAnnotation {
    public let coordinate: CLLocationCoordinate2D
    public let title: String?
    public let subtitle: String?
    public let marker: Globe3DMarker?
    public let isHome: Bool
    public let isActiveTarget: Bool
    public let badgeLabel: String

    public init(
        coordinate: CLLocationCoordinate2D,
        title: String?,
        subtitle: String?,
        marker: Globe3DMarker? = nil,
        isHome: Bool = false,
        isActiveTarget: Bool = false,
        badgeLabel: String = ""
    ) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.marker = marker
        self.isHome = isHome
        self.isActiveTarget = isActiveTarget
        self.badgeLabel = badgeLabel
        super.init()
    }
}

// MARK: - Photorealistic 3D Globe NSViewRepresentable

public struct Globe3DMapView: NSViewRepresentable {
    public var homeCoordinate: GeoCoordinate
    public var markers: [Globe3DMarker]
    public var mapType: MKMapType
    public var showGreatCircleArcs: Bool
    public var showDayNightShadow: Bool
    public var showCountryLabels: Bool
    public var telemetryState: MapTelemetryState
    public var onSelectMarker: ((Globe3DMarker) -> Void)?

    public init(
        homeCoordinate: GeoCoordinate,
        markers: [Globe3DMarker],
        mapType: MKMapType = .hybrid,
        showGreatCircleArcs: Bool = true,
        showDayNightShadow: Bool = true,
        showCountryLabels: Bool = true,
        telemetryState: MapTelemetryState,
        onSelectMarker: ((Globe3DMarker) -> Void)? = nil
    ) {
        self.homeCoordinate = homeCoordinate
        self.markers = markers
        self.mapType = mapType
        self.showGreatCircleArcs = showGreatCircleArcs
        self.showDayNightShadow = showDayNightShadow
        self.showCountryLabels = showCountryLabels
        self.telemetryState = telemetryState
        self.onSelectMarker = onSelectMarker
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
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true

        // Configure modern realistic 3D elevation configuration if available
        if #available(macOS 13.0, *) {
            let config = MKHybridMapConfiguration(elevationStyle: .realistic)
            config.pointOfInterestFilter = .excludingAll
            config.showsTraffic = false
            mapView.preferredConfiguration = config
        }

        // Set initial 3D Globe camera looking at home QTH with realistic tilt
        let homeCenter = CLLocationCoordinate2D(
            latitude: homeCoordinate.latitude,
            longitude: homeCoordinate.longitude
        )
        let camera = MKMapCamera(
            lookingAtCenter: homeCenter,
            fromDistance: 19_500_000,
            pitch: 32,
            heading: 0
        )
        mapView.setCamera(camera, animated: false)

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

    // MARK: - Coordinator (MapKit 3D Globe Engine)

    public class Coordinator: NSObject, MKMapViewDelegate {
        var parent: Globe3DMapView
        weak var mapView: MKMapView?
        private var trackingArea: NSTrackingArea?

        private var lastAnnotationsSig: String = ""
        private var lastOverlaysSig: String = ""
        private var lastHoverUpdate: TimeInterval = 0

        init(_ parent: Globe3DMapView) {
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

            let overlaySig = "\(parent.showGreatCircleArcs):\(parent.showDayNightShadow):\(parent.markers.prefix(35).count)"
            if !force && overlaySig == lastOverlaysSig { return }
            lastOverlaysSig = overlaySig

            mapView.removeOverlays(mapView.overlays)

            // 1. Day / Night Solar Terminator
            if parent.showDayNightShadow {
                mapView.addOverlay(SolarTerminatorOverlay(), level: .aboveRoads)
            }

            // 2. Glowing Geodesic Great-Circle Arcs
            if parent.showGreatCircleArcs {
                let home = parent.homeCoordinate
                for (index, m) in parent.markers.prefix(35).enumerated() {
                    let waypoints = GeodesicMath.greatCircleWaypoints(from: home, to: m.coordinate, count: 28)
                    var coords = waypoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    let polyline = GlobeArcPolyline(coordinates: &coords, count: coords.count)
                    polyline.isActiveTarget = (index == 0)
                    mapView.addOverlay(polyline, level: .aboveLabels)
                }
            }
        }

        private func updateAnnotations(force: Bool) {
            guard let mapView else { return }

            let annSig = "\(parent.homeCoordinate.latitude):\(parent.homeCoordinate.longitude):\(parent.markers.prefix(35).map(\.callsign).joined(separator: ","))"
            if !force && annSig == lastAnnotationsSig { return }
            lastAnnotationsSig = annSig

            mapView.removeAnnotations(mapView.annotations)

            var list: [MKAnnotation] = []

            // A. Home Station
            let homeCoord = CLLocationCoordinate2D(
                latitude: parent.homeCoordinate.latitude,
                longitude: parent.homeCoordinate.longitude
            )
            let homeAnn = Globe3DStationAnnotation(
                coordinate: homeCoord,
                title: "📡 HOME STATION",
                subtitle: "\(String(format: "%.2f", parent.homeCoordinate.latitude)), \(String(format: "%.2f", parent.homeCoordinate.longitude))",
                isHome: true,
                isActiveTarget: false,
                badgeLabel: "HOME"
            )
            list.append(homeAnn)

            // B. Active Stations & Cities
            for (index, m) in parent.markers.prefix(35).enumerated() {
                let coord = CLLocationCoordinate2D(latitude: m.coordinate.latitude, longitude: m.coordinate.longitude)
                let label = m.callsign.isEmpty ? m.grid : m.callsign
                let ann = Globe3DStationAnnotation(
                    coordinate: coord,
                    title: "\(m.flag) \(m.callsign)",
                    subtitle: "\(m.grid) · \(m.band) \(m.mode) \(m.snr.map { "\($0) dB" } ?? "")",
                    marker: m,
                    isHome: false,
                    isActiveTarget: (index == 0),
                    badgeLabel: label
                )
                list.append(ann)
            }

            mapView.addAnnotations(list)
        }

        // MARK: - MKMapViewDelegate

        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let stationAnn = annotation as? Globe3DStationAnnotation else { return nil }

            let identifier = stationAnn.isHome ? "GlobeHomePin" : "GlobeStationPill"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

            if view == nil {
                view = GlobePillAnnotationView(annotation: stationAnn, reuseIdentifier: identifier)
            } else {
                view?.annotation = stationAnn
                if let pillView = view as? GlobePillAnnotationView {
                    pillView.configure(with: stationAnn)
                }
            }

            return view
        }

        public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let stationAnn = view.annotation as? Globe3DStationAnnotation, let m = stationAnn.marker {
                parent.onSelectMarker?(m)
            }
        }

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let arcPolyline = overlay as? GlobeArcPolyline {
                let renderer = MKPolylineRenderer(polyline: arcPolyline)
                if arcPolyline.isActiveTarget {
                    renderer.strokeColor = NSColor(red: 0.25, green: 0.95, blue: 0.45, alpha: 0.95)
                    renderer.lineWidth = 3.2
                } else {
                    renderer.strokeColor = NSColor(red: 0.40, green: 0.78, blue: 0.98, alpha: 0.65)
                    renderer.lineWidth = 1.8
                }
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            if let solarOverlay = overlay as? SolarTerminatorOverlay {
                return SolarTerminatorRenderer(overlay: solarOverlay)
            }

            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Custom Polyline with Active Flag

public final class GlobeArcPolyline: MKPolyline {
    public var isActiveTarget: Bool = false
}

// MARK: - Sleek Translucent City & Station Pill Annotation View

public final class GlobePillAnnotationView: MKAnnotationView {
    private let pillView = NSView()
    private let label = NSTextField(labelWithString: "")
    private let nodeCircle = NSView()

    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupViews()
        if let ann = annotation as? Globe3DStationAnnotation {
            configure(with: ann)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        canShowCallout = true
        wantsLayer = true

        // 1. Center Node Dot
        nodeCircle.wantsLayer = true
        nodeCircle.layer?.cornerRadius = 5.0
        nodeCircle.layer?.borderWidth = 1.5
        nodeCircle.layer?.borderColor = NSColor.white.cgColor
        nodeCircle.frame = NSRect(x: -5, y: -5, width: 10, height: 10)
        addSubview(nodeCircle)

        // 2. Translucent Pill Badge (above the node)
        pillView.wantsLayer = true
        pillView.layer?.cornerRadius = 9.0
        pillView.layer?.masksToBounds = true
        pillView.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.82).cgColor
        pillView.layer?.borderWidth = 1.0
        pillView.layer?.borderColor = NSColor(white: 0.45, alpha: 0.55).cgColor

        label.font = NSFont.systemFont(ofSize: 10.5, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false

        pillView.addSubview(label)
        addSubview(pillView)
    }

    public func configure(with annotation: Globe3DStationAnnotation) {
        label.stringValue = annotation.badgeLabel
        label.sizeToFit()

        let textWidth = max(24.0, label.frame.width)
        let pillWidth = textWidth + 14.0
        let pillHeight: CGFloat = 18.0

        pillView.frame = NSRect(
            x: -pillWidth / 2.0,
            y: 8,
            width: pillWidth,
            height: pillHeight
        )
        label.frame = NSRect(x: 7, y: 1.5, width: textWidth, height: 15)

        if annotation.isHome {
            nodeCircle.layer?.backgroundColor = NSColor.systemGreen.cgColor
            nodeCircle.layer?.borderColor = NSColor.white.cgColor
            pillView.layer?.backgroundColor = NSColor(red: 0.08, green: 0.40, blue: 0.20, alpha: 0.88).cgColor
            pillView.layer?.borderColor = NSColor.systemGreen.cgColor
        } else if annotation.isActiveTarget {
            nodeCircle.layer?.backgroundColor = NSColor(red: 0.25, green: 0.95, blue: 0.45, alpha: 1.0).cgColor
            pillView.layer?.backgroundColor = NSColor(red: 0.06, green: 0.35, blue: 0.28, alpha: 0.88).cgColor
            pillView.layer?.borderColor = NSColor(red: 0.25, green: 0.95, blue: 0.45, alpha: 0.85).cgColor
        } else {
            nodeCircle.layer?.backgroundColor = NSColor(white: 0.85, alpha: 0.95).cgColor
            pillView.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.82).cgColor
            pillView.layer?.borderColor = NSColor(white: 0.45, alpha: 0.55).cgColor
        }
    }
}
