//
//  CWKeyerRegressionTests.swift
//  YAAM Tests
//
//  Regression & Unit Tests for CWKeyerService, Memory Banks, Token Expander & Cut Numbers
//

import Foundation
@testable import YAAM

@main
@MainActor
public struct CWKeyerRegressionTests {
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

        // Test 1: Verify all 4 memory banks have 12 macros
        for bank in CWMemoryBank.allCases {
            let defaults = CWKeyerService.shared.defaultMacros(for: bank)
            assertTest(defaults.count == 12, "Bank \(bank.rawValue) contains exactly 12 macros")
            assertTest(defaults.first?.id == 1, "First macro id is 1 (F1)")
            assertTest(defaults.last?.id == 12, "Last macro id is 12 (F12)")
        }

        // Test 2: Token expansion
        let template = "CQ TEST {MYCALL} {MYCALL} K"
        let expanded = CWKeyerService.shared.expandMacro(
            template,
            myCall: "EP2AES"
        )
        assertTest(expanded == "CQ TEST EP2AES EP2AES K", "Expand {MYCALL} works correctly")

        // Test 3: Cut numbers
        let exchTemplate = "{CALL} {SENT_RST} {SERIAL}"
        let cutExpanded = CWKeyerService.shared.expandMacro(
            exchTemplate,
            myCall: "EP2AES",
            call: "W1AW",
            rst: "599",
            serial: 1
        )
        assertTest(cutExpanded.contains("5NN"), "Cut numbers translates 599 to 5NN")
        assertTest(cutExpanded.contains("TT1"), "Cut serial translates 001 to TT1")

        // Test 4: Custom tokens
        let ragchewTemplate = "TNX {CALL} OP {NAME} QTH {QTH} EXCH {EXCH} BAND {BAND}"
        let ragchewExpanded = CWKeyerService.shared.expandMacro(
            ragchewTemplate,
            myCall: "EP2AES",
            call: "G3ABC",
            name: "John",
            qth: "London",
            exch: "CQWW",
            band: "20M"
        )
        assertTest(ragchewExpanded.contains("G3ABC"), "Expanded his call")
        assertTest(ragchewExpanded.contains("JOHN"), "Expanded name uppercase")
        assertTest(ragchewExpanded.contains("LONDON"), "Expanded QTH uppercase")
        assertTest(ragchewExpanded.contains("CQWW"), "Expanded exchange")
        assertTest(ragchewExpanded.contains("20M"), "Expanded band")

        // Test 5: Morse Alphabet completeness
        assertTest(CWKeyerService.morseAlphabet["A"] == ".-", "Morse code A is .-")
        assertTest(CWKeyerService.morseAlphabet["S"] == "...", "Morse code S is ...")
        assertTest(CWKeyerService.morseAlphabet["O"] == "---", "Morse code O is ---")
        assertTest(CWKeyerService.morseAlphabet["/"] == "-..-.", "Morse code / is -..-.")
        assertTest(CWKeyerService.morseAlphabet["?"] == "..--..", "Morse code ? is ..--..")

        return passed
    }
}
