//
//  ContestRateMatrixRegressionTests.swift
//  YAAM Tests
//
//  Unit and Regression Tests for Contest Rate Matrix Engine,
//  rolling rate calculations, streak detection, and 2D multiplier aggregation.
//

import Foundation
@testable import YAAM

@main
@MainActor
public struct ContestRateMatrixRegressionTests {
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

        print("--- Starting Contest Rate Matrix Regression Tests ---")

        let engine = ContestRateMatrixEngine.shared
        engine.reset()

        assertTest(engine.totalQSOs == 0, "Initial QSOs is 0")
        assertTest(engine.rolling10MinRate == 0, "Initial 10m rate is 0")
        assertTest(engine.bandSummaries.count == 7, "Supports 7 HF contest bands")

        // Create test QSOs across multiple bands with valid date/times
        let now = Date()
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd HHmmss"

        let d1 = formatter.string(from: now.addingTimeInterval(-120)) // 2 mins ago
        let d2 = formatter.string(from: now.addingTimeInterval(-240)) // 4 mins ago
        let d3 = formatter.string(from: now.addingTimeInterval(-400)) // ~6.6 mins ago

        let parts1 = d1.components(separatedBy: " ")
        let parts2 = d2.components(separatedBy: " ")
        let parts3 = d3.components(separatedBy: " ")

        let qso1 = QSORecordModel(fields: [
            "CALL": "W1AW",
            "BAND": "20M",
            "MODE": "CW",
            "CQZ": "5",
            "QSO_DATE": parts1[0],
            "TIME_ON": parts1[1]
        ])

        let qso2 = QSORecordModel(fields: [
            "CALL": "DL1ABC",
            "BAND": "20M",
            "MODE": "CW",
            "CQZ": "14",
            "QSO_DATE": parts2[0],
            "TIME_ON": parts2[1]
        ])

        let qso3 = QSORecordModel(fields: [
            "CALL": "EP2AES",
            "BAND": "40M",
            "MODE": "CW",
            "CQZ": "21",
            "QSO_DATE": parts3[0],
            "TIME_ON": parts3[1]
        ])

        engine.recalculate(qsoRecords: [qso1, qso2, qso3])

        // Test 1: Total QSOs
        assertTest(engine.totalQSOs == 3, "Total QSOs is 3")

        // Test 2: Rolling Rates (3 QSOs in last 10 mins => 3 * 6 = 18 QSO/hr)
        assertTest(engine.rolling10MinRate == 18, "Rolling 10m rate is 18/hr (got \(engine.rolling10MinRate))")
        assertTest(engine.rolling60MinRate == 3, "Rolling 60m rate is 3/hr (got \(engine.rolling60MinRate))")
        assertTest(engine.peakHourlyRate >= 3, "Peak rate recorded")

        // Test 3: Multiplier Counts
        assertTest(engine.totalDXCCMultipliers >= 3, "At least 3 DXCC countries worked (US, Germany, Iran) (got \(engine.totalDXCCMultipliers))")
        assertTest(engine.totalZoneMultipliers >= 3, "At least 3 Zones worked (5, 14, 21) (got \(engine.totalZoneMultipliers))")

        // Test 4: Band Breakdown
        let band20M = engine.bandSummaries.first(where: { $0.band == "20M" })
        assertTest(band20M != nil, "20M summary exists")
        assertTest(band20M?.qsoCount == 2, "20M has 2 QSOs")
        assertTest(band20M?.dxccCount == 2, "20M has 2 DXCCs")
        assertTest(band20M?.zoneCount == 2, "20M has 2 Zones")

        let band40M = engine.bandSummaries.first(where: { $0.band == "40M" })
        assertTest(band40M != nil, "40M summary exists")
        assertTest(band40M?.qsoCount == 1, "40M has 1 QSO")
        assertTest(band40M?.zoneCount == 1, "40M has 1 Zone")

        // Test 5: Streak
        assertTest(engine.currentStreak == 3, "Active streak of 3 consecutive QSOs")

        print("--- Contest Rate Matrix Regression Tests Completed ---")
        return passed
    }
}
