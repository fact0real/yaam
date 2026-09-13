//
//  QClusterEnhancementsRegressionTests.swift
//  YAAM Tests
//
//  Comprehensive regression tests for QCluster-inspired architectural features:
//  - LoTWActivityDatabase parsing, caching, and active user resolution
//  - SpotterDistanceEngine Maidenhead locator conversion, Haversine distance, and azimuth bearing
//  - SpotAlertRule multi-tier matching and WildcardPatternMatcher
import Foundation
@testable import YAAM

@main
public struct QClusterEnhancementsRegressionTests {
    public static func main() {
        let success = runAllTests()
        exit(success ? 0 : 1)
    }

    public static func runAllTests() -> Bool {
        var passed = true

        func assertTest(_ condition: Bool, _ name: String) {
            if !condition {
                print("❌ FAIL: \(name)")
                passed = false
            } else {
                print("✅ PASS: \(name)")
            }
        }

        print("🚀 Starting QCluster Enhancements Regression Tests...")

        // MARK: - 1. LoTW User Activity Tests
        print("--- Testing LoTWActivityDatabase ---")
        let sampleCSV = """
        EP2AES,2026-08-15,14:20:00
        W1AW,2026-09-01,10:11:12
        3B8CF,2023-01-10,08:00:00
        K1ABC,2025-05-20,12:00:00
        """

        let lotwDB = LoTWActivityDatabase.shared
        let parsedCount = lotwDB.parseCSVData(Data(sampleCSV.utf8))
        assertTest(parsedCount == 4, "Parsed exactly 4 sample LoTW records (got \(parsedCount))")

        // EP2AES and W1AW should be active (within 365 days of September 2026)
        assertTest(lotwDB.isUserActive("EP2AES"), "EP2AES is marked active")
        assertTest(lotwDB.isUserActive("W1AW"), "W1AW is marked active")

        // 3B8CF uploaded in 2023 (>3 years ago), should be inactive
        assertTest(!lotwDB.isUserActive("3B8CF"), "3B8CF is marked inactive (>1 year)")
        assertTest(lotwDB.lastUploadDate(for: "3B8CF") != nil, "3B8CF has a recorded date")

        // Non-existent callsign
        assertTest(!lotwDB.isUserActive("UNKNOWN999"), "Unknown call is not active")
        assertTest(lotwDB.lastUploadDate(for: "UNKNOWN999") == nil, "Unknown call has no date")

        // Portable suffix cleaning
        assertTest(lotwDB.isUserActive("EP2AES/P"), "EP2AES/P resolves to base call and is active")

        // MARK: - 2. Spotter Distance & Bearing Engine Tests
        print("--- Testing SpotterDistanceEngine ---")
        // Test Tehran (LM65) coordinates:
        // LM: Field lon = 11 ('L'), lat = 12 ('M') -> lon: (11*20 - 180) + (6*2) + 1 = 53°E, lat: (12*10 - 90) + 5 + 0.5 = 35.5°N
        if let tehranCoord = SpotterDistanceEngine.coordinates(forGrid: "LM65") {
            assertTest(abs(tehranCoord.lat - 35.5) < 0.1, "LM65 latitude center is ~35.5°N (got \(tehranCoord.lat))")
            assertTest(abs(tehranCoord.lon - 53.0) < 0.1, "LM65 longitude center is ~53.0°E (got \(tehranCoord.lon))")
        } else {
            assertTest(false, "Failed to parse LM65 grid")
        }

        // Test London (JO01)
        if let londonCoord = SpotterDistanceEngine.coordinates(forGrid: "JO01") {
            assertTest(abs(londonCoord.lat - 51.5) < 0.1, "JO01 latitude center is ~51.5°N (got \(londonCoord.lat))")
            assertTest(abs(londonCoord.lon - 1.0) < 0.1, "JO01 longitude center is ~1.0°E (got \(londonCoord.lon))")
        } else {
            assertTest(false, "Failed to parse JO01 grid")
        }

        // Distance & Bearing between LM65 (Tehran) and JO01 (London)
        if let pathInfo = SpotterDistanceEngine.locationInfo(fromGrid: "LM65", toGrid: "JO01") {
            assertTest(pathInfo.distanceKm > 4000 && pathInfo.distanceKm < 5000, "Distance Tehran-London is ~4400 km (got \(Int(pathInfo.distanceKm)) km)")
            assertTest(pathInfo.bearingDeg > 290 && pathInfo.bearingDeg < 330, "Bearing Tehran to London is NW (got \(Int(pathInfo.bearingDeg))°)")
            assertTest(pathInfo.cardinalDirection.contains("W") || pathInfo.cardinalDirection.contains("N"), "Cardinal direction contains N/W (got \(pathInfo.cardinalDirection))")
        } else {
            assertTest(false, "Failed to calculate path between LM65 and JO01")
        }

        // MARK: - 3. WildcardPatternMatcher Tests
        print("--- Testing WildcardPatternMatcher ---")
        assertTest(WildcardPatternMatcher.matches(pattern: "*", text: "EP2AES"), "Pattern '*' matches any call")
        assertTest(WildcardPatternMatcher.matches(pattern: "*P*", text: "EP2AES"), "Pattern '*P*' matches EP2AES")
        assertTest(WildcardPatternMatcher.matches(pattern: "3B7*", text: "3B7M"), "Pattern '3B7*' matches 3B7M")
        assertTest(!WildcardPatternMatcher.matches(pattern: "3B7*", text: "3B8CF"), "Pattern '3B7*' does not match 3B8CF")
        assertTest(WildcardPatternMatcher.matches(pattern: "??2???", text: "EP2AES"), "Pattern '??2???' matches EP2AES")

        // MARK: - 4. SpotAlertRule Matching Tests
        print("--- Testing SpotAlertRule ---")
        let rule1 = SpotAlertRule(slotIndex: 1, title: "Iran Rule", isEnabled: true, dxccEntity: "Iran", band: "20m", mode: "CW")
        let spot1 = DXSpot(
            id: "EP2AES-14025",
            callsign: "EP2AES",
            spotter: "G3ABC",
            frequencyKHz: 14025.0,
            band: "20m",
            mode: "CW",
            submode: "CW",
            comment: "599",
            grid: "LL65",
            spottedAt: Date(),
            lastSeenAt: Date(),
            reportCount: 1
        )

        assertTest(rule1.matches(spot: spot1, entityName: "Iran", status: .newCallsign), "Rule 1 matches spot1 (Iran, 20m, CW)")

        // Mismatch band
        var spotWrongBand = spot1
        spotWrongBand.band = "40m"
        assertTest(!rule1.matches(spot: spotWrongBand, entityName: "Iran", status: .newCallsign), "Rule 1 does not match wrong band (40m)")

        // Wildcard callsign rule
        let ruleWildcard = SpotAlertRule(slotIndex: 5, title: "Special Prefix", isEnabled: true, callsignPattern: "3B*")
        var spotMauritius = spot1
        spotMauritius.callsign = "3B8CF"
        assertTest(ruleWildcard.matches(spot: spotMauritius, entityName: "Mauritius", status: .worked), "Wildcard rule matches 3B8CF")

        print("========================================")
        if passed {
            print("🎉 ALL QCluster Enhancements Tests PASSED successfully!")
        } else {
            print("💥 Some tests FAILED!")
        }
        return passed
    }
}
