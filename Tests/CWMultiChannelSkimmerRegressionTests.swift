//
//  CWMultiChannelSkimmerRegressionTests.swift
//  YAAM Tests
//
//  Unit and Regression Tests for Native Multi-Channel CW Audio Passband Mini-Skimmer
//

import AVFoundation
import Foundation
@testable import YAAM

@main
@MainActor
public struct CWMultiChannelSkimmerRegressionTests {
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

        print("--- Starting CW Multi-Channel Skimmer Regression Tests ---")

        let skimmer = CWMultiChannelSkimmerEngine.shared

        // Test 1: Channel Bank Setup & Frequency Coverage
        assertTest(skimmer.channels.count == 10, "Channel bank contains exactly 10 parallel channels")
        assertTest(skimmer.channels.first?.centerFreqHz == 450.0, "First channel is at 450 Hz")
        assertTest(skimmer.channels.last?.centerFreqHz == 900.0, "Last channel is at 900 Hz")
        assertTest(skimmer.channels.contains(where: { $0.centerFreqHz == 650.0 }), "Channel bank covers standard 650 Hz sidetone center")

        // Test 2: Candidate Callsign Identification Heuristics
        assertTest(CWMultiChannelSkimmerEngine.isCandidateCallsign("W1AW"), "W1AW is candidate callsign")
        assertTest(CWMultiChannelSkimmerEngine.isCandidateCallsign("DL1ABC"), "DL1ABC is candidate callsign")
        assertTest(CWMultiChannelSkimmerEngine.isCandidateCallsign("JA1BJK"), "JA1BJK is candidate callsign")
        assertTest(CWMultiChannelSkimmerEngine.isCandidateCallsign("EP2AES"), "EP2AES is candidate callsign")
        assertTest(CWMultiChannelSkimmerEngine.isCandidateCallsign("4X4DK"), "4X4DK is candidate callsign")
        assertTest(!CWMultiChannelSkimmerEngine.isCandidateCallsign("CQ"), "CQ is not candidate callsign")
        assertTest(!CWMultiChannelSkimmerEngine.isCandidateCallsign("TEST"), "TEST is not candidate callsign")
        assertTest(!CWMultiChannelSkimmerEngine.isCandidateCallsign("5NN"), "5NN is not candidate callsign")
        assertTest(!CWMultiChannelSkimmerEngine.isCandidateCallsign("599"), "599 is not candidate callsign")
        assertTest(!CWMultiChannelSkimmerEngine.isCandidateCallsign("73"), "73 is not candidate callsign")
        assertTest(!CWMultiChannelSkimmerEngine.isCandidateCallsign("HELLO"), "Words without digits are not candidate callsigns")
        assertTest(!CWMultiChannelSkimmerEngine.isCandidateCallsign("12345"), "Words without letters are not candidate callsigns")

        // Test 3: Zero-Beat Frequency Delta Calculations
        let spotA = CWSkimmerSpot(callsign: "W1AW", audioFreqHz: 650.0, snrDb: 18.0, wpm: 24, snippet: "CQ TEST")
        assertTest(skimmer.calculateZeroBeatDelta(for: spotA, nominalPitch: 650.0) == 0.0, "Zero-Beat delta at center is 0 Hz")

        let spotHigh = CWSkimmerSpot(callsign: "DL1ABC", audioFreqHz: 725.0, snrDb: 15.0, wpm: 26, snippet: "CQ TEST")
        assertTest(skimmer.calculateZeroBeatDelta(for: spotHigh, nominalPitch: 650.0) == 75.0, "Zero-Beat delta above center is +75 Hz")

        let spotLow = CWSkimmerSpot(callsign: "JA1BJK", audioFreqHz: 500.0, snrDb: 20.0, wpm: 22, snippet: "5NN 001")
        assertTest(skimmer.calculateZeroBeatDelta(for: spotLow, nominalPitch: 650.0) == -150.0, "Zero-Beat delta below center is -150 Hz")

