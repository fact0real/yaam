//
//  LiveGreylineOverlayRegression.swift
//  YAAM Tests
//
//  Regression test suite for Live Greyline Propagation Overlay:
//  - Solar ephemeris declination and subsolar point calculations
//  - Terminator (0°) and twilight (-6°, -12°) vector contours
//  - Next solar event countdown (Sunrise/Sunset)
//  - Station solar status and low-band ducting efficiency
//  - Great-Circle path Greyline ducting coincidence detection
//

import Foundation
@testable import YAAM

@main
@MainActor
struct LiveGreylineOverlayRegression {
    static func main() async {
        print("🚀 Starting Live Greyline Propagation Overlay Regression Test Suite...")
        testSolarEphemerisAndDeclination()
        testTerminatorAndTwilightCoordinates()
        testSunriseSunsetAndNextEventCountdown()
        testStationSolarStatusAndDuctingEfficiency()
        testGreylinePathPropagationDucting()
        print("🎉 ALL Live Greyline Overlay Tests PASSED successfully!")
    }

    // MARK: - 1. Solar Ephemeris & Declination
    private static func testSolarEphemerisAndDeclination() {
        print("🧪 Testing Solar Ephemeris & Declination at Solstices & Equinoxes...")

        let calendar = Calendar(identifier: .gregorian)
        var calUTC = calendar
        calUTC.timeZone = TimeZone(secondsFromGMT: 0)!

        // Summer Solstice: June 21 at 12:00 UTC
        var compsSummer = DateComponents()
        compsSummer.year = 2026
        compsSummer.month = 6
        compsSummer.day = 21
        compsSummer.hour = 12
        let summerDate = calUTC.date(from: compsSummer)!
        let summerSubSolar = SolarEphemeris.calculate(at: summerDate)

        assert(summerSubSolar.latitude > 23.0 && summerSubSolar.latitude < 23.6,
               "Summer solstice declination should be ~+23.44°, got \(summerSubSolar.latitude)°")
        print("  ✓ Summer Solstice Declination: \(String(format: "%+.2f°", summerSubSolar.latitude))")

        // Winter Solstice: December 21 at 12:00 UTC
        var compsWinter = DateComponents()
        compsWinter.year = 2026
        compsWinter.month = 12
        compsWinter.day = 21
        compsWinter.hour = 12
        let winterDate = calUTC.date(from: compsWinter)!
        let winterSubSolar = SolarEphemeris.calculate(at: winterDate)

        assert(winterSubSolar.latitude < -23.0 && winterSubSolar.latitude > -23.6,
               "Winter solstice declination should be ~-23.44°, got \(winterSubSolar.latitude)°")
        print("  ✓ Winter Solstice Declination: \(String(format: "%+.2f°", winterSubSolar.latitude))")

        // Spring Equinox: March 20 at 12:00 UTC
        var compsEquinox = DateComponents()
        compsEquinox.year = 2026
        compsEquinox.month = 3
        compsEquinox.day = 20
        compsEquinox.hour = 12
        let equinoxDate = calUTC.date(from: compsEquinox)!
        let equinoxSubSolar = SolarEphemeris.calculate(at: equinoxDate)

        assert(abs(equinoxSubSolar.latitude) < 1.0,
               "Spring equinox declination should be near 0°, got \(equinoxSubSolar.latitude)°")
        print("  ✓ Spring Equinox Declination: \(String(format: "%+.2f°", equinoxSubSolar.latitude))")
    }

    // MARK: - 2. Terminator & Twilight Coordinates
    private static func testTerminatorAndTwilightCoordinates() {
        print("🧪 Testing Terminator and Civil Twilight Contour Elevation Verification...")

        let testDate = Date()

        // 1. Terminator coordinates (h = 0°)
        let termCoords = SolarEphemeris.terminatorCoordinates(at: testDate, stepDegrees: 15.0)
        assert(!termCoords.isEmpty, "Terminator coordinates must not be empty")

        for coord in termCoords {
            let elev = SolarEphemeris.solarElevation(for: coord, at: testDate)
            assert(abs(elev) < 1.0, "Point on terminator should have solar elevation near 0°, got \(elev)° at \(coord)")
        }
        print("  ✓ Terminator coordinates verified (all within ±1.0° of 0° elevation).")

        // 2. Civil Twilight coordinates (h = -6°)
        let civilCoords = SolarEphemeris.twilightCoordinates(elevationDeg: -6.0, at: testDate, stepDegrees: 2.0)
        assert(!civilCoords.isEmpty, "Civil twilight coordinates must not be empty")

        var verifiedCount = 0
        for coord in civilCoords {
            // Check non-polar clamped coordinates
            if abs(coord.latitude) < 85.0 {
                let elev = SolarEphemeris.solarElevation(for: coord, at: testDate)
                if abs(elev - (-6.0)) < 1.5 {
                    verifiedCount += 1
                }
            }
        }
        assert(verifiedCount >= 5, "At least 5 civil twilight points must be verified, got \(verifiedCount)")
        print("  ✓ Civil Twilight coordinates verified (verified \(verifiedCount) points with solar elevation ~-6°).")
    }

