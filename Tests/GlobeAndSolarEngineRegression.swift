//
//  GlobeAndSolarEngineRegression.swift
//  YAAM Tests
//

import Foundation

// MARK: - Standalone Replicas of Engine Structs for Regression Testing

struct TestGeoCoordinate: Equatable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = max(-90.0, min(90.0, latitude))
        var lon = longitude.truncatingRemainder(dividingBy: 360.0)
        if lon > 180.0 { lon -= 360.0 }
        if lon < -180.0 { lon += 360.0 }
        self.longitude = lon
    }
}

func calculateSubSolarTest(date: Date) -> (lat: Double, lon: Double, eqTime: Double) {
    let calendar = Calendar(identifier: .gregorian)
    var calUTC = calendar
    calUTC.timeZone = TimeZone(secondsFromGMT: 0)!

    let dayOfYear = Double(calUTC.ordinality(of: .day, in: .year, for: date) ?? 1)
    let hour = Double(calUTC.component(.hour, from: date))
    let minute = Double(calUTC.component(.minute, from: date))
    let second = Double(calUTC.component(.second, from: date))

    let universalTimeHours = hour + minute / 60.0 + second / 3600.0
    let gamma = 2.0 * .pi / 365.0 * (dayOfYear - 1.0 + (universalTimeHours - 12.0) / 24.0)

    let eqtime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
                          - 0.014615 * cos(2.0 * gamma) - 0.040849 * sin(2.0 * gamma))

    let decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
               - 0.006758 * cos(2.0 * gamma) + 0.000907 * sin(2.0 * gamma)
               - 0.002697 * cos(3.0 * gamma) + 0.001480 * sin(3.0 * gamma)

    let declinationDeg = decl * 180.0 / .pi

    let subSolarLon = -(universalTimeHours - 12.0 + eqtime / 60.0) * 15.0
    var normalizedLon = subSolarLon.truncatingRemainder(dividingBy: 360.0)
    if normalizedLon > 180.0 { normalizedLon -= 360.0 }
    if normalizedLon < -180.0 { normalizedLon += 360.0 }

    return (declinationDeg, normalizedLon, eqtime)
}

func distanceKmTest(from: TestGeoCoordinate, to: TestGeoCoordinate) -> Double {
    let earthRadiusKm = 6371.0088
    let lat1 = from.latitude * .pi / 180.0
    let lat2 = to.latitude * .pi / 180.0
    let deltaLat = (to.latitude - from.latitude) * .pi / 180.0
    let deltaLon = (to.longitude - from.longitude) * .pi / 180.0

    let a = sin(deltaLat / 2.0) * sin(deltaLat / 2.0) +
            cos(lat1) * cos(lat2) *
            sin(deltaLon / 2.0) * sin(deltaLon / 2.0)
    let c = 2.0 * atan2(sqrt(a), sqrt(max(0.0, 1.0 - a)))
    return earthRadiusKm * c
}

func initialBearingTest(from: TestGeoCoordinate, to: TestGeoCoordinate) -> Double {
    let lat1 = from.latitude * .pi / 180.0
    let lat2 = to.latitude * .pi / 180.0
    let deltaLon = (to.longitude - from.longitude) * .pi / 180.0

    let y = sin(deltaLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
    let bearingRad = atan2(y, x)
    let bearingDeg = bearingRad * 180.0 / .pi
    return bearingDeg < 0 ? bearingDeg + 360.0 : bearingDeg
}

func coordToMaidenhead4Test(coord: TestGeoCoordinate) -> String {
    var lon = coord.longitude + 180.0
    var lat = coord.latitude + 90.0

    lon = max(0.0, min(359.9999, lon))
    lat = max(0.0, min(179.9999, lat))

    let fieldLon = Int(lon / 20.0)
    let fieldLat = Int(lat / 10.0)

    let remLon1 = lon.truncatingRemainder(dividingBy: 20.0)
    let remLat1 = lat.truncatingRemainder(dividingBy: 10.0)

    let squareLon = Int(remLon1 / 2.0)
    let squareLat = Int(remLat1 / 1.0)

    let charA = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(fieldLon))))
    let charB = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(fieldLat))))

    return "\(charA)\(charB)\(squareLon)\(squareLat)"
}

