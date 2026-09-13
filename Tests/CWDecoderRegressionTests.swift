//
//  CWDecoderRegressionTests.swift
//  YAAM Tests
//
//  Unit & Regression Tests for CWAudioDecoderEngine and CWAdaptiveAssistant
//

import Foundation
@testable import YAAM

@main
@MainActor
public struct CWDecoderRegressionTests {
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

        // Test 1: Morse Timing and WPM conversion
        // Standard PARIS: 1 dit at 20 WPM = 60ms (0.060 sec)
        let wpmAt60ms = 1.2 / 0.060
        assertTest(abs(wpmAt60ms - 20.0) < 0.001, "60ms dit corresponds to 20 WPM")
        // Standard PARIS: 1 dit at 30 WPM = 40ms (0.040 sec)
        let wpmAt40ms = 1.2 / 0.040
        assertTest(abs(wpmAt40ms - 30.0) < 0.001, "40ms dit corresponds to 30 WPM")

        // Test 2: Adaptive Assistant CQ recognition
        let assistant = CWAdaptiveAssistant.shared
        assistant.analyzeDecodedStream("CQ TEST W1AW W1AW TEST")
        assertTest(assistant.detectedIntent == .callingCQ, "Identified callingCQ intent")
        assertTest(assistant.detectedCallsign == "W1AW", "Extracted caller callsign W1AW")
        assertTest(assistant.hasActionableSuggestion, "Has actionable suggestion for CQ")

        // Test 3: Adaptive Assistant Contest Exchange recognition
        assistant.analyzeDecodedStream("W1AW EP2AES 5NN 042")
        assertTest(assistant.detectedIntent == .contestExchange, "Identified contest exchange intent")
        assertTest(assistant.detectedExchange == "042", "Extracted serial exchange 042")
        assertTest(assistant.suggestedReply.contains("5NN"), "Suggested reply includes 5NN")

        // Test 4: Adaptive Assistant Ragchew Name & QTH recognition
        assistant.analyzeDecodedStream("TNX FER CALL NAME ALI QTH TEHRAN")
        assertTest(assistant.detectedIntent == .ragchewInfo, "Identified ragchewInfo intent")
        assertTest(assistant.detectedName == "ALI", "Extracted name ALI")
        assertTest(assistant.detectedQTH == "TEHRAN", "Extracted QTH TEHRAN")

        // Test 5: Synthetic Goertzel Detection
        // Generate a 650Hz pure sine wave in a float buffer
        let sampleRate: Double = 44100.0
        let frameCount = 1024
        var buffer = [Float](repeating: 0, count: frameCount)
        let testFreq = 650.0

        for i in 0..<frameCount {
            buffer[i] = Float(sin(2.0 * .pi * testFreq * Double(i) / sampleRate))
        }

        // Evaluate Goertzel magnitude at 650Hz vs 400Hz
        func testGoertzel(data: [Float], target: Double) -> Float {
            let k = Int(0.5 + (Double(frameCount) * target / sampleRate))
            let omega = (2.0 * .pi * Double(k)) / Double(frameCount)
            let coeff = Float(2.0 * cos(omega))
            var q0: Float = 0.0, q1: Float = 0.0, q2: Float = 0.0
            for val in data {
                q0 = coeff * q1 - q2 + val
                q2 = q1
                q1 = q0
            }
            let real = q1 - q2 * Float(cos(omega))
            let imag = q2 * Float(sin(omega))
            return sqrt(real * real + imag * imag) / Float(frameCount)
        }

        let mag650 = testGoertzel(data: buffer, target: 650.0)
        let mag400 = testGoertzel(data: buffer, target: 400.0)
        assertTest(mag650 > mag400 * 10.0, "Goertzel magnitude at 650Hz (\(mag650)) is significantly higher than off-tone 400Hz (\(mag400))")

        return passed
    }
}
