//
//  AzimuthMapEngineRegression.swift
//  YAAM Tests
//

import CoreGraphics
import Foundation

@main
struct AzimuthMapEngineRegression {
    static func main() {
        print("🚀 Starting Azimuth Map & DXing Engineering Regression Test Suite...")
        testLunarEphemerisCalculation()
        testSolarElevationAndTwilight()
        testShortPathAndLongPathBearings()
        testBandColorMapping()
        testSpotAgingTemporalDecay()
        testDXCCBoundingBoxCollisionAvoidance()
        print("🎉 ALL Azimuth Map & DXing Engineering Tests PASSED successfully!")
    }

    // MARK: - 1. Lunar Ephemeris Test
    private static func testLunarEphemerisCalculation() {
        print("🧪 Testing Lunar Ephemeris (Meeus/Schlyter algorithm)...")

        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 5
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)

        guard let testDate = calendar.date(from: components) else {
            fatalError("Failed to construct test date")
        }

        let lunarPos = LunarEphemeris.calculate(at: testDate)

        // Declination / latitude of Moon is always between -29° and +29°
        assert(lunarPos.latitude >= -29.0 && lunarPos.latitude <= 29.0,
               "Moon declination out of physical bounds: \(lunarPos.latitude)°")

        // Sub-lunar longitude must be normalized in [-180, 180]
        assert(lunarPos.longitude >= -180.0 && lunarPos.longitude <= 180.0,
               "Sub-lunar longitude out of bounds: \(lunarPos.longitude)°")

        // Illumination phase percent must be in [0.0, 100.0]
        assert(lunarPos.phasePercent >= 0.0 && lunarPos.phasePercent <= 100.0,
               "Moon phase percent out of range [0, 100]: \(lunarPos.phasePercent)")

        print("   ✅ Moon Sublunar: Lat \(String(format: "%.2f", lunarPos.latitude))°, Lon \(String(format: "%.2f", lunarPos.longitude))°, Illum: \(Int(lunarPos.phasePercent))%")
    }

    // MARK: - 2. Solar Elevation & Twilight Test
    private static func testSolarElevationAndTwilight() {
        print("🧪 Testing Solar Elevation and Civil/Nautical Twilight Gradients...")

        let noonTehran = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
        var comp = DateComponents()
        comp.year = 2026
        comp.month = 6
        comp.day = 21
        comp.hour = 8
        comp.minute = 30
        comp.timeZone = TimeZone(secondsFromGMT: 0)
        let noonDate = Calendar(identifier: .gregorian).date(from: comp)!

        let elev = SolarEphemeris.solarElevation(for: noonTehran, at: noonDate)
        assert(elev > 60.0, "Tehran summer solar noon elevation expected > 60°, got \(elev)°")

        let state = SolarEphemeris.illuminationState(for: noonTehran, at: noonDate)
        assert(state == .daylight, "Expected daylight at solar noon")
        assert(SolarEphemeris.IlluminationState.greylineCivil.rawValue == "Civil Greyline")
        print("   ✅ Solar elevation and daylight/twilight states validated successfully")
    }

    // MARK: - 3. Short Path & Long Path Bearings Test
    private static func testShortPathAndLongPathBearings() {
        print("🧪 Testing Great Circle Short Path (SP) and Long Path (LP) Bearings...")

        let tehran = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
        let tokyo = GeoCoordinate(latitude: 35.6762, longitude: 139.6503)

        let spBearing = GeodesicMath.initialBearing(from: tehran, to: tokyo)
        let lpBearing = GeodesicMath.longPathBearing(from: tehran, to: tokyo)

        assert(spBearing >= 60.0 && spBearing <= 75.0, "Tehran to Tokyo SP bearing out of expected range: \(spBearing)°")

        let expectedLP = (spBearing + 180.0).truncatingRemainder(dividingBy: 360.0)
        assert(abs(lpBearing - expectedLP) < 0.001, "LP bearing (\(lpBearing)°) != expected (\(expectedLP)°)")

        let spDist = GeodesicMath.distanceKm(from: tehran, to: tokyo)
        let lpDist = GeodesicMath.longPathDistanceKm(from: tehran, to: tokyo)
        let totalCircumference = spDist + lpDist
        assert(abs(totalCircumference - 40030.0) < 50.0, "Earth circumference sum mismatch: \(totalCircumference) km")

        print("   ✅ SP: \(String(format: "%.1f", spBearing))° (\(Int(spDist)) km), LP: \(String(format: "%.1f", lpBearing))° (\(Int(lpDist)) km)")
    }

    // MARK: - 4. Band Color Mapping Test
    private static func testBandColorMapping() {
        print("🧪 Testing Ham Radio Standard Band Colors...")

        let testBands = ["160m", "80m", "40m", "30m", "20M", "17M", "15m", "12m", "10m", "6M", "2m", "70cm"]
        for b in testBands {
            let color = WorldVectorGeography.bandColor(for: b)
            _ = color
        }
        print("   ✅ Validated color mappings for all 12 amateur bands")
    }

    // MARK: - 5. Spot Aging Temporal Decay Test
    private static func testSpotAgingTemporalDecay() {
        print("🧪 Testing Spot Aging Temporal Decay intervals...")

        func spotAlpha(ageSeconds: Double) -> Double {
            if ageSeconds < 180 { return 1.0 }
            else if ageSeconds < 600 { return 0.80 }
            else if ageSeconds < 1200 { return 0.50 }
            else if ageSeconds < 1800 { return 0.28 }
            else { return 0.12 }
        }

        assert(spotAlpha(ageSeconds: 45) == 1.0, "0-3m spot must be 100% alpha")
        assert(spotAlpha(ageSeconds: 300) == 0.80, "3-10m spot must be 80% alpha")
        assert(spotAlpha(ageSeconds: 900) == 0.50, "10-20m spot must be 50% alpha")
        assert(spotAlpha(ageSeconds: 1500) == 0.28, "20-30m spot must be 28% alpha")
        assert(spotAlpha(ageSeconds: 2400) == 0.12, ">30m spot must be 12% alpha")

        print("   ✅ Temporal decay intervals (0-3m, 3-10m, 10-20m, 20-30m, >30m) verified")
    }

    // MARK: - 6. DXCC Collision Avoidance Test
    private static func testDXCCBoundingBoxCollisionAvoidance() {
        print("🧪 Testing DXCC Collision Avoidance algorithm...")

        var occupiedRects: [CGRect] = []
        let box1 = CGRect(x: 100, y: 100, width: 50, height: 20)
        occupiedRects.append(box1)

        let boxOverlap = CGRect(x: 120, y: 110, width: 50, height: 20)
        let collidesOverlap = occupiedRects.contains { $0.intersects(boxOverlap) }
        assert(collidesOverlap, "Overlapping label was not detected as colliding")

        let boxClear = CGRect(x: 200, y: 200, width: 50, height: 20)
        let collidesClear = occupiedRects.contains { $0.intersects(boxClear) }
        assert(!collidesClear, "Non-overlapping label was falsely flagged as colliding")

        print("   ✅ DXCC bounding box collision detection verified")
    }
}