func maidenheadToBoundingBoxTest(grid: String) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
    let clean = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard clean.count >= 4 else { return nil }

    let chars = Array(clean)
    guard let fieldA = chars[0].asciiValue,
          let fieldB = chars[1].asciiValue,
          let sqNum1 = chars[2].wholeNumberValue,
          let sqNum2 = chars[3].wholeNumberValue else { return nil }

    var minLon = Double(fieldA - Character("A").asciiValue!) * 20.0 - 180.0
    var minLat = Double(fieldB - Character("A").asciiValue!) * 10.0 - 90.0

    minLon += Double(sqNum1) * 2.0
    let maxLon = minLon + 2.0

    minLat += Double(sqNum2) * 1.0
    let maxLat = minLat + 1.0

    return (minLat, maxLat, minLon, maxLon)
}

@main
struct GlobeAndSolarEngineRegression {
    static func main() {
        print("Running Interactive 3D Globe, Solar Greyline & GridTracker Regression Tests...")

        testAstronomicalSubSolarAndDeclination()
        testGreatCircleGeodesicCalculations()
        testMaidenheadGridCalculations()
        testCompassCardinals()

        print("All 3D Globe, Solar Greyline & GridTracker Tests PASSED successfully!")
    }

    private static func testAstronomicalSubSolarAndDeclination() {
        let now = Date()
        let sub = calculateSubSolarTest(date: now)

        // Declination must stay within Earth axial tilt range ±23.5°
        precondition(sub.lat >= -24.0 && sub.lat <= 24.0, "Declination \(sub.lat) out of bounds")
        // Longitude must stay within -180° ... +180°
        precondition(sub.lon >= -180.0 && sub.lon <= 180.0, "Subsolar lon \(sub.lon) out of bounds")
        // Equation of time is between -20 min and +20 min
        precondition(sub.eqTime >= -25.0 && sub.eqTime <= 25.0, "Equation of time \(sub.eqTime) out of bounds")
    }

    private static func testGreatCircleGeodesicCalculations() {
        // Tehran (35.6892° N, 51.3890° E) to London (51.5074° N, 0.1278° W)
        let tehran = TestGeoCoordinate(latitude: 35.6892, longitude: 51.3890)
        let london = TestGeoCoordinate(latitude: 51.5074, longitude: -0.1278)

        let dist = distanceKmTest(from: tehran, to: london)
        precondition(dist > 4300.0 && dist < 4550.0, "Expected dist ~4420km, got \(dist)")

        let bearing = initialBearingTest(from: tehran, to: london)
        precondition(bearing > 300.0 && bearing < 325.0, "Expected bearing ~313° (NW), got \(bearing)")

        // Tehran to Tokyo (35.6762° N, 139.6503° E)
        let tokyo = TestGeoCoordinate(latitude: 35.6762, longitude: 139.6503)
        let distTokyo = distanceKmTest(from: tehran, to: tokyo)
        precondition(distTokyo > 7500.0 && distTokyo < 7800.0, "Expected dist Tokyo ~7650km, got \(distTokyo)")

        let bearingTokyo = initialBearingTest(from: tehran, to: tokyo)
        precondition(bearingTokyo > 55.0 && bearingTokyo < 75.0, "Expected bearing Tokyo ~65° (ENE), got \(bearingTokyo)")
    }

    private static func testMaidenheadGridCalculations() {
        // Tehran coordinates -> LM55
        let tehran = TestGeoCoordinate(latitude: 35.6892, longitude: 51.3890)
        let grid = coordToMaidenhead4Test(coord: tehran)
        precondition(grid == "LM55", "Expected Tehran grid LM55, got \(grid)")

        // Bounding box of LM55
        guard let box = maidenheadToBoundingBoxTest(grid: "LM55") else {
            fatalError("Failed bounding box for LM55")
        }
        precondition(box.minLon >= 40.0 && box.maxLon <= 60.0, "Invalid lon bounds for LM55")
        precondition(box.minLat >= 30.0 && box.maxLat <= 40.0, "Invalid lat bounds for LM55")
    }

    private static func testCompassCardinals() {
        func compassCardinal(for bearing: Double) -> String {
            let directions = [
                "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"
            ]
            let rawIndex = Int(round(bearing / 22.5)) % 16
            let safeIndex = rawIndex < 0 ? rawIndex + 16 : rawIndex
            return directions[safeIndex]
        }

        precondition(compassCardinal(for: 0.0) == "N", "0° should be N")
        precondition(compassCardinal(for: 90.0) == "E", "90° should be E")
        precondition(compassCardinal(for: 180.0) == "S", "180° should be S")
        precondition(compassCardinal(for: 270.0) == "W", "270° should be W")
        precondition(compassCardinal(for: 295.0) == "WNW", "295° should be WNW")
        precondition(compassCardinal(for: 315.0) == "NW", "315° should be NW")
    }
}
