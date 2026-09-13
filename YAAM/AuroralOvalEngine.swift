//
//  AuroralOvalEngine.swift
//  YAAM
//
//  Real-time NOAA OVATION-Style Auroral Oval Prediction Engine
//  Generates dynamic geomagnetic auroral oval boundary polygons for Northern (Borealis)
//  and Southern (Australis) hemispheres based on planetary Kp index and IMF Bz polarity.
//

import Combine
import Foundation
import SwiftUI

public struct AuroralOvalBoundary: Equatable, Sendable {
    public let northernOuterRing: [GeoCoordinate]
    public let northernInnerRing: [GeoCoordinate]
    public let southernOuterRing: [GeoCoordinate]
    public let southernInnerRing: [GeoCoordinate]
    public let equatorwardEdgeGeomagneticLat: Double
    public let kpIndex: Double
    public let auroralActivityLevel: String // "Quiet", "Active", "Minor Storm (G1)", "Severe Storm (G4)"
}

@MainActor
public final class AuroralOvalEngine: ObservableObject {
    public static let shared = AuroralOvalEngine()

    @Published public private(set) var boundary: AuroralOvalBoundary
    @Published public private(set) var currentKp: Double = 2.0
    @Published public private(set) var currentBz: Double = 1.0 // nT
    @Published public private(set) var isStormActive: Bool = false

    // Geomagnetic Pole Coordinates (WGS84)
    public static let northGeomagneticPole = GeoCoordinate(latitude: 80.5, longitude: -72.6)
    public static let southGeomagneticPole = GeoCoordinate(latitude: -80.5, longitude: 107.4)

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.boundary = Self.calculateBoundary(kp: 2.0, bz: 1.0)
        startAutoRefresh()
    }

    public func updateSpaceWeatherIndices(kp: Double, bz: Double) {
        self.currentKp = max(0.0, min(9.0, kp))
        self.currentBz = bz
        self.isStormActive = kp >= 5.0 || (kp >= 4.0 && bz < -5.0)
        self.boundary = Self.calculateBoundary(kp: currentKp, bz: currentBz)
    }

    private func startAutoRefresh() {
        // Refresh every 10 minutes from NOAA SWPC
        Timer.publish(every: 600.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchLatestNOAAIndices()
            }
            .store(in: &cancellables)

        fetchLatestNOAAIndices()
    }

    public func fetchLatestNOAAIndices() {
        guard let url = URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [[String]],
                   let lastRow = json.last, lastRow.count >= 2,
                   let kpVal = Double(lastRow[1]) {
                    DispatchQueue.main.async {
                        self.updateSpaceWeatherIndices(kp: kpVal, bz: self.currentBz)
                    }
                }
            } catch {}
        }.resume()
    }

    // MARK: - Empirical Auroral Oval Physical Model (Holzworth-Meng / Feldstein)

    public static func calculateBoundary(kp: Double, bz: Double, date: Date = Date()) -> AuroralOvalBoundary {
        // Equatorward boundary expands south as Kp increases and as Bz goes negative (southward)
        // Quiet (Kp=0): boundary ~ 66° magnetic lat
        // Storm (Kp=5): boundary ~ 58° magnetic lat
        // Severe (Kp=9): boundary ~ 48° magnetic lat
        let bzShift = bz < 0 ? min(3.0, abs(bz) * 0.3) : -min(1.5, bz * 0.15)
        let equatorwardMagLat = max(45.0, 66.5 - (kp * 1.9) - bzShift)
        let ovalWidthDeg = max(3.5, 4.0 + (kp * 1.2))

        let polewardMagLat = min(88.0, equatorwardMagLat + ovalWidthDeg)

        // Subsolar point for noon/midnight offset (the oval is shifted ~3-5° towards the midnight sector)
        let subSolar = SolarEphemeris.calculate(at: date)
        let sunLon = subSolar.longitude

        let northOuter = generateOvalRing(
            pole: northGeomagneticPole,
            magLat: equatorwardMagLat,
            sunLongitude: sunLon,
            isNorth: true,
            stepDeg: 5.0
        )
        let northInner = generateOvalRing(
            pole: northGeomagneticPole,
            magLat: polewardMagLat,
            sunLongitude: sunLon,
            isNorth: true,
            stepDeg: 5.0
        )

        let southOuter = generateOvalRing(
            pole: southGeomagneticPole,
            magLat: equatorwardMagLat,
            sunLongitude: sunLon,
            isNorth: false,
            stepDeg: 5.0
        )
        let southInner = generateOvalRing(
            pole: southGeomagneticPole,
            magLat: polewardMagLat,
            sunLongitude: sunLon,
            isNorth: false,
            stepDeg: 5.0
        )

        let activityText: String
        if kp >= 7.0 {
            activityText = "Severe Storm (G3-G5)"
        } else if kp >= 5.0 {
            activityText = "Minor-Moderate Storm (G1-G2)"
        } else if kp >= 4.0 {
            activityText = "Active Auroral Backscatter"
        } else {
            activityText = "Quiet / Normal"
        }

        return AuroralOvalBoundary(
            northernOuterRing: northOuter,
            northernInnerRing: northInner,
            southernOuterRing: southOuter,
            southernInnerRing: southInner,
            equatorwardEdgeGeomagneticLat: equatorwardMagLat,
            kpIndex: kp,
            auroralActivityLevel: activityText
        )
    }

    private static func generateOvalRing(
        pole: GeoCoordinate,
        magLat: Double,
        sunLongitude: Double,
        isNorth: Bool,
        stepDeg: Double
    ) -> [GeoCoordinate] {
        var coords: [GeoCoordinate] = []

        // Colatitude in geomagnetic coordinates
        let colat = 90.0 - magLat
        let poleLatRad = pole.latitude * .pi / 180.0
        let poleLonRad = pole.longitude * .pi / 180.0

        var azimuth = 0.0
        while azimuth <= 360.0 {
            let azRad = azimuth * .pi / 180.0

            // Day-night eccentricity offset: widen towards midnight meridian (sunLon + 180°)
            let localLongitude = (pole.longitude + azimuth).truncatingRemainder(dividingBy: 360.0)
            let solarAngle = abs((localLongitude - sunLongitude).truncatingRemainder(dividingBy: 360.0))
            let isMidnightSector = solarAngle > 90.0
            let eccentricityOffset = isMidnightSector ? 2.5 * sin((solarAngle - 90.0) * .pi / 180.0) : -1.0

            let effectiveColatRad = (colat + eccentricityOffset) * .pi / 180.0

            // Spherical coordinate transformation from Geomagnetic to Geographic
            let sinLat = sin(poleLatRad) * cos(effectiveColatRad) +
                         cos(poleLatRad) * sin(effectiveColatRad) * cos(azRad)
            let geoLatRad = asin(max(-1.0, min(1.0, sinLat)))

            let y = sin(azRad) * sin(effectiveColatRad) * cos(poleLatRad)
            let x = cos(effectiveColatRad) - sin(poleLatRad) * sin(geoLatRad)
            let deltaLonRad = atan2(y, x)
            var geoLonDeg = (poleLonRad + deltaLonRad) * 180.0 / .pi

            if geoLonDeg > 180.0 { geoLonDeg -= 360.0 }
            if geoLonDeg < -180.0 { geoLonDeg += 360.0 }

            let targetLat = isNorth ? geoLatRad * 180.0 / .pi : -abs(geoLatRad * 180.0 / .pi)
            coords.append(GeoCoordinate(latitude: targetLat, longitude: geoLonDeg))

            azimuth += stepDeg
        }

        return coords
    }
}