        // Test 4: Spot Equality and Deduplication
        let spot1 = CWSkimmerSpot(callsign: "W1AW", audioFreqHz: 500.0, snrDb: 12.0, wpm: 20, snippet: "CQ")
        let spot2 = CWSkimmerSpot(callsign: "W1AW", audioFreqHz: 508.0, snrDb: 16.0, wpm: 22, snippet: "CQ TEST W1AW")
        assertTest(spot1 == spot2, "Spots with same callsign within 25 Hz are considered identical")

        let spotDifferentCall = CWSkimmerSpot(callsign: "K3LR", audioFreqHz: 500.0, snrDb: 14.0, wpm: 20, snippet: "CQ")
        assertTest(spot1 != spotDifferentCall, "Spots with different callsigns are not equal")

        // Test 5: Multi-Station Audio Synthesis
        let simStations: [(call: String, freq: Double, wpm: Int, text: String)] = [
            ("W1AW", 500.0, 24, "CQ TEST W1AW"),
            ("DL1ABC", 650.0, 26, "CQ TEST DL1ABC"),
            ("JA1BJK", 800.0, 28, "JA1BJK 5NN 001")
        ]
        let multiBuf = skimmer.synthesizeMultiStationBuffer(stations: simStations)
        assertTest(multiBuf != nil, "synthesizeMultiStationBuffer produces non-nil buffer")
        assertTest((multiBuf?.frameLength ?? 0) > 0, "synthesizeMultiStationBuffer produces valid frames")

        // Test 6: Parallel Audio Processing on Multi-Station Buffer
        if let buf = multiBuf {
            skimmer.processAudioBuffer(buf)
            assertTest(skimmer.audioInputLevel > 0.0, "processAudioBuffer updates audioInputLevel")

            // Active channels (500 Hz, 650 Hz, 800 Hz) should measure higher energy than idle channels (450 Hz, 900 Hz)
            let ch500 = skimmer.channels.first(where: { $0.centerFreqHz == 500.0 })
            let ch650 = skimmer.channels.first(where: { $0.centerFreqHz == 650.0 })
            let ch800 = skimmer.channels.first(where: { $0.centerFreqHz == 800.0 })
            let ch450 = skimmer.channels.first(where: { $0.centerFreqHz == 450.0 })

            assertTest((ch500?.signalLevel ?? 0.0) > 0.001, "Channel at 500 Hz detects carrier energy")
            assertTest((ch650?.signalLevel ?? 0.0) > 0.001, "Channel at 650 Hz detects carrier energy")
            assertTest((ch800?.signalLevel ?? 0.0) > 0.001, "Channel at 800 Hz detects carrier energy")
            assertTest((ch650?.signalLevel ?? 0.0) > (ch450?.signalLevel ?? 0.0), "Active channel 650 Hz has higher energy than quiet 450 Hz")
        }

        // Test 7: Spot Roster Management & Clear
        skimmer.clearRoster()
        assertTest(skimmer.spots.isEmpty, "clearRoster empties all spots")

        let testSpot = CWSkimmerSpot(callsign: "OH2BH", audioFreqHz: 650.0, snrDb: 22.0, wpm: 28, snippet: "CQ TEST OH2BH")
        skimmer.spots.append(testSpot)
        assertTest(skimmer.spots.count == 1, "Appended spot is present in roster")
        assertTest(skimmer.spots.first?.callsign == "OH2BH", "Spot callsign preserved as OH2BH")

        skimmer.tuneToSpot(testSpot)
        assertTest(skimmer.pendingSelectedCallsign == "OH2BH", "tuneToSpot sets pendingSelectedCallsign to OH2BH")
        assertTest(skimmer.lastZeroBeatAdjustmentHz == 0.0, "Zero-Beat adjustment for 650Hz with nominal 650Hz is 0 Hz")

        skimmer.clearRoster()
        assertTest(skimmer.spots.isEmpty, "clearRoster clears roster again")

        // Test 8: Simulation Lifecycle
        skimmer.startSimulation()
        assertTest(skimmer.isSimulationActive, "startSimulation activates simulation mode")
        skimmer.stopSimulation()
        assertTest(!skimmer.isSimulationActive, "stopSimulation deactivates simulation mode")

        print("--- CW Multi-Channel Skimmer Regression Tests Completed ---")
        return passed
    }
}
