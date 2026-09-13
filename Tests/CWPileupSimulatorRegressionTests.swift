//
//  CWPileupSimulatorRegressionTests.swift
//  YAAM Tests
//
//  Unit and Regression Tests for Native CW Pileup Contest Simulator & DSP Engine
//

import AVFoundation
import Foundation
@testable import YAAM

@main
@MainActor
public struct CWPileupSimulatorRegressionTests {
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

        print("--- Starting CW Pileup Simulator Regression Tests ---")

        let sim = CWPileupSimulatorEngine.shared

        // Test 1: Difficulty Presets
        sim.applyDifficultyPreset(.beginner)
        assertTest(sim.difficulty.stationCountRange == 1...1, "Beginner has 1 station count range")
        assertTest(sim.baseWPM == 18, "Beginner default WPM is 18")
        assertTest(!sim.qsbEnabled, "Beginner QSB is disabled")

        sim.applyDifficultyPreset(.contester)
        assertTest(sim.difficulty.stationCountRange == 2...3, "Contester has 2...3 station count range")
        assertTest(sim.baseWPM == 26, "Contester default WPM is 26")
        assertTest(sim.qsbEnabled, "Contester QSB is enabled")

        sim.applyDifficultyPreset(.extremePileup)
        assertTest(sim.difficulty.stationCountRange == 4...5, "Extreme Pileup has 4...5 station count range")
        assertTest(sim.baseWPM == 38, "Extreme default WPM is 38")
        assertTest(sim.qrmEnabled, "Extreme QRM is enabled")

        // Test 2: Callsign Database Integrity
        assertTest(CWPileupSimulatorEngine.callsignDatabase.count >= 40, "Callsign database contains at least 40 stations")
        assertTest(CWPileupSimulatorEngine.callsignDatabase.contains("EP2AES") || CWPileupSimulatorEngine.callsignDatabase.contains("DL1ABC"), "Database contains standard contest calls")

        // Test 3: Contest Prefix Extraction
        assertTest(CWPileupSimulatorEngine.extractContestPrefix(from: "DL1ABC") == "DL1", "Prefix extraction DL1ABC -> DL1")
        assertTest(CWPileupSimulatorEngine.extractContestPrefix(from: "W1AW") == "W1", "Prefix extraction W1AW -> W1")
        assertTest(CWPileupSimulatorEngine.extractContestPrefix(from: "JA7NVF") == "JA7", "Prefix extraction JA7NVF -> JA7")
        assertTest(CWPileupSimulatorEngine.extractContestPrefix(from: "EP2AES") == "EP2", "Prefix extraction EP2AES -> EP2")
        assertTest(CWPileupSimulatorEngine.extractContestPrefix(from: "4X4DK") == "4X4", "Prefix extraction 4X4DK -> 4X4")
        assertTest(CWPileupSimulatorEngine.extractContestPrefix(from: "9A1A") == "9A1", "Prefix extraction 9A1A -> 9A1")

        // Test 4: Session Lifecycle & Reset State
        sim.startSession()
        assertTest(sim.isRunning == true, "startSession sets isRunning to true")
        assertTest(sim.qsoCount == 0, "Initial QSO count is 0")
        assertTest(sim.totalScore == 0, "Initial score is 0")
        assertTest(sim.draftSerialSent == 1, "Initial sent serial is 1")
        assertTest(sim.sessionStartTime != nil, "sessionStartTime is initialized")

        sim.pauseSession()
        assertTest(sim.isRunning == false, "pauseSession pauses running state")
        assertTest(sim.state == .paused, "State is .paused")

        sim.resumeSession()
        assertTest(sim.isRunning == true, "resumeSession restores running state")

        sim.stopSession()
        assertTest(sim.isRunning == false, "stopSession terminates running state")
        assertTest(sim.state == .idle, "State returns to .idle")

        // Test 5: Virtual Station Model & Active State Matching
        let testStation = VirtualStation(
            callsign: "DL1ABC",
            pitchHz: 650.0,
            wpm: 28,
            signalStrength: 0.9,
            qsbSpeed: 0.2,
            qsbPhase: 0.0,
            delayOffsetSec: 0.1,
            serialNumber: 42
        )
        assertTest(testStation.callsign == "DL1ABC", "VirtualStation preserves callsign")
        assertTest(testStation.serialNumber == 42, "VirtualStation preserves serial number")
        assertTest(!testStation.isLogged, "VirtualStation initially not logged")

