//
//  APRSBalloonTrackingEngine.swift
//  YAAM
//
//  Real-time APRS & High-Altitude Balloon (HAB) Tracking Engine
//  Tracks meteorological and amateur radio balloons, packet telemetry,
//  altitude ascent/descent rates, and renders drift trajectories on world maps.
//

import Combine
import Foundation

public struct APRSBalloon: Identifiable, Equatable, Sendable {
    public var id: String { callsign }
    public let callsign: String
    public let name: String
    public var coordinate: GeoCoordinate
    public var altitudeMeters: Double
    public var verticalSpeedMps: Double      // m/s (positive = climbing, negative = descent/burst)
    public var speedKmH: Double
    public var courseDeg: Double
    public var lastPacketDate: Date
    public var flightTrail: [GeoCoordinate]
    public var temperatureC: Double?
    public var batteryVoltage: Double?

    public var altitudeFeet: Double {
        altitudeMeters * 3.28084
    }

    public var altitudeFormatted: String {
        String(format: "%.0f m (%.0f ft)", altitudeMeters, altitudeFeet)
    }

    public var verticalSpeedFormatted: String {
        String(format: "%+.1f m/s", verticalSpeedMps)
    }

    public var gridLocator: String {
        GeodesicMath.maidenheadLocator(from: coordinate)
    }

    public enum FlightPhase: String, Sendable {
        case ascending = "Ascending"
        case cruising = "Float Level"
        case descending = "Parachute Descent"
    }

    public var flightPhase: FlightPhase {
        if verticalSpeedMps > 1.0 {
            return .ascending
        } else if verticalSpeedMps < -1.0 {
            return .descending
        } else {
            return .cruising
        }
    }

    public var speedKmh: Double {
        speedKmH
    }

    public var trackHistory: [GeoCoordinate] {
        flightTrail
    }

    public var comment: String {
        name
    }

    public var flightStatus: String {
        if verticalSpeedMps > 1.0 {
            return "Ascending (+ \(String(format: "%.1f", verticalSpeedMps)) m/s)"
        } else if verticalSpeedMps < -1.0 {
            return "Parachute Descent (\(String(format: "%.1f", verticalSpeedMps)) m/s)"
        } else {
            return "Floating / Float Level"
        }
    }
}

@MainActor
public final class APRSBalloonTrackingEngine: ObservableObject {
    public static let shared = APRSBalloonTrackingEngine()

    @Published public private(set) var balloons: [APRSBalloon] = []
    @Published public var selectedBalloonCallsign: String = "W3BC-11"
    @Published public var isTrackingEnabled: Bool = true

    public var trackedBalloons: [APRSBalloon] {
        balloons
    }

    public func selectBalloon(callsign: String) {
        selectedBalloonCallsign = callsign
    }

    private var driftTimer: AnyCancellable?

    private init() {
        self.balloons = Self.bundledInitialBalloons()
        startDriftSimulationLoop()
    }

    public var selectedBalloon: APRSBalloon? {
        balloons.first { $0.callsign == selectedBalloonCallsign }
    }

    public func addOrUpdateBalloon(
        callsign: String,
        name: String,
        coordinate: GeoCoordinate,
        altitudeMeters: Double,
        verticalSpeedMps: Double,
        speedKmH: Double,
        courseDeg: Double,
        tempC: Double? = nil
    ) {
        if let idx = balloons.firstIndex(where: { $0.callsign == callsign }) {
            var b = balloons[idx]
            b.coordinate = coordinate
            b.altitudeMeters = altitudeMeters
            b.verticalSpeedMps = verticalSpeedMps
            b.speedKmH = speedKmH
            b.courseDeg = courseDeg
            b.lastPacketDate = Date()
            b.temperatureC = tempC
            b.flightTrail.append(coordinate)
            if b.flightTrail.count > 50 {
                b.flightTrail.removeFirst()
            }
            balloons[idx] = b
        } else {
            let newB = APRSBalloon(
                callsign: callsign,
                name: name,
                coordinate: coordinate,
                altitudeMeters: altitudeMeters,
                verticalSpeedMps: verticalSpeedMps,
                speedKmH: speedKmH,
                courseDeg: courseDeg,
                lastPacketDate: Date(),
                flightTrail: [coordinate],
                temperatureC: tempC,
                batteryVoltage: 3.7
            )
            balloons.append(newB)
        }
    }

