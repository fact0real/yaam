//
//  CallHistoryLookupRegressionTests.swift
//  YAAM Tests
//
//  Unit and Regression Tests for Call History Lookup Engine,
//  Exchange Pre-fill, Macro Token Expansion, and Paddle Break-In.
//

import Foundation
@testable import YAAM

@main
@MainActor
public struct CallHistoryLookupRegressionTests {
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

        print("--- Starting Call History & Pre-fill Regression Tests ---")

        let engine = CallHistoryLookupEngine.shared

        // Test 1: Seed Database Integrity
        assertTest(engine.totalRecordsCount >= 30, "Seed database loaded at least 30 verified contest callsigns (count: \(engine.totalRecordsCount))")

        // Test 2: Known Station Lookups
        let w1aw = engine.lookup(callsign: "W1AW")
        assertTest(w1aw != nil, "W1AW found in database")
        assertTest(w1aw?.state == "CT", "W1AW state is CT")
        assertTest(w1aw?.cqZone == 5, "W1AW CQ Zone is 5")
        assertTest(w1aw?.name == "HQ", "W1AW name is HQ")

        let k3lr = engine.lookup(callsign: "k3lr") // Test case insensitivity
        assertTest(k3lr != nil, "k3lr found (case insensitive)")
        assertTest(k3lr?.name == "Tim", "K3LR operator name is Tim")
        assertTest(k3lr?.state == "PA", "K3LR state is PA")
        assertTest(k3lr?.cqZone == 5, "K3LR zone is 5")

        let ep2aes = engine.lookup(callsign: "EP2AES")
        assertTest(ep2aes != nil, "EP2AES found")
        assertTest(ep2aes?.name == "Amir", "EP2AES operator name is Amir")
        assertTest(ep2aes?.cqZone == 21, "EP2AES zone is 21")

        // Test 3: Logbook Self-Learning
        let learnedQSO = QSORecordModel(fields: [
            "CALL": "TEST9XYZ",
            "NAME": "DAVE",
            "STATE": "FL",
            "ARRL_SECT": "SFL",
            "CQZ": "5",
            "EXCHANGE": "KW"
        ])
        engine.learnFromLogbook(records: [learnedQSO])

        let learnedRecord = engine.lookup(callsign: "TEST9XYZ")
        assertTest(learnedRecord != nil, "TEST9XYZ learned from logbook")
        assertTest(learnedRecord?.name == "DAVE", "Learned name is DAVE")
        assertTest(learnedRecord?.state == "FL", "Learned state is FL")
        assertTest(learnedRecord?.cqZone == 5, "Learned CQ zone is 5")
        assertTest(learnedRecord?.source == .logbookLearned, "Source is .logbookLearned")

        // Test 4: CallHistory.txt Standard File Import
        let mockCallHistoryFile = """
        # N1MM / Win-Test Sample Call History
        !!Order!!, Call, Name, Sec, State, Zone, Grid, Exch
        W4TEST, Charlie, NFL, FL, 5, EM70, 100
        DL9ABC, Hans, , , 14, JO31, 14
        JA9XYZ, Ken, , , 25, PM86, 25
        """
        let importedCount = engine.importCallHistory(content: mockCallHistoryFile, filename: "MockCallHistory.txt")
        assertTest(importedCount == 3, "Imported 3 records from mock CallHistory.txt (got \(importedCount))")

        let w4test = engine.lookup(callsign: "W4TEST")
        assertTest(w4test != nil, "W4TEST resolved from imported file")
        assertTest(w4test?.name == "Charlie", "W4TEST name is Charlie")
        assertTest(w4test?.state == "FL", "W4TEST state is FL")
        assertTest(w4test?.arrlSection == "NFL", "W4TEST section is NFL")
        assertTest(w4test?.userExchange == "100", "W4TEST exchange is 100")
        assertTest(w4test?.source == .importedFile, "Source is .importedFile")

        // Test 5: Macro Token Expansion in CWKeyerService
        let keyer = CWKeyerService.shared
        let expandedW1AW = keyer.expandMacro("TU {HISNAME} {HISSTATE} {HISZONE} 5NN", myCall: "AA1AA", call: "W1AW")
        assertTest(expandedW1AW.contains("HQ"), "Macro expanded {HISNAME} to HQ")
        assertTest(expandedW1AW.contains("CT"), "Macro expanded {HISSTATE} to CT")
        assertTest(expandedW1AW.contains("05"), "Macro expanded {HISZONE} to 05")

        let expandedK3LR = keyer.expandMacro("TNX {HISNAME} 73", myCall: "AA1AA", call: "K3LR")
        assertTest(expandedK3LR.contains("TIM"), "Macro expanded {HISNAME} to TIM")

        // Test 6: Paddle Break-In Handling
        keyer.isTransmitting = true
        keyer.handlePaddleBreakIn()
        assertTest(!keyer.isTransmitting, "Paddle break-in immediately aborts transmission")
        assertTest(keyer.isPaddleBreakInActive, "isPaddleBreakInActive is set to true")

        // WinKeyer driver break-in trigger
        var breakInTriggered = false
        WinKeyerDriver.shared.onPaddleBreakIn = {
            breakInTriggered = true
        }
        WinKeyerDriver.shared.triggerPaddleBreakIn()
        assertTest(breakInTriggered, "WinKeyerDriver triggerPaddleBreakIn fires callback")

        print("--- Call History & Pre-fill Regression Tests Completed ---")
        return passed
    }
}