        // Test 6: ESM Logic & Action Transitions
        sim.startSession()
        sim.draftCallsign = ""
        // Empty callsign -> Enter triggers CQ
        sim.handleEnterKey()
        assertTest(sim.state == .transmittingCQ, "Enter with empty callsign enters .transmittingCQ")
        assertTest(sim.currentTransmittingText.contains("CQ TEST"), "Transmitting text contains 'CQ TEST'")

        // Operator finishes CQ -> Pileup calls -> Operator enters callsign -> Enter triggers Exchange
        sim.state = .pileupCalling
        sim.draftCallsign = "K3LR"
        sim.handleEnterKey()
        assertTest(sim.state == .transmittingExchange, "Enter with callsign entered enters .transmittingExchange")
        assertTest(sim.currentTransmittingText.contains("K3LR 5NN"), "Transmitting text contains target call and 5NN")

        // Station responding -> Enter triggers TU & Log
        sim.state = .stationResponding
        sim.activeTargetStation = VirtualStation(
            callsign: "K3LR",
            pitchHz: 670.0,
            wpm: 26,
            signalStrength: 0.85,
            qsbSpeed: 0.2,
            qsbPhase: 0.0,
            delayOffsetSec: 0.1,
            serialNumber: 15
        )
        sim.draftSerialRcvd = "015"
        sim.handleEnterKey()
        assertTest(sim.state == .transmittingTU, "Enter during station response enters .transmittingTU")
        assertTest(sim.qsoCount == 1, "QSO is recorded in contest log")
        assertTest(sim.qsoRecords.first?.callsign == "K3LR", "Recorded QSO matches K3LR")
        assertTest(sim.qsoRecords.first?.points == 3, "Valid QSO earns 3 points")
        assertTest(sim.draftSerialSent == 2, "Serial sent increments to 2")
        assertTest(sim.multiplierCount >= 1, "Multiplier count increments")
        assertTest(sim.totalScore >= 3, "Total score is updated")
        assertTest(sim.currentStreak == 1, "Current streak increments to 1")
        assertTest(sim.accuracyPercentage == 100.0, "Accuracy percentage is 100%")

        // Test 7: Abort Transmission (Esc)
        sim.abortTransmission()
        assertTest(sim.currentTransmittingText.isEmpty, "Abort clears transmitting text")
        assertTest(sim.state == .idle, "Abort returns state to idle")

        // Test 8: Audio Synthesis Engine - Single Station Buffer
        let singleBuf = sim.synthesizeSingleStationBuffer(
            text: "TEST",
            pitchHz: 650.0,
            wpm: 25,
            amplitude: 0.8,
            attenuateByFilter: false,
            addQRN: false
        )
        assertTest(singleBuf != nil, "synthesizeSingleStationBuffer produces non-nil buffer")
        assertTest((singleBuf?.frameLength ?? 0) > 0, "synthesizeSingleStationBuffer has positive frame count")

        // Test 9: Audio Synthesis Engine - Multi-Station Pileup Buffer
        let stationA = VirtualStation(callsign: "W1AW", pitchHz: 610.0, wpm: 24, signalStrength: 0.8, qsbSpeed: 0.2, qsbPhase: 0.0, delayOffsetSec: 0.05, serialNumber: 1)
        let stationB = VirtualStation(callsign: "JA1BJK", pitchHz: 690.0, wpm: 28, signalStrength: 0.7, qsbSpeed: 0.3, qsbPhase: 1.0, delayOffsetSec: 0.15, serialNumber: 2)
        let multiBuf = sim.synthesizeMultiStationPileupBuffer(stations: [stationA, stationB])
        assertTest(multiBuf != nil, "synthesizeMultiStationPileupBuffer produces non-nil buffer")
        assertTest((multiBuf?.frameLength ?? 0) > 0, "synthesizeMultiStationPileupBuffer has positive frame count")

        // Test 10: Filter Bandwidth Attenuation Logic
        sim.centerPitchHz = 650.0
        sim.filterBandwidthHz = 250.0 // Half-BW = 125 Hz. Passband is 525 to 775 Hz.
        let inBandBuf = sim.synthesizeSingleStationBuffer(
            text: "E",
            pitchHz: 650.0,
            wpm: 20,
            amplitude: 0.8,
            attenuateByFilter: true,
            addQRN: false
        )
        let outBandBuf = sim.synthesizeSingleStationBuffer(
            text: "E",
            pitchHz: 950.0, // 300Hz away from center -> well outside 250Hz passband!
            wpm: 20,
            amplitude: 0.8,
            attenuateByFilter: true,
            addQRN: false
        )
        assertTest(inBandBuf != nil && outBandBuf != nil, "Both in-band and out-of-band buffers synthesize")

        sim.stopSession()

        print("--- CW Pileup Simulator Regression Tests Completed ---")
        return passed
    }
}
