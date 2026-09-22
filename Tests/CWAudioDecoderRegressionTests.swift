//
//  CWAudioDecoderRegressionTests.swift
//  YAAM Tests
//
//  Comprehensive Regression & Accuracy Tests for Wideband CW Audio Decoder Engine.
//  Tests Quadrature Demodulation, Auto-Tune, Pitch Hunting (300-1800 Hz),
//  and verifies ground truth decoding on real user on-air recordings.
//

import AVFoundation
import Foundation
@testable import YAAM

@main
@MainActor
public struct CWAudioDecoderRegressionTests {
    public static func main() async {
        let passed = await runAllTests()
        exit(passed ? 0 : 1)
    }

    public static func runAllTests() async -> Bool {
        var passed = true

        func assertTest(_ condition: Bool, _ name: String) {
            if !condition {
                print("❌ FAIL: \(name)")
                passed = false
            } else {
                print("✅ PASS: \(name)")
            }
        }

        print("=== CWAudioDecoderEngine Wideband DSP Regression Suite ===")

        let decoder = CWAudioDecoderEngine.shared

        // Test 1: Wideband Tuning Range (300 Hz - 1800 Hz)
        decoder.setPitch(200.0)
        assertTest(decoder.centerFrequencyHz == 300.0, "Pitch lower clamp at 300 Hz (requested 200 Hz -> \(decoder.centerFrequencyHz) Hz)")

        decoder.setPitch(2500.0)
        assertTest(decoder.centerFrequencyHz == 1800.0, "Pitch upper clamp at 1800 Hz (requested 2500 Hz -> \(decoder.centerFrequencyHz) Hz)")

        decoder.setPitch(1224.0)
        assertTest(abs(decoder.centerFrequencyHz - 1224.0) < 0.1, "Pitch sets correctly to 1224 Hz")

        // Test 2: User Audio File Decoding & Pitch Auto-Detection
        let userFiles: [(filename: String, expectedWord: String)] = [
            ("uploaded_media_0_1790066363961.m4a", "OXIDE"),
            ("uploaded_media_1_1790066363961.m4a", "FIELD"),
            ("uploaded_media_2_1790066363961.m4a", "COLOR"),
            ("uploaded_media_3_1790066363961.m4a", "RELAY")
        ]

        let baseUploadDir = "/Users/factoreal/.gemini/antigravity/brain/e8a67704-905b-45d8-8a79-a42a67a5773e/.user_uploaded"

        for (filename, expectedWord) in userFiles {
            let fileURL = URL(fileURLWithPath: "\(baseUploadDir)/\(filename)")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    print("\n--- Testing file: \(filename) (Expected: \(expectedWord)) ---")
                    let decodedText = try await decoder.decodeAudioFile(at: fileURL)
                    print("Decoded output: '\(decodedText)'")
                    print("Detected pitch: \(Int(decoder.centerFrequencyHz)) Hz")
                    print("Estimated WPM: \(String(format: "%.1f", decoder.estimatedWPM))")
                    print("Estimated SNR: \(String(format: "%.1f dB", decoder.signalToNoiseRatioDb))")
                    print("Dit/Dah ratio: 1 : \(String(format: "%.2f", decoder.ditDahRatio))")

                    assertTest(decodedText.contains(expectedWord), "Accurately decoded '\(expectedWord)' from \(filename) (got: '\(decodedText)')")
                    assertTest(abs(decoder.centerFrequencyHz - 1224.0) <= 50.0, "Auto-detected carrier pitch around 1224 Hz (got: \(Int(decoder.centerFrequencyHz)) Hz)")
                    assertTest(decoder.estimatedWPM >= 9.0 && decoder.estimatedWPM <= 16.0, "Estimated WPM within 9-16 range for 12.3 WPM audio (got: \(decoder.estimatedWPM))")
                    assertTest(decoder.signalToNoiseRatioDb >= 6.0, "SNR health >= +6 dB (got: \(decoder.signalToNoiseRatioDb) dB)")
                } catch {
                    assertTest(false, "Failed to decode \(filename): \(error)")
                }
            } else {
                print("⚠️ Skipping \(filename): File not found at \(fileURL.path)")
            }
        }

        // Test 3: Synthetic Tone at 1500 Hz Auto-Tune Verification
        let sampleRate: Double = 48000.0
        let frameCount = 4096
        var synthBuffer = [Float](repeating: 0, count: frameCount)
        let highFreq = 1500.0
        for i in 0..<frameCount {
            synthBuffer[i] = Float(0.5 * sin(2.0 * .pi * highFreq * Double(i) / sampleRate))
        }

        let bins = synthBuffer.withUnsafeBufferPointer { ptr -> [CWSpectrumBin] in
            guard let base = ptr.baseAddress else { return [] }
            return decoder.evaluateFilterBank(channelData: base, frameCount: frameCount)
        }

        if let peakBin = bins.max(by: { $0.magnitude < $1.magnitude }) {
            assertTest(abs(peakBin.frequencyHz - 1500.0) <= 50.0, "Wideband filter bank identified 1500 Hz peak (detected: \(peakBin.frequencyHz) Hz)")
        } else {
            assertTest(false, "Wideband filter bank failed to produce bins")
        }

        return passed
    }
}
