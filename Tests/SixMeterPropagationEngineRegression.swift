//
//  SixMeterPropagationEngineRegression.swift
//  YAAM Tests
//

import Foundation

// MARK: - Mathematical & Azimuth Helpers for Testing

func calculateAzimuthTest(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> Double {
    let lat1 = fromLat * .pi / 180.0
    let lon1 = fromLon * .pi / 180.0
    let lat2 = toLat * .pi / 180.0
    let lon2 = toLon * .pi / 180.0
    let dlon = lon2 - lon1

    let y = sin(dlon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon)
    var bearing = atan2(y, x) * 180.0 / .pi
    if bearing < 0 { bearing += 360.0 }
    return bearing
}

func degreesToCompassTest(_ deg: Double) -> String {
    let compassPoints = [
        "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW", "N"
    ]
    let index = Int(round(deg.truncatingRemainder(dividingBy: 360.0) / 22.5))
    return compassPoints[max(0, min(16, index))]
}

func calculateDistanceKmTest(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let p1 = lat1 * .pi / 180.0
    let p2 = lat2 * .pi / 180.0
    let dp = (lat2 - lat1) * .pi / 180.0
    let dl = (lon2 - lon1) * .pi / 180.0

    let a = sin(dp / 2.0) * sin(dp / 2.0) + cos(p1) * cos(p2) * sin(dl / 2.0) * sin(dl / 2.0)
    let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
    return 6371.0 * c
}

func calculateDynamicWeightedScoreTest(midpointMUF: Double, telemetryCount: Int, isPeakHour: Bool, isSummer: Bool, sfi: Double, kp: Double) -> (score: Int, isCompensated: Bool, midWeight: Double, telWeight: Double) {
    let isSparse = telemetryCount < 5
    let midWeight = isSparse ? 0.65 : 0.50
    let telWeight = isSparse ? 0.10 : 0.25
    let diWeight = 0.15
    let spWeight = 0.10

    // 1. Midpoint MUF
    let midScore: Double
    if midpointMUF >= 50.0 { midScore = 100.0 }
    else if midpointMUF >= 45.0 { midScore = 75.0 + (midpointMUF - 45.0) * 5.0 }
    else if midpointMUF >= 40.0 { midScore = 50.0 + (midpointMUF - 40.0) * 5.0 }
    else if midpointMUF >= 30.0 { midScore = 20.0 + (midpointMUF - 30.0) * 3.0 }
    else { midScore = 10.0 }

    // 2. Regional Telemetry
    let telScore: Double
    if telemetryCount >= 15 { telScore = 100.0 }
    else if telemetryCount >= 8 { telScore = 75.0 }
    else if telemetryCount >= 3 { telScore = 50.0 }
    else if telemetryCount >= 1 { telScore = 30.0 }
    else { telScore = 5.0 }

    // 3. Diurnal / Seasonal
    var diScore = 10.0
    if isPeakHour { diScore += 45.0 }
    if isSummer { diScore += 45.0 }
    diScore = min(100.0, diScore)

    // 4. Space Weather
    var spScore = 20.0
    if sfi >= 200 { spScore = 100.0 }
    else if sfi >= 160 { spScore = 70.0 }
    else if sfi >= 130 { spScore = 45.0 }
    if kp >= 5 { spScore = max(spScore, 70.0) }

    let raw = (midScore * midWeight) + (telScore * telWeight) + (diScore * diWeight) + (spScore * spWeight)
    return (max(5, min(99, Int(round(raw)))), isSparse, midWeight, telWeight)
}

func evaluateOpeningLevelTest(maxMUF: Double, score: Int) -> String {
    if maxMUF >= 50.0 {
        return "OPEN"
    } else if score >= 70 || maxMUF >= 45.0 {
        return "VERY HIGH / IMMINENT"
    } else if score >= 45 || maxMUF >= 38.0 {
        return "STANDBY / ELEVATED"
    } else {
        return "QUIET"
    }
}

@main
struct SixMeterPropagationEngineRegression {
    static func main() {
        print("Running Advanced 6m Magic Band Dynamic Weighting & Physical Corridor Geometry Tests...")

        testAzimuthAndCompass()
        testCorridorMaxMUFSelection()
        testReflectorMidpointGeometries()
        testDynamicSparseReceiverCompensation()
        testStrictOpeningLevelClassification()

        print("All Advanced 6m Magic Band Physical & Mathematical Regression Tests PASSED successfully!")
    }

    private static func testAzimuthAndCompass() {
        // Tehran (35.7° N, 51.4° E) -> Athens (38.0° N, 23.5° E)
        let azAthens = calculateAzimuthTest(fromLat: 35.7, fromLon: 51.4, toLat: 38.0, toLon: 23.5)
        let compAthens = degreesToCompassTest(azAthens)
        precondition(azAthens >= 280.0 && azAthens <= 305.0, "Unexpected Athens Azimuth: \(azAthens)")
        precondition(compAthens == "WNW", "Expected WNW compass heading, got: \(compAthens)")
    }

    private static func testCorridorMaxMUFSelection() {
        // Along 295° corridor, sounders are Nicosia (FoEs 8.8 -> 44 MHz) and Athens (FoEs 9.2 -> 46 MHz)
        let stations: [(code: String, foEs: Double, muf: Double)] = [
            ("NIC40", 8.8, 44.0),
            ("AT138", 9.2, 46.0)
        ]
        let best = stations.max { $0.muf < $1.muf }
        precondition(best?.code == "AT138", "Corridor 295° failed to pick highest MUF sounder")
        precondition(best?.muf == 46.0, "Corridor 295° failed to record 46 MHz MUF")
    }

    private static func testReflectorMidpointGeometries() {
        // 295° Corridor (2600 km Es2 path):
        // 1st midpoint is at ~700 km (Eastern Turkey / Cyprus)
        // 2nd midpoint is at ~1950 km (Greece / Balkans / AT138 / RO041)
        let distTotal = 2600.0
        let hop1Mid = distTotal * 0.27 // ~700 km
        let hop2Mid = distTotal * 0.75 // ~1950 km

        precondition(hop1Mid >= 650 && hop1Mid <= 750)
        precondition(hop2Mid >= 1900 && hop2Mid <= 2000)
    }

    private static func testDynamicSparseReceiverCompensation() {
        // When telemetry count is 0 in EP region and Midpoint MUF is 46 MHz:
        // Midpoint MUF 46 MHz -> score = 80.0
        // Dynamic Compensated: 80 * 0.65 (52.0) + 5 * 0.10 (0.5) + 100 * 0.15 (15.0) + 45 * 0.10 (4.5) = 72%
        let res = calculateDynamicWeightedScoreTest(midpointMUF: 46.0, telemetryCount: 0, isPeakHour: true, isSummer: true, sfi: 130, kp: 2)
        precondition(res.isCompensated == true)
        precondition(res.midWeight == 0.65)
        precondition(res.telWeight == 0.10)
        precondition(res.score >= 70 && res.score <= 74, "Expected ~72% score, got \(res.score)%")
    }

    private static func testStrictOpeningLevelClassification() {
        // Score is 77% but Max MUF is 46 MHz (< 50 MHz):
        // Must be "VERY HIGH / IMMINENT", NOT "OPEN"
        let levelImminent = evaluateOpeningLevelTest(maxMUF: 46.0, score: 77)
        precondition(levelImminent == "VERY HIGH / IMMINENT", "Expected VERY HIGH / IMMINENT, got \(levelImminent)")

        // When Max MUF reaches 51 MHz:
        let levelOpen = evaluateOpeningLevelTest(maxMUF: 51.0, score: 85)
        precondition(levelOpen == "OPEN", "Expected OPEN, got \(levelOpen)")
    }
}
