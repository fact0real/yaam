// Compile with RecentQSOMapRoute.swift, RecentQSORouteBadge.swift and AstronomicalSolarEngine.swift.
// Synthetic routes only: does not open AppState or write to a real logbook.
import AppKit
import SwiftUI
import MapKit

@main struct RecentQSOMapVisualReview {
    @MainActor final class Delegate: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            RecentQSOArrowRenderer(overlay: overlay)
        }
    }
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = Delegate()
        let route = RecentQSOMapRoute(identity: "test", origin: GeoCoordinate(latitude: 35.7, longitude: 51.4),
            destination: GeoCoordinate(latitude: 51.5, longitude: -0.1), sourceCallsign: "EP2AES", destinationCallsign: "G0JHC")
        let pacific = RecentQSOMapRoute(identity: "pacific", origin: GeoCoordinate(latitude: 35, longitude: 170),
            destination: GeoCoordinate(latitude: 40, longitude: -160), sourceCallsign: "A", destinationCallsign: "B").polyline()
        for index in 1..<pacific.pointCount {
            assert(abs(pacific.points()[index].x - pacific.points()[index - 1].x) < MKMapRect.world.size.width / 2)
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (width, height) in [(1100.0, 390.0), (510.0, 245.0)] {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                let content = NSView(frame: window.contentView!.bounds)
                let map = MKMapView(frame: content.bounds)
                map.delegate = delegate
                content.addSubview(map)
                let presentation = RecentQSOMapPresentation()
                presentation.update(route, on: map)
                let badge = NSHostingView(rootView: RecentQSORouteBadge(source: route.sourceCallsign, destination: route.destinationCallsign))
                badge.frame = NSRect(x: 12, y: 12, width: 285, height: 62)
                content.addSubview(badge)
                window.contentView = content
                window.orderFront(nil)
                RunLoop.current.run(until: Date().addingTimeInterval(4))
                guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { fatalError("No bitmap") }
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name)-\(Int(width)).png"))
                let before = map.visibleMapRect
                presentation.update(route, on: map)
                assert(map.visibleMapRect.origin.x == before.origin.x && map.visibleMapRect.origin.y == before.origin.y && map.visibleMapRect.size.width == before.size.width && map.visibleMapRect.size.height == before.size.height, "Unchanged route must preserve navigation")
                presentation.update(nil, on: map)
                assert(!map.overlays.contains { $0 is RecentQSOArrowPolyline }, "Expired route must be removed")
                window.orderOut(nil)
            }
        }
        print("Route geometry, unchanged-camera, expiry removal and light/dark map renders passed")
    }
}
