//
//  CountryHeroMapView.swift
//  YAAM
//
//  Created by factoreal on 9/15/26.
//

import SwiftUI
import AppKit
import MapKit
import CoreLocation

// MARK: - Country Hero Map View Representable
public struct CountryHeroMapRepresentable: NSViewRepresentable {
    public let profile: CountryThemeProfile
    public let mapType: MKMapType
    public let showAnnotation: Bool

    public init(
        profile: CountryThemeProfile,
        mapType: MKMapType = .hybrid,
        showAnnotation: Bool = true
    ) {
        self.profile = profile
        self.mapType = mapType
        self.showAnnotation = showAnnotation
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
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true

        if #available(macOS 13.0, *) {
            let config = MKHybridMapConfiguration(elevationStyle: .realistic)
            config.pointOfInterestFilter = .excludingAll
            config.showsTraffic = false
            mapView.preferredConfiguration = config
        }

        context.coordinator.mapView = mapView
        context.coordinator.updateCamera(for: profile, animated: false)
        return mapView
    }

    public func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        if mapView.mapType != mapType {
            mapView.mapType = mapType
        }
        if context.coordinator.lastIso != profile.iso {
            context.coordinator.updateCamera(for: profile, animated: true)
        }
    }

    public class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CountryHeroMapRepresentable
        weak var mapView: MKMapView?
        var lastIso: String = ""

        init(_ parent: CountryHeroMapRepresentable) {
            self.parent = parent
            super.init()
        }

        func updateCamera(for profile: CountryThemeProfile, animated: Bool) {
            guard let mapView = mapView else { return }
            lastIso = profile.iso

            let region = MKCoordinateRegion(
                center: profile.centerCoordinate,
                span: profile.coordinateSpan
            )
            mapView.setRegion(region, animated: animated)

            // Update Annotation
            mapView.removeAnnotations(mapView.annotations)
            if parent.showAnnotation {
                let anno = MKPointAnnotation()
                anno.coordinate = profile.centerCoordinate
                anno.title = "\(profile.flagEmoji) \(profile.name)"
                anno.subtitle = "Prefix: \(profile.prefix) · \(profile.cqZone) · \(profile.ituZone)"
                mapView.addAnnotation(anno)
                mapView.selectAnnotation(anno, animated: true)
            }
        }

        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let identifier = "CountryCenterPin"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view?.canShowCallout = true
                view?.animatesWhenAdded = true
            } else {
                view?.annotation = annotation
            }
            view?.markerTintColor = NSColor(parent.profile.accentColor)
            view?.glyphText = parent.profile.flagEmoji
            return view
        }
    }
}

// MARK: - Country Hero Map Card View (SwiftUI Wrapper with Glassmorphic Overlays)
public struct CountryHeroMapCardView: View {
    public let profile: CountryThemeProfile
    @State private var mapType: MKMapType = .hybrid
    @State private var isInteractive: Bool = true

    public init(profile: CountryThemeProfile) {
        self.profile = profile
    }

    private var formattedCoordinates: String {
        let lat = profile.centerCoordinate.latitude
        let lon = profile.centerCoordinate.longitude
        let latStr = String(format: "%.2f° %@", abs(lat), lat >= 0 ? "N" : "S")
        let lonStr = String(format: "%.2f° %@", abs(lon), lon >= 0 ? "E" : "W")
        return "\(latStr), \(lonStr)"
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            // Native Map
            CountryHeroMapRepresentable(profile: profile, mapType: mapType)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            // Subtle Gradient Vows / Overlays
            VStack {
                HStack {
                    // Geographic Badges Overlay (Top Left)
                    HStack(spacing: 6) {
                        Label(profile.continent, systemImage: "globe.europe.africa.fill")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))

                        Text(profile.cqZone)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))

                        Text(profile.ituZone)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                    }
                    .padding(8)

                    Spacer()

                    // Map Type Switcher (Top Right)
                    HStack(spacing: 4) {
                        Button(action: {
                            withAnimation {
                                mapType = (mapType == .hybrid) ? .standard : .hybrid
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: mapType == .hybrid ? "globe.americas.fill" : "map.fill")
                                Text(mapType == .hybrid ? "Satellite" : "Map")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(profile.accentColor.opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                }

                Spacer()

                // Bottom Coordinates HUD
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9))
                            .foregroundColor(profile.accentColor)
                        Text(formattedCoordinates)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                    .padding(8)

                    Spacer()

                    Text("PREFIX: \(profile.prefix)")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(profile.accentColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundColor(.white)
                        .padding(8)
                }
            }
        }
        .frame(height: 180)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [profile.accentColor.opacity(0.7), profile.secondaryColor.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: profile.accentColor.opacity(0.25), radius: 10, x: 0, y: 4)
    }
}
