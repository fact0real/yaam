//
//  HFPointToPointPropagationEngine.swift
//  YAAM
//
//  Real-Time VOACAP-Style Point-to-Point HF Circuit Propagation Engine
//  Predicts 24-hour UTC circuit reliability, SNR, MUF, and LUF for DE-to-DX path across all amateur bands
//  (160m through 6m) based on Solar Flux (SFI), path geometry, D-region absorption, and Greyline overlap.
//

import Combine
import Foundation
import SwiftUI

public struct PropagationCell: Equatable, Sendable, Identifiable {
    public var id: String { "\(band)_\(hourUTC)" }
    public let band: String          // "160m", "80m", "40m", "20m", etc.
    public let frequencyMHz: Double  // 1.8, 3.5, 7.0, 14.0, etc.
    public let hourUTC: Int          // 0 .. 23
    public let reliabilityPercent: Int // 0 .. 100%
    public let snrDB: Double         // Expected signal-to-noise ratio in dB
    public let condition: BandConditionRating

    public enum BandConditionRating: String, Sendable {
        case open = "Open"
        case marginal = "Fair"
        case closed = "Poor"

        public var color: Color {
            switch self {
            case .open: return .green
            case .marginal: return .yellow
            case .closed: return Color.red.opacity(0.4)
            }
        }
    }
}

public struct PathPropagationPrediction: Equatable, Sendable, Identifiable {
    public var id: String { "\(band)_\(String(format: "%.1f", frequencyMHz))" }
    public let band: String
    public let frequencyMHz: Double
    public let reliabilityPercent: Int
    public let snrDB: Double
    public let condition: PropagationCell.BandConditionRating
    public let pathMUF: Double
    public let pathLUF: Double
    public let optimalFOT: Double
    public let bestBandNow: String
    public let isGreylineDuct: Bool
    public let advice: String
    public let hourlyTimeline: [PropagationCell]
}

public struct HFCircuitMatrix: Equatable, Sendable {
    public let deCoordinate: GeoCoordinate
    public let dxCoordinate: GeoCoordinate
    public let dxCallsign: String
    public let distanceKm: Double
    public let shortPathBearingDeg: Double
    public let solarFlux: Double
    public let kpIndex: Double
    public let bands: [String]
    public let cellsByBand: [String: [PropagationCell]]
    public let bestBandNow: String
    public let currentPathMUF: Double
    public let currentPathLUF: Double
    public let currentFOT: Double
    public let openBandsNow: [String]
    public let peakOpenHourUTC: Int
}

@MainActor
public final class HFPointToPointPropagationEngine: ObservableObject {
    public static let shared = HFPointToPointPropagationEngine()

    @Published public private(set) var activeMatrix: HFCircuitMatrix?
    @Published public private(set) var isCalculating: Bool = false

    nonisolated public static let supportedBands: [(name: String, mhz: Double)] = [
        ("160m", 1.8),
        ("80m", 3.5),
        ("60m", 5.3),
        ("40m", 7.0),
        ("30m", 10.1),
        ("20m", 14.0),
        ("17m", 18.1),
        ("15m", 21.0),
        ("12m", 24.9),
        ("10m", 28.5),
        ("6m", 50.1)
    ]

    private init() {}

