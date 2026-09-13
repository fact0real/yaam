//
//  DRAPAbsorptionEngine.swift
//  YAAM
//
//  Real-time NOAA D-Region Absorption Prediction (D-RAP) Engine
//  Models solar X-ray flare shortwave fadeouts (SWF) and Polar Cap Absorption (PCA)
//  across the sunlit hemisphere and generates vector coordinates for map overlay.
//

import Combine
import Foundation
import SwiftUI

public struct DRAPPoint: Equatable, Sendable {
    public let coordinate: GeoCoordinate
    public let absorbedFrequencyMHz: Double
    public let absorptionDB: Double
}

public struct DRAPSnapshot: Equatable, Sendable {
    public let subsolarHAFMHz: Double       // Highest Absorbed Frequency at subsolar point (MHz)
    public let maxAbsorptionDB: Double      // 10 MHz absorption at subsolar point in dB
    public let flareClass: String           // e.g. "X1.2", "M3.5", "C2.1", "Quiet"
    public let polarCapAbsorptionDB: Double
    public let affectedPoints: [DRAPPoint]
    public let isBlackoutActive: Bool

    public var radioBlackoutScale: String {
        if subsolarHAFMHz >= 30.0 { return "R5 (Extreme Blackout)" }
        if subsolarHAFMHz >= 20.0 { return "R4 (Severe Blackout)" }
        if subsolarHAFMHz >= 10.0 { return "R3 (Strong Blackout)" }
        if subsolarHAFMHz >= 5.0 { return "R2 (Moderate Blackout)" }
        if subsolarHAFMHz >= 2.5 { return "R1 (Minor Fadeout)" }
        return "R0 (Normal / Quiet)"
    }
}

@MainActor
public final class DRAPAbsorptionEngine: ObservableObject {
    public static let shared = DRAPAbsorptionEngine()

    @Published public private(set) var snapshot: DRAPSnapshot
    @Published public private(set) var isFetching: Bool = false
    @Published public private(set) var lastUpdatedDate: Date?

    private var refreshCancellable: AnyCancellable?

    private init() {
        // Initial quiet snapshot
        self.snapshot = Self.calculateDrap(xrayFluxWattsM2: 1e-6, flareClass: "Quiet", protonFlux: 1.0)
        startAutoRefresh()
    }

    private func startAutoRefresh() {
        // Refresh every 5 minutes from NOAA SWPC
        refreshCancellable = Timer.publish(every: 300.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchLatestGOESXrayFlux()
            }

        fetchLatestGOESXrayFlux()
    }

    public func updateFlareTelemetry(flareClass: String, fluxWattsM2: Double, protonFlux: Double = 1.0) {
        self.snapshot = Self.calculateDrap(xrayFluxWattsM2: fluxWattsM2, flareClass: flareClass, protonFlux: protonFlux)
        self.lastUpdatedDate = Date()
    }

    public var maxHAFMHz: Double {
        snapshot.subsolarHAFMHz
    }

    public var flareClassification: String {
        snapshot.flareClass
    }

    public var polarCapAbsorptionDB: Double {
        snapshot.polarCapAbsorptionDB
    }

    public struct BlackoutLevel: Equatable {
        public let rScale: Int
        public let title: String
        public let color: Color

        public init(rScale: Int, title: String, color: Color) {
            self.rScale = rScale
            self.title = title
            self.color = color
        }
    }

    public var blackoutLevel: BlackoutLevel {
        let haf = snapshot.subsolarHAFMHz
        if haf >= 30.0 {
            return BlackoutLevel(rScale: 5, title: "R5 Extreme", color: .purple)
        } else if haf >= 20.0 {
            return BlackoutLevel(rScale: 4, title: "R4 Severe", color: .red)
        } else if haf >= 10.0 {
            return BlackoutLevel(rScale: 3, title: "R3 Strong", color: .red)
        } else if haf >= 5.0 {
            return BlackoutLevel(rScale: 2, title: "R2 Moderate", color: .orange)
        } else if haf >= 2.5 {
            return BlackoutLevel(rScale: 1, title: "R1 Minor", color: .yellow)
        } else {
            return BlackoutLevel(rScale: 0, title: "R0 Quiet", color: .green)
        }
    }

