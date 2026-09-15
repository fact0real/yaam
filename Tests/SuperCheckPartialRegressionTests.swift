//
//  SuperCheckPartialRegressionTests.swift
//  YAAM Tests
//
//  Unit and Regression Tests for Super Check Partial (SCP) & Contest Intelligence Engine
//

import Foundation
@testable import YAAM

@main
@MainActor
public struct SuperCheckPartialRegressionTests {
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

        print("--- Starting Super Check Partial (SCP) Regression Tests ---")

        let scp = SuperCheckPartialEngine.shared

        // Test 1: Starter Database Seed Integrity
        assertTest(scp.totalCallsigns >= 100, "Starter database contains at least 100 verified contest callsigns (count: \(scp.totalCallsigns))")
        assertTest(scp.isKnownContestCallsign("W1AW"), "W1AW is in contest database")
        assertTest(scp.isKnownContestCallsign("DL1ABC"), "DL1ABC is in contest database")
        assertTest(scp.isKnownContestCallsign("JA1BJK"), "JA1BJK is in contest database")
        assertTest(scp.isKnownContestCallsign("EP2AES"), "EP2AES is in contest database")
        assertTest(scp.isKnownContestCallsign("K3LR"), "K3LR is in contest database")
        assertTest(scp.isKnownContestCallsign("4X4DK"), "4X4DK is in contest database")

        // Test 2: Exact Matching
        let exactMatches = scp.findEnrichedMatches(for: "W1AW")
        assertTest(!exactMatches.isEmpty, "findEnrichedMatches for W1AW returns results")
        assertTest(exactMatches.first?.isExact == true, "W1AW match is marked as exact")
        assertTest(exactMatches.first?.callsign == "W1AW", "Exact match callsign is W1AW")
        assertTest(exactMatches.first?.country.countryCode == "US", "W1AW entity country code is US")
        assertTest(exactMatches.first?.country.flagEmoji == "🇺🇸", "W1AW flag emoji is 🇺🇸")

        // Test 3: Prefix Matching
        let dlMatches = scp.findEnrichedMatches(for: "DL1")
        assertTest(!dlMatches.isEmpty, "findEnrichedMatches for 'DL1' returns matches")
        assertTest(dlMatches.contains(where: { $0.callsign == "DL1ABC" }), "DL1 matches contain DL1ABC")
        assertTest(dlMatches.first(where: { $0.callsign == "DL1ABC" })?.country.flagEmoji == "🇩🇪", "DL1ABC has German flag 🇩🇪")

        // Test 4: Substring Matching
        let subMatches = scp.findEnrichedMatches(for: "1AW")
        assertTest(subMatches.contains(where: { $0.callsign == "W1AW" }), "Substring '1AW' matches W1AW")

        // Test 5: Multiplier Detection (Unworked Entity)
        let emptyLogMatches = scp.findEnrichedMatches(for: "EP2AES", band: "20M", mode: "CW", qsoRecords: [])
        assertTest(emptyLogMatches.first?.status == .newMultiplier, "Unworked entity in empty log is tagged as .newMultiplier")

        // Test 6: Dupe Detection on Band & Mode
        let dummyQSO = QSORecordModel(fields: [
            "CALL": "W1AW",
            "BAND": "20M",
            "MODE": "CW",
            "FREQ": "14.025",
            "RST_SENT": "599",
            "RST_RCVD": "599"
        ])
        let dupeMatchesSameBand = scp.findEnrichedMatches(for: "W1AW", band: "20M", mode: "CW", qsoRecords: [dummyQSO])
        assertTest(dupeMatchesSameBand.first?.status == .duplicate, "QSO on same band & mode is detected as .duplicate")
        assertTest((dupeMatchesSameBand.first?.workedCount ?? 0) >= 1, "Duplicate workedCount is at least 1")

        // Different band should NOT be duplicate
        let nonDupeDifferentBand = scp.findEnrichedMatches(for: "W1AW", band: "40M", mode: "CW", qsoRecords: [dummyQSO])
        assertTest(nonDupeDifferentBand.first?.status != .duplicate, "QSO on different band (40M) is not a duplicate")

        // Test 7: Sorting Priority (Exact first, then MULT, then NEW, then DUPE)
        let mixedMatches = scp.findEnrichedMatches(for: "W1", band: "20M", mode: "CW", qsoRecords: [dummyQSO])
        assertTest(!mixedMatches.isEmpty, "Mixed query returns results")
        if let first = mixedMatches.first {
            assertTest(first.callsign == "W1AW" || first.isExact, "Exact or highest priority match appears first")
        }

        // Test 8: Short Query Suppression
        let singleCharMatches = scp.findEnrichedMatches(for: "W")
        assertTest(singleCharMatches.isEmpty, "Single character query returns empty list to prevent noise")

        print("--- Super Check Partial (SCP) Regression Tests Completed ---")
        return passed
    }
}
