//
//  CWESMEngineRegressionTests.swift
//  YAAM Tests
//
//  Regression & Unit Tests for Contest Enter-Sends-Message (ESM) State Machine
//

import Foundation
@testable import YAAM

@main
@MainActor
public struct CWESMEngineRegressionTests {
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

        let esm = CWESMEngine.shared

        // Test 1: RUN Mode with Empty Callsign -> Send CQ
        esm.operatingMode = .run
        esm.resetForNewQSO()
        let action1 = esm.determineAction(callsign: "", receivedExchange: "", receivedSerial: "")
        if case .sendCQ(let tmpl) = action1 {
            assertTest(true, "RUN mode with empty call triggers .sendCQ")
            assertTest(tmpl.contains("{MYCALL}"), "RUN CQ template contains {MYCALL}")
        } else {
            assertTest(false, "RUN mode with empty call triggers .sendCQ")
        }
        assertTest(action1.buttonTitle == "⚡ CQ (↵)", "Button title for CQ is '⚡ CQ (↵)'")

        // Test 2: RUN Mode with Callsign Entered -> Send Exchange
        let action2 = esm.determineAction(callsign: "W1AW", receivedExchange: "", receivedSerial: "")
        if case .sendExchange(let call, let tmpl) = action2 {
            assertTest(call == "W1AW", "RUN mode targets correct callsign W1AW")
            assertTest(tmpl.contains("5NN") || tmpl.contains("{SERIAL}"), "RUN Exchange template contains 5NN or {SERIAL}")
        } else {
            assertTest(false, "RUN mode with callsign entered triggers .sendExchange")
        }
        assertTest(action2.buttonTitle == "⚡ Exch (↵)", "Button title for Exchange is '⚡ Exch (↵)'")

        // Test 3: RUN Mode with Exchange Entered -> Send TU & Log
        let action3 = esm.determineAction(callsign: "W1AW", receivedExchange: "599 001", receivedSerial: "")
        if case .sendTUAndLog(let tmpl) = action3 {
            assertTest(true, "RUN mode with exchange received triggers .sendTUAndLog")
            assertTest(tmpl.contains("TU"), "TU template contains 'TU'")
        } else {
            assertTest(false, "RUN mode with exchange received triggers .sendTUAndLog")
        }
        assertTest(action3.buttonTitle == "⚡ TU & Log (↵)", "Button title for TU is '⚡ TU & Log (↵)'")

        // Test 4: RUN Mode after Exchange Sent flag -> Send TU & Log (Even if exchange box empty)
        esm.hasSentExchangeInCurrentQSO = true
        let action4 = esm.determineAction(callsign: "W1AW", receivedExchange: "", receivedSerial: "")
        if case .sendTUAndLog = action4 {
            assertTest(true, "RUN mode after exchange is sent triggers .sendTUAndLog on subsequent Enter")
        } else {
            assertTest(false, "RUN mode after exchange is sent triggers .sendTUAndLog on subsequent Enter")
        }

        // Test 5: S&P Mode with Empty Callsign -> Prompt Callsign
        esm.operatingMode = .searchAndPounce
        esm.resetForNewQSO()
        let spAction1 = esm.determineAction(callsign: "", receivedExchange: "", receivedSerial: "")
        assertTest(spAction1 == .promptCallsign, "S&P mode with empty call triggers .promptCallsign")
        assertTest(spAction1.buttonTitle == "⚡ Enter Call", "Button title for prompt is '⚡ Enter Call'")

        // Test 6: S&P Mode with Callsign Entered -> Send My Call
        let spAction2 = esm.determineAction(callsign: "K1TTT", receivedExchange: "", receivedSerial: "")
        if case .sendMyCall(let tmpl) = spAction2 {
            assertTest(true, "S&P mode with call entered triggers .sendMyCall")
            assertTest(tmpl.contains("{MYCALL}"), "S&P call template contains {MYCALL}")
        } else {
            assertTest(false, "S&P mode with call entered triggers .sendMyCall")
        }
        assertTest(spAction2.buttonTitle == "⚡ My Call (↵)", "Button title is '⚡ My Call (↵)'")

        // Test 7: S&P Mode with Exchange Entered -> Send My Exchange & Log
        let spAction3 = esm.determineAction(callsign: "K1TTT", receivedExchange: "005", receivedSerial: "")
        if case .sendMyExchangeAndLog(let tmpl) = spAction3 {
            assertTest(true, "S&P mode with exchange entered triggers .sendMyExchangeAndLog")
            assertTest(tmpl.contains("5NN") || tmpl.contains("{SERIAL}"), "S&P exchange contains report/serial")
        } else {
            assertTest(false, "S&P mode with exchange entered triggers .sendMyExchangeAndLog")
        }
        assertTest(spAction3.buttonTitle == "⚡ Exch & Log (↵)", "Button title is '⚡ Exch & Log (↵)'")

        // Test 8: Callsign Change mid-QSO re-arms exchange
        esm.operatingMode = .run
        esm.hasSentExchangeInCurrentQSO = true
        esm.onCallsignChanged("W1AW/3")
        assertTest(!esm.hasSentExchangeInCurrentQSO, "Altering callsign re-arms exchange flag")
        let actionAfterCorrection = esm.determineAction(callsign: "W1AW/3", receivedExchange: "", receivedSerial: "")
        if case .sendExchange(let call, _) = actionAfterCorrection {
            assertTest(call == "W1AW/3", "Exchange correctly targeted to updated callsign")
        } else {
            assertTest(false, "Exchange correctly targeted to updated callsign")
        }

        // Test 9: Reset for new QSO clears all flags
        esm.hasSentExchangeInCurrentQSO = true
        esm.hasSentCallInCurrentQSO = true
        esm.resetForNewQSO()
        assertTest(!esm.hasSentExchangeInCurrentQSO, "resetForNewQSO resets hasSentExchange")
        assertTest(!esm.hasSentCallInCurrentQSO, "resetForNewQSO resets hasSentCall")

        return passed
    }
}