    /// Calculates full 24-hour DE-to-DX propagation matrix asynchronously and updates the activeMatrix
    public func calculateCircuit(
        de: GeoCoordinate,
        dx: GeoCoordinate,
        dxCallsign: String,
        sfi: Double = 145.0,
        kp: Double = 2.0,
        date: Date = Date()
    ) {
        isCalculating = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let matrix = Self.calculateCircuitMatrix(
                de: de,
                dx: dx,
                dxCallsign: dxCallsign,
                sfi: sfi,
                kp: kp,
                date: date
            )

            DispatchQueue.main.async {
                self?.activeMatrix = matrix
                self?.isCalculating = false
            }
        }
    }

    /// Thread-safe pure functional calculation of the 24-hour circuit matrix
    nonisolated public static func calculateCircuitMatrix(
        de: GeoCoordinate,
        dx: GeoCoordinate,
        dxCallsign: String,
        sfi: Double = 145.0,
        kp: Double = 2.0,
        date: Date = Date()
    ) -> HFCircuitMatrix {
        let distKm = GeodesicMath.distanceKm(from: de, to: dx)
        let spBearing = GeodesicMath.initialBearing(from: de, to: dx)
        let midpoints = GeodesicMath.greatCircleWaypoints(from: de, to: dx, count: 5)
        let midPoint = midpoints.count >= 3 ? midpoints[midpoints.count / 2] : de

        var cellsByBand: [String: [PropagationCell]] = [:]
        var bestBand = "20m"
        var highestNowScore = -1
        var openBands: [String] = []

        let currentHourUTC = Calendar(identifier: .gregorian).component(.hour, from: date)
        var hourlyTotalScores = Array(repeating: 0, count: 24)

        for (bandName, freqMHz) in supportedBands {
            var bandCells: [PropagationCell] = []

            for hour in 0..<24 {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(secondsFromGMT: 0)!
                var comps = cal.dateComponents([.year, .month, .day], from: date)
                comps.hour = hour
                comps.minute = 30
                let simDate = cal.date(from: comps) ?? date

                let rel = estimateReliability(
                    freqMHz: freqMHz,
                    distanceKm: distKm,
                    deCoord: de,
                    dxCoord: dx,
                    midCoord: midPoint,
                    sfi: sfi,
                    kp: kp,
                    simDate: simDate
                )

                hourlyTotalScores[hour] += rel

                let snr = Double(rel - 50) * 0.4
                let condition: PropagationCell.BandConditionRating
                if rel >= 65 {
                    condition = .open
                } else if rel >= 35 {
                    condition = .marginal
                } else {
                    condition = .closed
                }

                let cell = PropagationCell(
                    band: bandName,
                    frequencyMHz: freqMHz,
                    hourUTC: hour,
                    reliabilityPercent: rel,
                    snrDB: snr,
                    condition: condition
                )
                bandCells.append(cell)

                if hour == currentHourUTC {
                    if rel >= 65 {
                        openBands.append(bandName)
                    }
                    if rel > highestNowScore {
                        highestNowScore = rel
                        bestBand = bandName
                    }
                }
            }
            cellsByBand[bandName] = bandCells
        }

        // True peak open hour across all bands
        var peakHour = 14
        var maxHourlyScore = -1
        for (h, score) in hourlyTotalScores.enumerated() {
            if score > maxHourlyScore {
                maxHourlyScore = score
                peakHour = h
            }
        }

        let freqs = calculatePathFrequencies(
            distanceKm: distKm,
            deCoord: de,
            dxCoord: dx,
            midCoord: midPoint,
            sfi: sfi,
            at: date
        )

        return HFCircuitMatrix(
            deCoordinate: de,
            dxCoordinate: dx,
            dxCallsign: dxCallsign,
            distanceKm: distKm,
            shortPathBearingDeg: spBearing,
            solarFlux: sfi,
            kpIndex: kp,
            bands: supportedBands.map(\.name),
            cellsByBand: cellsByBand,
            bestBandNow: bestBand,
            currentPathMUF: freqs.muf,
            currentPathLUF: freqs.luf,
            currentFOT: freqs.fot,
            openBandsNow: openBands,
            peakOpenHourUTC: peakHour
        )
    }

    /// Fast synchronous prediction for a specific path, band, and time
    nonisolated public static func predictPath(
        de: GeoCoordinate,
        dx: GeoCoordinate,
        band: String,
        frequencyMHz: Double? = nil,
        sfi: Double = 145.0,
        kp: Double = 2.0,
        date: Date = Date()
    ) -> PathPropagationPrediction {
        let freq = frequencyMHz ?? frequency(for: band)
        let distKm = GeodesicMath.distanceKm(from: de, to: dx)
        let midpoints = GeodesicMath.greatCircleWaypoints(from: de, to: dx, count: 5)
        let midPoint = midpoints.count >= 3 ? midpoints[midpoints.count / 2] : de

        let freqs = calculatePathFrequencies(
            distanceKm: distKm,
            deCoord: de,
            dxCoord: dx,
            midCoord: midPoint,
            sfi: sfi,
            at: date
        )

        let rel = estimateReliability(
            freqMHz: freq,
            distanceKm: distKm,
            deCoord: de,
            dxCoord: dx,
            midCoord: midPoint,
            sfi: sfi,
            kp: kp,
            simDate: date
        )

        let snr = Double(rel - 50) * 0.4
        let condition: PropagationCell.BandConditionRating
        if rel >= 65 {
            condition = .open
        } else if rel >= 35 {
            condition = .marginal
        } else {
            condition = .closed
        }

        // Determine best band right now
        var bestBand = "20m"
        var bestRel = -1
        for (bName, bFreq) in supportedBands {
            let r = estimateReliability(
                freqMHz: bFreq,
                distanceKm: distKm,
                deCoord: de,
                dxCoord: dx,
                midCoord: midPoint,
                sfi: sfi,
                kp: kp,
                simDate: date
            )
            if r > bestRel {
                bestRel = r
                bestBand = bName
            }
        }

        let isGreyline = SolarEphemeris.isPathInGreyline(from: de, to: dx, at: date).isInGreyline

        // Tactical advice string
        let advice: String
        if condition == .open {
            if isGreyline {
                advice = "⚡️ GREYLINE DUCT OPEN: Excellent low-band ducting with minimal D-layer absorption."
            } else {
                advice = "STRONG OPENING: Frequency (\(String(format: "%.1f", freq)) MHz) is near optimum FOT (\(String(format: "%.1f", freqs.fot)) MHz)."
            }
        } else if condition == .marginal {
            if freq > freqs.muf {
                advice = "MARGINAL: Operating above path MUF (\(String(format: "%.1f", freqs.muf)) MHz). Try \(bestBand)."
            } else {
                advice = "FAIR: Elevated ionospheric absorption or mild geomagnetic activity."
            }
        } else {
            if freq > freqs.muf {
                advice = "CLOSED: Signal penetrates ionosphere into space. MUF is \(String(format: "%.1f", freqs.muf)) MHz. Best band is \(bestBand)."
            } else {
                advice = "CLOSED: Heavy D-layer daytime absorption (LUF is \(String(format: "%.1f", freqs.luf)) MHz). Try a higher band like \(bestBand)."
            }
        }

        // Calculate 24-hour timeline for this specific band
        var timeline: [PropagationCell] = []
        for hour in 0..<24 {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            var comps = cal.dateComponents([.year, .month, .day], from: date)
            comps.hour = hour
            comps.minute = 30
            let simDate = cal.date(from: comps) ?? date

            let hRel = estimateReliability(
                freqMHz: freq,
                distanceKm: distKm,
                deCoord: de,
                dxCoord: dx,
                midCoord: midPoint,
                sfi: sfi,
                kp: kp,
                simDate: simDate
            )
            let hSnr = Double(hRel - 50) * 0.4
            let hCond: PropagationCell.BandConditionRating = hRel >= 65 ? .open : (hRel >= 35 ? .marginal : .closed)

            timeline.append(PropagationCell(
                band: band,
                frequencyMHz: freq,
                hourUTC: hour,
                reliabilityPercent: hRel,
                snrDB: hSnr,
                condition: hCond
            ))
        }

        return PathPropagationPrediction(
            band: band,
            frequencyMHz: freq,
            reliabilityPercent: rel,
            snrDB: snr,
            condition: condition,
            pathMUF: freqs.muf,
            pathLUF: freqs.luf,
            optimalFOT: freqs.fot,
            bestBandNow: bestBand,
            isGreylineDuct: isGreyline,
            advice: advice,
            hourlyTimeline: timeline
        )
    }

    // MARK: - Frequency & Physics Helpers

    nonisolated public static func frequency(for band: String) -> Double {
        let clean = band.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch clean {
        case "160m", "160": return 1.8
        case "80m", "80": return 3.5
        case "60m", "60": return 5.3
        case "40m", "40": return 7.0
        case "30m", "30": return 10.1
        case "20m", "20": return 14.0
        case "17m", "17": return 18.1
        case "15m", "15": return 21.0
        case "12m", "12": return 24.9
        case "10m", "10": return 28.5
        case "6m", "6": return 50.1
        default: return 14.0
        }
    }

    nonisolated public static func calculatePathFrequencies(
        distanceKm: Double,
        deCoord: GeoCoordinate,
        dxCoord: GeoCoordinate,
        midCoord: GeoCoordinate,
        sfi: Double,
        at date: Date
    ) -> (muf: Double, luf: Double, fot: Double) {
        let deSunEl = SolarEphemeris.solarElevation(for: deCoord, at: date)
        let dxSunEl = SolarEphemeris.solarElevation(for: dxCoord, at: date)
        let midSunEl = SolarEphemeris.solarElevation(for: midCoord, at: date)

        let zenithFactor = max(0.2, (midSunEl + 90.0) / 180.0)
        let baseFoF2 = 3.0 + 0.045 * sfi * sqrt(zenithFactor)

        let hopDist = min(3000.0, distanceKm)
        let mFactor = 1.0 + 2.5 * (hopDist / 3000.0)
        let pathMUF = max(4.0, baseFoF2 * mFactor)

        let avgSunEl = (deSunEl + dxSunEl + 2.0 * midSunEl) / 4.0
        let daylightFraction = max(0.0, avgSunEl / 90.0)
        let baseLUF = max(1.5, 1.8 + (daylightFraction * 12.0))

        let optimalFOT = max(baseLUF, pathMUF * 0.85)

        return (pathMUF, baseLUF, optimalFOT)
    }

    // MARK: - ITU / VOACAP Physics Approximation Model

    nonisolated public static func estimateReliability(
        freqMHz: Double,
        distanceKm: Double,
        deCoord: GeoCoordinate,
        dxCoord: GeoCoordinate,
        midCoord: GeoCoordinate,
        sfi: Double,
        kp: Double,
        simDate: Date
    ) -> Int {
        let deSunEl = SolarEphemeris.solarElevation(for: deCoord, at: simDate)
        let dxSunEl = SolarEphemeris.solarElevation(for: dxCoord, at: simDate)
        let midSunEl = SolarEphemeris.solarElevation(for: midCoord, at: simDate)

        let zenithFactor = max(0.2, (midSunEl + 90.0) / 180.0)
        let baseFoF2 = 3.0 + 0.045 * sfi * sqrt(zenithFactor)

        let hopDist = min(3000.0, distanceKm)
        let mFactor = 1.0 + 2.5 * (hopDist / 3000.0)
        let pathMUF = max(4.0, baseFoF2 * mFactor)

        let avgSunEl = (deSunEl + dxSunEl + 2.0 * midSunEl) / 4.0
        let daylightFraction = max(0.0, avgSunEl / 90.0)
        let baseLUF = max(1.5, 1.8 + (daylightFraction * 12.0))

        // Greyline enhancement using exact path coincidence
        let (isGreylineDuct, ductFactor) = SolarEphemeris.isPathInGreyline(from: deCoord, to: dxCoord, at: simDate)
        let greylineBonus = isGreylineDuct ? (20.0 + ductFactor * 15.0) : 0.0

        // Geomagnetic storm penalty (Kp > 3 degrades polar/high-latitude paths)
        let geomagPenalty = kp > 3.0 ? (kp - 3.0) * 12.0 : 0.0

        var score: Double = 0.0

        // Special handling for 160m (1.8 MHz)
        if freqMHz < 2.5 {
            if daylightFraction > 0.10 {
                // Extreme D-region absorption during daylight
                score = max(5.0, 20.0 - daylightFraction * 50.0)
            } else {
                // Strong nighttime TopBand reflection
                score = 72.0 + (avgSunEl < -15.0 ? 18.0 : 5.0)
            }
        } else if freqMHz >= 45.0 { // 6m Magic Band (50 MHz)
            let month = Calendar(identifier: .gregorian).component(.month, from: simDate)
            let isNorthern = (deCoord.latitude + dxCoord.latitude) / 2.0 >= 0
            let isSummerEs = isNorthern ? (month >= 5 && month <= 8) : (month == 11 || month == 12 || month == 1 || month == 2)
            let isEsTime = (avgSunEl >= -6.0 && avgSunEl <= 80.0)

            if sfi >= 160.0 && (pathMUF >= 38.0 || isSummerEs) {
                // Peak solar cycle F2 propagation or intense Summer Sporadic-E
                score = 65.0 + min(25.0, (sfi - 160.0) * 0.6)
            } else if isSummerEs && isEsTime {
                // Classic summer daytime Sporadic-E
                score = 45.0 + (sfi > 130.0 ? 15.0 : 5.0)
            } else {
                // Baseline winter/off-season 6m scatter
                score = max(5.0, 10.0 + (sfi > 140.0 ? 10.0 : 0.0))
            }
        } else {
            // Standard HF bands (80m through 10m)
            if freqMHz > pathMUF {
                let overshoot = freqMHz - pathMUF
                score = max(0.0, 60.0 - overshoot * 18.0)
            } else if freqMHz < baseLUF {
                let undershoot = baseLUF - freqMHz
                score = max(0.0, 70.0 - undershoot * 15.0)
            } else {
                let windowSpan = max(1.0, pathMUF - baseLUF)
                let relativePosition = (freqMHz - baseLUF) / windowSpan
                let optimumScore = 1.0 - abs(relativePosition - 0.75)
                score = 65.0 + optimumScore * 30.0
            }

            // Nighttime bonus for low bands (80m, 60m, 40m)
            if freqMHz <= 7.5 && avgSunEl < -10.0 {
                score += 20.0
            }
        }

        score += greylineBonus
        score -= geomagPenalty

        return Int(max(5.0, min(99.0, score)))
    }
}
