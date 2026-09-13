//
//  CWAcademyRegressionTests.swift
//  YAAM Tests
//
//  Unit & Regression tests for CWAcademyEngine, Koch Progression, Callsign Sprint,
//  and CWReferenceDatabase.
//

import Foundation
@testable import YAAM

@main
@MainActor
public struct CWAcademyRegressionTests {
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

        // Test 1: Koch sequence integrity (40 characters, unique)
        let seq = CWAcademyEngine.kochSequence
        assertTest(seq.count == 40, "Koch sequence contains exactly 40 elements")
        let uniqueSeq = Set(seq)
        assertTest(uniqueSeq.count == 40, "All 40 Koch characters are unique")
        assertTest(seq[0] == "K" && seq[1] == "M", "First two Koch characters are K and M")

        // Test 2: Callsign generator
        for _ in 0..<10 {
            let call = CWAcademyEngine.shared.generateRealisticCallsign()
            assertTest(!call.isEmpty && call.count >= 3 && call.count <= 7, "Generated realistic callsign \(call)")
            assertTest(call.contains(where: \.isNumber), "Callsign contains at least one digit: \(call)")
        }

        // Test 3: Reference Database completeness
        let db = CWReferenceDatabase.shared
        assertTest(db.items.count >= 25, "Reference database contains at least 25 items")
        let qCodes = db.items.filter { $0.category == .qCode }
        let prosigns = db.items.filter { $0.category == .prosign }
        let abbrs = db.items.filter { $0.category == .abbreviation }

        assertTest(!qCodes.isEmpty, "Contains Q-Codes (count: \(qCodes.count))")
        assertTest(!prosigns.isEmpty, "Contains Prosigns (count: \(prosigns.count))")
        assertTest(!abbrs.isEmpty, "Contains Abbreviations (count: \(abbrs.count))")

        assertTest(qCodes.contains(where: { $0.code == "QTH" }), "Contains QTH")
        assertTest(qCodes.contains(where: { $0.code == "QSL" }), "Contains QSL")
        assertTest(qCodes.contains(where: { $0.code == "QRZ?" }), "Contains QRZ?")
        assertTest(prosigns.contains(where: { $0.code == "<AR>" }), "Contains <AR>")
        assertTest(prosigns.contains(where: { $0.code == "<SK>" }), "Contains <SK>")

        // Test 4: Quiz generator produces 4 choices with valid index
        if let quiz = db.generateQuizQuestion() {
            assertTest(quiz.options.count == 4, "Quiz question has exactly 4 options")
            assertTest(quiz.correctOptionIndex >= 0 && quiz.correctOptionIndex < 4, "Correct option index is within 0...3")
        } else {
            assertTest(false, "Failed to generate quiz question")
        }

        // Test 5: Answer verification
        CWAcademyEngine.shared.currentPrompt = "KMR"
        let isCorrect = CWAcademyEngine.shared.submitAnswer("kmr")
        assertTest(isCorrect, "Case-insensitive submission matches prompt")
        let isWrong = CWAcademyEngine.shared.submitAnswer("XYZ")
        assertTest(!isWrong, "Incorrect submission detected properly")

        return passed
    }
}