    // MARK: - Atmospheric Jet Stream Drift Loop

    private func startDriftSimulationLoop() {
        // Drift balloons slightly every 5 seconds along course vector
        driftTimer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.advanceBalloonPositions()
            }
    }

    private func advanceBalloonPositions() {
        for i in 0..<balloons.count {
            var b = balloons[i]

            // 5 seconds drift distance (km)
            let dtHours = 5.0 / 3600.0
            let distKm = b.speedKmH * dtHours

            // Calculate next lat/lon
            let radBearing = b.courseDeg * .pi / 180.0
            let angDist = distKm / GeodesicMath.earthRadiusKm
            let lat1 = b.coordinate.latitude * .pi / 180.0
            let lon1 = b.coordinate.longitude * .pi / 180.0

            let lat2 = asin(sin(lat1) * cos(angDist) + cos(lat1) * sin(angDist) * cos(radBearing))
            let lon2 = lon1 + atan2(sin(radBearing) * sin(angDist) * cos(lat1), cos(angDist) - sin(lat1) * sin(lat2))

            let newCoord = GeoCoordinate(latitude: lat2 * 180.0 / .pi, longitude: lon2 * 180.0 / .pi)
            b.coordinate = newCoord
            b.altitudeMeters += b.verticalSpeedMps * 5.0

            // Burst check at ~34,000m
            if b.altitudeMeters >= 34000.0 && b.verticalSpeedMps > 0 {
                b.verticalSpeedMps = -8.5 // Parachute deployment!
            } else if b.altitudeMeters <= 500.0 && b.verticalSpeedMps < 0 {
                b.verticalSpeedMps = 3.2 // Re-launch simulation
                b.altitudeMeters = 800.0
            }

            b.flightTrail.append(newCoord)
            if b.flightTrail.count > 40 {
                b.flightTrail.removeFirst()
            }
            balloons[i] = b
        }
    }

    public static func bundledInitialBalloons() -> [APRSBalloon] {
        [
            APRSBalloon(
                callsign: "W3BC-11",
                name: "NASA Jet Stream HAB-4",
                coordinate: GeoCoordinate(latitude: 38.8951, longitude: -77.0364),
                altitudeMeters: 24500.0,
                verticalSpeedMps: 4.2,
                speedKmH: 142.0,
                courseDeg: 82.0,
                lastPacketDate: Date(),
                flightTrail: [
                    GeoCoordinate(latitude: 38.60, longitude: -78.20),
                    GeoCoordinate(latitude: 38.75, longitude: -77.60),
                    GeoCoordinate(latitude: 38.89, longitude: -77.03)
                ],
                temperatureC: -48.5,
                batteryVoltage: 3.65
            ),
            APRSBalloon(
                callsign: "HAB-IRAN-1",
                name: "Alborz Stratosphere Tracker",
                coordinate: GeoCoordinate(latitude: 35.80, longitude: 51.50),
                altitudeMeters: 21800.0,
                verticalSpeedMps: 3.8,
                speedKmH: 88.0,
                courseDeg: 105.0,
                lastPacketDate: Date(),
                flightTrail: [
                    GeoCoordinate(latitude: 35.70, longitude: 51.20),
                    GeoCoordinate(latitude: 35.75, longitude: 51.35),
                    GeoCoordinate(latitude: 35.80, longitude: 51.50)
                ],
                temperatureC: -42.0,
                batteryVoltage: 3.72
            )
        ]
    }
}