    // MARK: - NOAA SWPC Real-Time Fetch

    public func fetchLatestGOESXrayFlux() {
        guard !isFetching else { return }
        isFetching = true

        guard let url = URL(string: "https://services.swpc.noaa.gov/json/goes/primary/xrays-6-hour.json") else {
            isFetching = false
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async { self.isFetching = false }
            }

            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let lastRecord = json.last,
                  let flux = lastRecord["flux"] as? Double else {
                return
            }

            let flareName = Self.flareClassString(for: flux)
            DispatchQueue.main.async {
                self.updateFlareTelemetry(flareClass: flareName, fluxWattsM2: flux)
            }
        }.resume()
    }

    // MARK: - D-RAP Physics Model (Empirical SWPC Formulation)

    public static func calculateDrap(
        xrayFluxWattsM2: Double,
        flareClass: String,
        protonFlux: Double = 1.0,
        date: Date = Date()
    ) -> DRAPSnapshot {
        // Subsolar Highest Absorbed Frequency (HAF in MHz):
        // HAF = 10 * sqrt(Flux / 1e-4) MHz
        let clampedFlux = max(1e-8, xrayFluxWattsM2)
        let subsolarHAF = min(40.0, 10.0 * sqrt(clampedFlux / 1e-4))
        let maxAbsorption10MHzDB = min(45.0, 3.0 * sqrt(clampedFlux / 1e-4) * 10.0)

        let isBlackout = subsolarHAF >= 4.0 // Absorbs 80m/40m or higher

        // Polar Cap Absorption (PCA) from proton flux (>10 MeV)
        let pcaDB = protonFlux > 10.0 ? min(25.0, 0.15 * sqrt(protonFlux)) : 0.0

        var points: [DRAPPoint] = []

        // Generate coarse grid of daylight points with non-zero absorption
        for lat in stride(from: -80.0, through: 80.0, by: 15.0) {
            for lon in stride(from: -180.0, through: 180.0, by: 15.0) {
                let coord = GeoCoordinate(latitude: lat, longitude: lon)
                let elev = SolarEphemeris.solarElevation(for: coord, at: date)

                if elev > 0.0 {
                    // Solar zenith angle chi = 90° - elev
                    let chiRad = (90.0 - elev) * .pi / 180.0
                    let cosChi = max(0.0, cos(chiRad))
                    let localHAF = subsolarHAF * pow(cosChi, 0.75)
                    let localDB = maxAbsorption10MHzDB * pow(cosChi, 0.75)

                    if localHAF >= 1.5 {
                        points.append(DRAPPoint(coordinate: coord, absorbedFrequencyMHz: localHAF, absorptionDB: localDB))
                    }
                }
            }
        }

        return DRAPSnapshot(
            subsolarHAFMHz: subsolarHAF,
            maxAbsorptionDB: maxAbsorption10MHzDB,
            flareClass: flareClass,
            polarCapAbsorptionDB: pcaDB,
            affectedPoints: points,
            isBlackoutActive: isBlackout
        )
    }

    public nonisolated static func flareClassString(for flux: Double) -> String {
        if flux >= 1e-4 {
            return String(format: "X%.1f", flux / 1e-4)
        } else if flux >= 1e-5 {
            return String(format: "M%.1f", flux / 1e-5)
        } else if flux >= 1e-6 {
            return String(format: "C%.1f", flux / 1e-6)
        } else if flux >= 1e-7 {
            return String(format: "B%.1f", flux / 1e-7)
        } else {
            return "Quiet"
        }
    }
}
