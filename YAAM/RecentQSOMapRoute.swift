import AppKit
import MapKit

public struct RecentQSOMapRoute: Equatable {
    let identity: String
    let origin: GeoCoordinate
    let destination: GeoCoordinate
    let sourceCallsign: String
    let destinationCallsign: String

    /// Unwrap longitude so a Pacific route follows the short crossing, not a world-wide line.
    func polyline() -> RecentQSOArrowPolyline {
        let waypoints = GeodesicMath.greatCircleWaypoints(from: origin, to: destination, count: 96)
        var previousX: Double?
        let world = MKMapRect.world.size.width
        var points = waypoints.map { coordinate -> MKMapPoint in
            var point = MKMapPoint(CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if let previousX {
                while point.x - previousX > world / 2 { point.x -= world }
                while point.x - previousX < -world / 2 { point.x += world }
            }
            previousX = point.x
            return point
        }
        return RecentQSOArrowPolyline(points: &points, count: points.count)
    }
}

final class RecentQSOArrowPolyline: MKPolyline {}

/// Screen-sized halo, core and directional chevrons stay readable at every map zoom.
final class RecentQSOArrowRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let line = overlay as? RecentQSOArrowPolyline, line.pointCount > 1 else { return }
        let points = (0..<line.pointCount).map { point(for: line.points()[$0]) }
        let scale = max(CGFloat(zoomScale), 0.0000001)
        let path = CGMutablePath()
        path.addLines(between: points)
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for (width, color) in [(11.0, NSColor.black.withAlphaComponent(0.28)),
                               (7.0, NSColor.white.withAlphaComponent(0.95)),
                               (4.0, NSColor.systemTeal)] {
            context.addPath(path)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width / scale)
            context.strokePath()
        }
        // Three arrowheads convey source → destination without motion or color alone.
        for fraction in [0.35, 0.62, 0.86] {
            let index = min(points.count - 1, max(1, Int(Double(points.count - 1) * fraction)))
            let tip = points[index]
            let before = points[index - 1]
            let angle = atan2(tip.y - before.y, tip.x - before.x)
            let length = 15 / scale
            let wing = 7 / scale
            let back = CGPoint(x: tip.x - cos(angle) * length, y: tip.y - sin(angle) * length)
            let arrow = CGMutablePath()
            arrow.move(to: CGPoint(x: back.x - sin(angle) * wing, y: back.y + cos(angle) * wing))
            arrow.addLine(to: tip)
            arrow.addLine(to: CGPoint(x: back.x + sin(angle) * wing, y: back.y - cos(angle) * wing))
            for (width, color) in [(7.0, NSColor.white), (3.5, NSColor.systemTeal)] {
                context.addPath(arrow)
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(width / scale)
                context.strokePath()
            }
        }
        for endpoint in [points[0], points[points.count - 1]] {
            let radius = 5 / scale
            context.setFillColor(NSColor.systemTeal.cgColor)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2 / scale)
            context.addEllipse(in: CGRect(x: endpoint.x - radius, y: endpoint.y - radius, width: radius * 2, height: radius * 2))
            context.drawPath(using: .fillStroke)
        }
    }
}

/// Separate from normal traffic overlays so refreshes never remove or refocus the route accidentally.
final class RecentQSOMapPresentation {
    private var route: RecentQSOMapRoute?
    private var overlay: RecentQSOArrowPolyline?

    func update(_ next: RecentQSOMapRoute?, on map: MKMapView) {
        let changed = next != route
        if changed, let overlay { map.removeOverlay(overlay) }
        if changed {
            route = next
            overlay = next?.polyline()
        }
        guard let overlay else { return }
        if !map.overlays.contains(where: { ($0 as AnyObject) === overlay }) {
            map.addOverlay(overlay, level: .aboveLabels)
        }
        if changed {
            let rect = overlay.boundingMapRect
            // Fit once for each new contact/location; subsequent updates preserve user navigation.
            map.setVisibleMapRect(rect, edgePadding: NSEdgeInsets(top: 80, left: 60, bottom: 70, right: 60), animated: true)
        }
    }
}