    // MARK: - 3. Next Solar Event Countdown
    private static func testSunriseSunsetAndNextEventCountdown() {
        print("🧪 Testing Next Solar Event (Sunrise/Sunset) and Live Countdown...")

        let tehran = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
        let now = Date()

        let nextEvent = SolarEphemeris.nextSolarEvent(for: tehran, at: now)

        assert(nextEvent.event == .sunrise || nextEvent.event == .sunset, "Event must be sunrise or sunset")
        assert(nextEvent.date != nil, "Next event date must not be nil")
        assert(nextEvent.countdownMinutes >= 0 && nextEvent.countdownMinutes <= 1440,
               "Countdown minutes must be between 0 and 1440 (24h), got \(nextEvent.countdownMinutes)")
        assert(!nextEvent.countdownText.isEmpty, "Countdown text must not be empty")
        assert(nextEvent.countdownText.contains("in"), "Countdown text must contain 'in': \(nextEvent.countdownText)")

        print("  ✓ Next Solar Event for Tehran: \(nextEvent.countdownText) (event: \(nextEvent.event.rawValue))")
    }

    // MARK: - 4. Station Solar Status & Ducting Efficiency
    private static func testStationSolarStatusAndDuctingEfficiency() {
        print("🧪 Testing Station Solar Status & Low-Band Ducting Efficiency...")

        let tehran = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
        let status = SolarEphemeris.stationSolarStatus(for: tehran, at: Date())

        assert(status.elevationDeg >= -90.0 && status.elevationDeg <= 90.0, "Elevation out of bounds")
        assert(status.lowBandDuctingEfficiency >= 0.0 && status.lowBandDuctingEfficiency <= 1.0,
               "Ducting efficiency must be between 0 and 1")

        if status.elevationDeg <= 0.0 && status.elevationDeg >= -12.0 {
            assert(status.isGreylineActive, "Status must report greyline active when elevation in [0, -12]")
            assert(status.lowBandDuctingEfficiency > 0.0, "Ducting efficiency must be > 0 during greyline")
        } else if status.elevationDeg > 10.0 {
            assert(!status.isGreylineActive, "Greyline should be inactive in broad daylight")
            assert(status.lowBandDuctingEfficiency == 0.0, "Ducting efficiency should be 0 in daylight")
        }

        print("  ✓ Station Solar Status: \(status.illumination.rawValue), Elev: \(String(format: "%+.1f°", status.elevationDeg)), Duct: \(Int(status.lowBandDuctingEfficiency * 100))%")
    }

    // MARK: - 5. Greyline Path Propagation Ducting
    private static func testGreylinePathPropagationDucting() {
        print("🧪 Testing Great Circle Path Greyline Ducting Detection...")

        let now = Date()
        let subSolar = SolarEphemeris.calculate(at: now)

        // Point A: In direct subsolar point (broad daylight, elevation ~+90°)
        let sunCoord = GeoCoordinate(latitude: subSolar.latitude, longitude: subSolar.longitude)
        // Point B: 5 degrees away from sun (broad daylight)
        let nearSunCoord = GeoCoordinate(latitude: subSolar.latitude + 3.0, longitude: subSolar.longitude + 3.0)

        let dayPathResult = SolarEphemeris.isPathInGreyline(from: sunCoord, to: nearSunCoord, at: now)
        assert(!dayPathResult.isInGreyline, "Path in full daylight should not be in greyline duct")
        assert(dayPathResult.ductFactor == 0.0, "Day path duct factor should be 0.0")

        // Point C & D: Both points on the terminator (solar elevation near 0°)
        let termPoints = SolarEphemeris.terminatorCoordinates(at: now, stepDegrees: 10.0)
        assert(termPoints.count >= 4, "Must have enough terminator points")

        let termA = termPoints[5]
        let termB = termPoints[6]

        let greylinePathResult = SolarEphemeris.isPathInGreyline(from: termA, to: termB, at: now)
        assert(greylinePathResult.isInGreyline, "Path between terminator points should be detected as Greyline duct")
        assert(greylinePathResult.ductFactor > 0.0, "Terminator path duct factor should be > 0.0")

        print("  ✓ Greyline Path Coincidence verified: Daylight path = \(dayPathResult.isInGreyline), Terminator path = \(greylinePathResult.isInGreyline) (factor: \(String(format: "%.2f", greylinePathResult.ductFactor)))")
    }
}
