//
//  ContestBandmapRegressionTests.swift
//  YAAM Tests
//
//  Unit and Regression Tests for Contest Bandmap HUD,
//  VFO tracking, spot filtering, age decay opacity, and status classification.
//

import Foundation
@testable import YAAM

@main
@MainActor
public struct ContestBandmapRegressionTests {
    public static func main() {
        let passed = runAllTests()
        exit(passed ? 0 : 1)
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

        print("--- Starting Contest Bandmap Regression Tests ---")

        // Test 1: Spot Construction & Age Decay
        let now = Date()
        let freshSpot = ContestBandmapSpotItem(
            callsign: "W1AW",
            frequencyKHz: 14025.0,
            band: "20M",
            mode: "CW",
            spottedAt: now,
            flagEmoji: "🇺🇸",
            entityName: "United States",
            status: .newMultiplier,
            snrDB: 24
        )

        assertTest(freshSpot.callsign == "W1AW", "Callsign preserved")
        assertTest(freshSpot.frequencyKHz == 14025.0, "Frequency preserved")
        assertTest(freshSpot.ageMinutes < 0.1, "Fresh spot has ~0 age")
        assertTest(freshSpot.ageOpacity == 1.0, "Fresh spot has 100% opacity")
        assertTest(freshSpot.status == .newMultiplier, "Status is newMultiplier")

        // 10-minute old spot (should have 0.75 opacity)
        let tenMinOldSpot = ContestBandmapSpotItem(
            callsign: "DL1ABC",
            frequencyKHz: 14015.0,
            band: "20M",
            mode: "CW",
            spottedAt: now.addingTimeInterval(-600),
            flagEmoji: "🇩🇪",
            entityName: "Germany",
            status: .validNewCall
        )
        assertTest(tenMinOldSpot.ageMinutes >= 9.9 && tenMinOldSpot.ageMinutes <= 10.1, "Spot age is ~10 min")
        assertTest(tenMinOldSpot.ageOpacity == 0.75, "10-min spot has 75% opacity")

        // 20-minute old spot (should have 0.45 opacity)
        let twentyMinOldSpot = ContestBandmapSpotItem(
            callsign: "JA1BJK",
            frequencyKHz: 14035.0,
            band: "20M",
            mode: "CW",
            spottedAt: now.addingTimeInterval(-1200),
            flagEmoji: "🇯🇵",
            entityName: "Japan",
            status: .duplicate
        )
        assertTest(twentyMinOldSpot.ageOpacity == 0.45, "20-min spot has 45% opacity")

        // 45-minute old spot (should have 0.25 opacity)
        let oldSpot = ContestBandmapSpotItem(
            callsign: "EP2AES",
            frequencyKHz: 14020.0,
            band: "20M",
            mode: "CW",
            spottedAt: now.addingTimeInterval(-2700),
            flagEmoji: "🇮🇷",
            entityName: "Iran",
            status: .newMultiplier
        )
        assertTest(oldSpot.ageOpacity == 0.25, "Expired spot has 25% opacity")

        // Test 2: Frequency Offset Calculation for QSY
        let vfoTargetFreq = freshSpot.frequencyKHz / 1000.0
        assertTest(abs(vfoTargetFreq - 14.025) < 0.0001, "Target VFO MHz is exactly 14.025")

        // Test 3: Status Distinction
        assertTest(freshSpot.status != tenMinOldSpot.status, "Different spot statuses distinguished")
        assertTest(twentyMinOldSpot.status == .duplicate, "Dupe status recognized")

        print("--- Contest Bandmap Regression Tests Completed ---")
        return passed
    }
}
