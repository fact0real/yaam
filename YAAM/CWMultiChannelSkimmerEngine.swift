//
//  CWMultiChannelSkimmerEngine.swift
//  YAAM
//
//  Native Real-Time Multi-Channel CW Audio Passband Mini-Skimmer
//  Monitors the entire receiver audio passband (350 Hz – 1050 Hz) in parallel.
//  Executes a bank of independent DSP Goertzel decoders, tracks multiple simultaneous
//  CW carriers, decodes concurrent Morse streams, and maintains a real-time Skimmer Call Roster
//  with 1-click CAT Zero-Beat tuning, DXCC lookup, and QuickLog integration.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

// MARK: - Skimmer Channel Model

public struct CWSkimmerChannel: Identifiable, Sendable {
    public let id: Int
    public let centerFreqHz: Double
    public var isSignalActive: Bool = false
    public var signalLevel: Float = 0.0
    public var snrDb: Double = 0.0
    public var estimatedWPM: Double = 20.0
    public var rawDecodedText: String = ""
    public var activeCharacterBuffer: String = ""
    public var identifiedCallsign: String? = nil
    public var lastActivity: Date = Date()
}

// MARK: - Skimmer Spot Model

public struct CWSkimmerSpot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let callsign: String
    public let audioFreqHz: Double
    public let rfFreqHz: Double?
    public var snrDb: Double
    public var wpm: Int
    public var snippet: String
    public var intent: CWQSOIntent
    public let countryFlag: String
    public let countryName: String
    public var isMultiplier: Bool
    public var lastHeard: Date

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        callsign: String,
        audioFreqHz: Double,
        rfFreqHz: Double? = nil,
        snrDb: Double,
        wpm: Int,
        snippet: String,
        intent: CWQSOIntent = .general,
        countryFlag: String = "🌐",
        countryName: String = "Unknown",
        isMultiplier: Bool = false,
        lastHeard: Date = Date()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.callsign = callsign
        self.audioFreqHz = audioFreqHz
        self.rfFreqHz = rfFreqHz
        self.snrDb = snrDb
        self.wpm = wpm
        self.snippet = snippet
        self.intent = intent
        self.countryFlag = countryFlag
        self.countryName = countryName
        self.isMultiplier = isMultiplier
        self.lastHeard = lastHeard
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(callsign)
        hasher.combine(Int(audioFreqHz / 25.0)) // Group spots within 25 Hz
    }

    public static func == (lhs: CWSkimmerSpot, rhs: CWSkimmerSpot) -> Bool {
        lhs.callsign == rhs.callsign && abs(lhs.audioFreqHz - rhs.audioFreqHz) < 25.0
    }
}

// MARK: - Internal Per-Channel DSP State Tracker

private final class ChannelDSPTracker {
    let id: Int
    let centerFreqHz: Double
    var isSignalActive: Bool = false
    var signalLevel: Float = 0.0
    var snrDb: Double = 0.0
    var estimatedWPM: Double = 22.0
    var rawDecodedText: String = ""
    var activeCharacterBuffer: String = ""
    var identifiedCallsign: String? = nil
    var lastActivity: Date = Date()

    // Sample-accurate timing state
    var isMarkActive: Bool = false
    var currentMarkDuration: Double = 0.0
    var currentSpaceDuration: Double = 0.0
    var currentDitEstimate: Double = 0.055 // ~22 WPM baseline (55ms)
    var recentDitDurations: [Double] = []
    var recentDahDurations: [Double] = []
    var hasCommittedWordBreak: Bool = true
    var recentWords: [String] = []

    init(id: Int, centerFreqHz: Double) {
        self.id = id
        self.centerFreqHz = centerFreqHz
    }

    func reset() {
        isSignalActive = false
        signalLevel = 0.0
        snrDb = 0.0
        isMarkActive = false
        currentMarkDuration = 0.0
        currentSpaceDuration = 0.0
        activeCharacterBuffer = ""
        hasCommittedWordBreak = true
    }
}

// MARK: - Main Multi-Channel Skimmer Engine

@MainActor
public final class CWMultiChannelSkimmerEngine: ObservableObject {
    public static let shared = CWMultiChannelSkimmerEngine()

    // Standard audio passband channels (450 Hz to 900 Hz in 50 Hz steps)
    public static let defaultFrequencies: [Double] = [
        450.0, 500.0, 550.0, 600.0, 650.0, 700.0, 750.0, 800.0, 850.0, 900.0
    ]

    // Reverse Morse Lookup Dictionary
    private static let reverseMorseAlphabet: [String: String] = {
        var dict: [String: String] = [:]
        for (char, pattern) in CWKeyerService.morseAlphabet {
            dict[pattern] = String(char)
        }
        dict[".-.-."] = "<AR>"
        dict["...-.-"] = "<SK>"
        dict["-...-"] = "<BT>"
        dict[".-..."] = "<AS>"
        dict["-.--."] = "<KN>"
        dict["........"] = "<HH>"
        return dict
    }()

    // MARK: - Published State
    @Published public var isListening: Bool = false
    @Published public var isAudioAvailable: Bool = false
    @Published public var audioInputLevel: Float = 0.0
    @Published public var nominalPitchHz: Double = 650.0

    // Parallel Channels
    @Published public var channels: [CWSkimmerChannel] = []
    @Published public var spots: [CWSkimmerSpot] = []
    @Published public var selectedChannelId: Int = 4 // Default to 650 Hz channel
    @Published public var lastZeroBeatAdjustmentHz: Double = 0.0
    @Published public var pendingSelectedCallsign: String? = nil

    // Simulation / Practice Feed
    @Published public var isSimulationActive: Bool = false

    // Internal Machinery
    private var trackers: [ChannelDSPTracker] = []
    private var audioEngine: AVAudioEngine?
    private var sampleRate: Double = 44100.0
    private var simulationTimer: Timer?

    public init() {
        let savedPitch = UserDefaults.standard.double(forKey: "cwDecoderFreq")
        self.nominalPitchHz = savedPitch >= 400.0 && savedPitch <= 950.0 ? savedPitch : 650.0
        setupChannelBank()
    }

    private func setupChannelBank() {
        trackers = Self.defaultFrequencies.enumerated().map { (idx, freq) in
            ChannelDSPTracker(id: idx, centerFreqHz: freq)
        }
        syncPublishedChannels()
    }

    private func syncPublishedChannels() {
        self.channels = trackers.map { t in
            CWSkimmerChannel(
                id: t.id,
                centerFreqHz: t.centerFreqHz,
                isSignalActive: t.isSignalActive,
                signalLevel: t.signalLevel,
                snrDb: t.snrDb,
                estimatedWPM: t.estimatedWPM,
                rawDecodedText: t.rawDecodedText,
                activeCharacterBuffer: t.activeCharacterBuffer,
                identifiedCallsign: t.identifiedCallsign,
                lastActivity: t.lastActivity
            )
        }
    }

    // MARK: - Start & Stop Skimmer

    public func startSkimmer() {
        guard !isListening else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            print("❌ CWMultiChannelSkimmer: Invalid audio input sample rate")
            return
        }

        self.sampleRate = format.sampleRate
        resetAllTrackers()

        // 2048 sample buffer tap
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            Task { @MainActor in
                self.processAudioBuffer(buffer)
            }
        }

        do {
            try engine.start()
            self.audioEngine = engine
            self.isListening = true
            self.isAudioAvailable = true
        } catch {
            print("❌ CWMultiChannelSkimmer: Failed to start audio engine: \(error.localizedDescription)")
            self.isAudioAvailable = false
        }
    }

    public func stopSkimmer() {
        guard isListening else { return }
        stopSimulation()

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.audioEngine = nil
        }

        self.isListening = false
        self.audioInputLevel = 0.0
        resetAllTrackers()
    }

    public func clearRoster() {
        spots.removeAll()
        for t in trackers {
            t.rawDecodedText = ""
            t.identifiedCallsign = nil
            t.recentWords.removeAll()
        }
        syncPublishedChannels()
    }

    private func resetAllTrackers() {
        for t in trackers {
            t.reset()
        }
        syncPublishedChannels()
    }

    // MARK: - Parallel Audio DSP Processing

    public func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let totalFrames = Int(buffer.frameLength)
        guard totalFrames > 0 else { return }

        // Measure Peak Master Audio Level
        var peak: Float = 0.0
        for i in stride(from: 0, to: totalFrames, by: 16) {
            let val = abs(channelData[i])
            if val > peak { peak = val }
        }

        let sRate = self.sampleRate > 0 ? self.sampleRate : 48000.0

        // Process in 256-sample sub-chunks (~5.3ms resolution)
        let chunkSize = 256
        let chunkCount = totalFrames / chunkSize
        let chunkDurationSec = Double(chunkSize) / sRate

        for c in 0..<chunkCount {
            let offset = c * chunkSize
            let chunkPtr = channelData.advanced(by: offset)

            // Measure wideband background noise floor across passband
            let noiseRefA = goertzelMagnitude(channelData: chunkPtr, frameCount: chunkSize, targetFreq: 380.0, sampleRate: sRate)
            let noiseRefB = goertzelMagnitude(channelData: chunkPtr, frameCount: chunkSize, targetFreq: 980.0, sampleRate: sRate)
            let passbandNoiseFloor = max(0.0006, (noiseRefA + noiseRefB) * 0.5)

            // Evaluate all parallel channels simultaneously
            for tracker in trackers {
                processChunkForChannel(
                    tracker: tracker,
                    chunkPtr: chunkPtr,
                    chunkSize: chunkSize,
                    chunkDurationSec: chunkDurationSec,
                    passbandNoiseFloor: passbandNoiseFloor,
                    sampleRate: sRate
                )
            }
        }

        self.audioInputLevel = peak
        self.syncPublishedChannels()
    }

    private func processChunkForChannel(
        tracker: ChannelDSPTracker,
        chunkPtr: UnsafePointer<Float>,
        chunkSize: Int,
        chunkDurationSec: Double,
        passbandNoiseFloor: Float,
        sampleRate: Double
    ) {
        let mag = goertzelMagnitude(channelData: chunkPtr, frameCount: chunkSize, targetFreq: tracker.centerFreqHz, sampleRate: sampleRate)
        tracker.signalLevel = mag

        // Local channel SNR
        let snrRatio = Double(mag) / Double(passbandNoiseFloor)
        let snrDb = 20.0 * log10(max(1.0, snrRatio))
        tracker.snrDb = snrDb

        // Dual Schmitt Trigger: onThreshold >= 2.0x noise, offThreshold <= 1.3x noise
        let onThreshold: Float = max(0.0028, passbandNoiseFloor * 2.0)
        let offThreshold: Float = max(0.0015, passbandNoiseFloor * 1.3)

        if !tracker.isMarkActive {
            if mag >= onThreshold && snrRatio >= 2.0 {
                // Space -> Mark transition
                handleSpaceEnd(tracker: tracker, spaceDuration: tracker.currentSpaceDuration)
                tracker.currentSpaceDuration = 0.0
                tracker.currentMarkDuration = chunkDurationSec
                tracker.isMarkActive = true
                tracker.isSignalActive = true
                tracker.lastActivity = Date()
            } else {
                tracker.currentSpaceDuration += chunkDurationSec
                handleSpaceProgression(tracker: tracker, spaceDuration: tracker.currentSpaceDuration)
            }
        } else {
            if mag < offThreshold || snrRatio < 1.3 {
                // Mark -> Space transition
                handleMarkEnd(tracker: tracker, markDuration: tracker.currentMarkDuration)
                tracker.currentMarkDuration = 0.0
                tracker.currentSpaceDuration = chunkDurationSec
                tracker.isMarkActive = false
                tracker.isSignalActive = false
            } else {
                tracker.currentMarkDuration += chunkDurationSec
            }
        }
    }

    // MARK: - Mark / Space FSM & Dit-Dah Decoders

    private func handleMarkEnd(tracker: ChannelDSPTracker, markDuration: Double) {
        let dit = tracker.currentDitEstimate
        guard markDuration >= (dit * 0.40) else { return } // Reject noise glitches < 0.4 dit

        let ditDecisionBoundary = dit * 1.85 // Nominal dit is 1.0, dah is 3.0

        if markDuration < ditDecisionBoundary {
            // Dit detected
            tracker.activeCharacterBuffer.append(".")
            tracker.recentDitDurations.append(markDuration)
            if tracker.recentDitDurations.count > 10 { tracker.recentDitDurations.removeFirst() }
        } else {
            // Dah detected
            tracker.activeCharacterBuffer.append("-")
            tracker.recentDahDurations.append(markDuration)
            if tracker.recentDahDurations.count > 10 { tracker.recentDahDurations.removeFirst() }
        }

        adaptWPM(tracker: tracker)
    }

    private func handleSpaceEnd(tracker: ChannelDSPTracker, spaceDuration: Double) {
        let dit = tracker.currentDitEstimate
        // If pause was longer than character space (~2.2 dits), commit previous character
        if spaceDuration >= (dit * 2.0) && !tracker.activeCharacterBuffer.isEmpty {
            commitCharacter(tracker: tracker)
        }
    }

    private func handleSpaceProgression(tracker: ChannelDSPTracker, spaceDuration: Double) {
        let dit = tracker.currentDitEstimate

        // Inter-character space commitment (>= 2.5 dits)
        if spaceDuration >= (dit * 2.5) && !tracker.activeCharacterBuffer.isEmpty {
            commitCharacter(tracker: tracker)
        }

        // Word space commitment (>= 6.0 dits)
        if spaceDuration >= (dit * 5.5) && !tracker.hasCommittedWordBreak {
            commitWordBreak(tracker: tracker)
        }
    }

    private func commitCharacter(tracker: ChannelDSPTracker) {
        let pattern = tracker.activeCharacterBuffer
        tracker.activeCharacterBuffer = ""
        guard !pattern.isEmpty else { return }

        if let char = Self.reverseMorseAlphabet[pattern] {
            tracker.rawDecodedText.append(char)
            tracker.lastActivity = Date()
            scanChannelTraffic(tracker: tracker)
        }
    }

    private func commitWordBreak(tracker: ChannelDSPTracker) {
        guard !tracker.hasCommittedWordBreak else { return }
        tracker.hasCommittedWordBreak = true

        if !tracker.rawDecodedText.isEmpty && !tracker.rawDecodedText.hasSuffix(" ") {
            tracker.rawDecodedText.append(" ")
            scanChannelTraffic(tracker: tracker)
        }
    }

    private func adaptWPM(tracker: ChannelDSPTracker) {
        if !tracker.recentDitDurations.isEmpty {
            let avgDit = tracker.recentDitDurations.reduce(0.0, +) / Double(tracker.recentDitDurations.count)
            tracker.currentDitEstimate = max(0.025, min(0.120, avgDit)) // 10 to 48 WPM
            tracker.estimatedWPM = 1.2 / tracker.currentDitEstimate
        }
    }

    // MARK: - Callsign Extraction & Spot Roster Registration

    private func scanChannelTraffic(tracker: ChannelDSPTracker) {
        let words = tracker.rawDecodedText.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !words.isEmpty else { return }

        let recentWords = Array(words.suffix(8))
        let recentText = recentWords.joined(separator: " ")

        for word in recentWords {
            if isCandidateCallsign(word) {
                tracker.identifiedCallsign = word
                registerOrUpdateSpot(callsign: word, tracker: tracker, contextText: recentText)
            }
        }
    }

    public static func isCandidateCallsign(_ word: String) -> Bool {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 3 && clean.count <= 10 else { return false }

        let hasDigit = clean.contains(where: \.isNumber)
        let hasLetter = clean.contains(where: \.isLetter)
        guard hasDigit && hasLetter else { return false }

        let blackList = [
            "5NN", "599", "73", "88", "TEST", "CQ", "AGN", "TU", "NAME", "QTH",
            "RIG", "ANT", "HW?", "RST", "CFM", "BK", "ES", "UR", "K", "SK"
        ]
        return !blackList.contains(clean)
    }

    private func isCandidateCallsign(_ word: String) -> Bool {
        Self.isCandidateCallsign(word)
    }

    private func registerOrUpdateSpot(callsign: String, tracker: ChannelDSPTracker, contextText: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let cleanCall = callsign.uppercased()
            let dxcc = DXCCDatabase.resolve(callsign: cleanCall)

            // Determine intent
            let intent: CWQSOIntent
            if contextText.contains("CQ") {
                intent = .callingCQ
            } else if contextText.contains("5NN") || contextText.contains("599") {
                intent = .contestExchange
            } else if contextText.contains("73") {
                intent = .signOff
            } else {
                intent = .general
            }

            let freq = tracker.centerFreqHz
            let snr = tracker.snrDb
            let wpm = Int(tracker.estimatedWPM)

            if let existingIdx = self.spots.firstIndex(where: { $0.callsign == cleanCall && abs($0.audioFreqHz - freq) < 35.0 }) {
                // Update existing spot
                self.spots[existingIdx].lastHeard = Date()
                self.spots[existingIdx].snrDb = snr
                self.spots[existingIdx].wpm = wpm
                self.spots[existingIdx].snippet = contextText
                self.spots[existingIdx].intent = intent
            } else {
                // Create new spot and prepend to roster
                let newSpot = CWSkimmerSpot(
                    callsign: cleanCall,
                    audioFreqHz: freq,
                    snrDb: snr,
                    wpm: wpm,
                    snippet: contextText,
                    intent: intent,
                    countryFlag: dxcc.flagEmoji,
                    countryName: dxcc.entityName,
                    isMultiplier: false,
                    lastHeard: Date()
                )
                self.spots.insert(newSpot, at: 0)

                // Limit roster to 60 most recent spots
                if self.spots.count > 60 {
                    self.spots.removeLast()
                }
            }
        }
    }

    // MARK: - Zero-Beat Tuning & CAT QSY Primitives

    /// Calculates the exact frequency shift in Hz required to Zero-Beat the target station to nominal sidetone pitch.
    public func calculateZeroBeatDelta(for spot: CWSkimmerSpot, nominalPitch: Double? = nil) -> Double {
        let nominal = nominalPitch ?? nominalPitchHz
        return spot.audioFreqHz - nominal
    }

    /// QSYs to the spot: adjusts transceiver frequency or RIT via CAT, and records target callsign.
    public func tuneToSpot(_ spot: CWSkimmerSpot) {
        let deltaHz = calculateZeroBeatDelta(for: spot)
        lastZeroBeatAdjustmentHz = deltaHz
        pendingSelectedCallsign = spot.callsign

        // Send CAT command if rig control is connected
        if RigControlClient.shared.state.isConnected, let snapshot = RigControlClient.shared.snapshot {
            let currentFreq = snapshot.frequencyHz
            if currentFreq > 0 {
                let targetFreq = UInt64(max(0, Int64(currentFreq) + Int64(deltaHz)))
                RigControlClient.shared.setFrequencyHz(targetFreq)
            }
        } else if FLRigClient.shared.isConnected {
            let currentFreq = FLRigClient.shared.frequencyHz
            if currentFreq > 0 {
                let targetFreq = currentFreq + deltaHz
                Task {
                    try? await FLRigClient.shared.setFrequency(hz: targetFreq)
                }
            }
        }
    }

    // MARK: - Multi-Station Practice Feed Simulation

    public func toggleSimulation() {
        if isSimulationActive {
            stopSimulation()
        } else {
            startSimulation()
        }
    }

    public func startSimulation() {
        guard !isSimulationActive else { return }
        isSimulationActive = true

        // Synthesize simulated multi-station audio blocks periodically
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isSimulationActive else { return }
                self.injectSimulatedMultiStationTraffic()
            }
        }
    }

    public func stopSimulation() {
        isSimulationActive = false
        simulationTimer?.invalidate()
        simulationTimer = nil
    }

    public func injectSimulatedMultiStationTraffic() {
        // Multi-station simulation traffic:
        // Channel 1 at 500 Hz: W1AW CQ TEST
        // Channel 4 at 650 Hz: DL1ABC CQ TEST
        // Channel 7 at 800 Hz: JA1BJK 5NN 001
        let stations: [(call: String, freq: Double, wpm: Int, text: String)] = [
            ("W1AW", 500.0, 24, "CQ TEST W1AW"),
            ("DL1ABC", 650.0, 26, "CQ TEST DL1ABC"),
            ("JA1BJK", 800.0, 28, "JA1BJK 5NN 001")
        ]

        if let buffer = synthesizeMultiStationBuffer(stations: stations) {
            processAudioBuffer(buffer)
        }
    }

    public func synthesizeMultiStationBuffer(stations: [(call: String, freq: Double, wpm: Int, text: String)]) -> AVAudioPCMBuffer? {
        let sampleRate = 44100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }

        // Render each station into tone blocks
        var stationTracks: [(freq: Double, blocks: [(isTone: Bool, frames: Int)])] = []
        var maxFrames = 0

        for st in stations {
            let blocks = buildMorseBlocks(text: st.text, wpm: st.wpm, sampleRate: sampleRate)
            let trackFrames = blocks.reduce(0) { $0 + $1.frames }
            if trackFrames > maxFrames { maxFrames = trackFrames }
            stationTracks.append((freq: st.freq, blocks: blocks))
        }

        guard maxFrames > 0 else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(maxFrames)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(maxFrames)

        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        var mix = [Float](repeating: 0.0, count: maxFrames)
        let rampFrames = max(1, Int(sampleRate * 0.004)) // 4ms soft cosine ramp

        for track in stationTracks {
            let omega = 2.0 * .pi * track.freq / sampleRate
            var phase: Double = 0.0
            var writePos = 0
            let amp: Float = 0.22

            for block in track.blocks {
                let frames = block.frames
                if !block.isTone {
                    writePos += frames
                    phase = 0.0
                } else {
                    let rf = min(rampFrames, frames / 2)
                    for f in 0..<frames {
                        let targetIdx = writePos + f
                        guard targetIdx < maxFrames else { break }

                        let s = Float(sin(phase)) * amp
                        var env: Float = 1.0
                        if f < rf {
                            env = 0.5 * (1.0 - cos(Float.pi * Float(f) / Float(rf)))
                        } else if f > (frames - rf) {
                            let endF = frames - f
                            env = 0.5 * (1.0 - cos(Float.pi * Float(endF) / Float(rf)))
                        }

                        mix[targetIdx] += (s * env)
                        phase += omega
                        if phase > 2.0 * .pi { phase -= 2.0 * .pi }
                    }
                    writePos += frames
                }
            }
        }

        // Add soft atmospheric noise floor
        for i in 0..<maxFrames {
            mix[i] += Float.random(in: -0.002...0.002)
            channelData[i] = mix[i]
        }

        return buffer
    }

    private func buildMorseBlocks(text: String, wpm: Int, sampleRate: Double) -> [(isTone: Bool, frames: Int)] {
        let ditDuration = 1.2 / Double(max(5, wpm))
        let ditFrames = max(1, Int(ditDuration * sampleRate))
        let dahFrames = ditFrames * 3
        let intraCharSpaceFrames = ditFrames
        let interCharSpaceFrames = ditFrames * 3
        let wordSpaceFrames = ditFrames * 7

        var blocks: [(isTone: Bool, frames: Int)] = []
        let morseTable = CWKeyerService.morseAlphabet
        let clean = text.uppercased()

        for (cIdx, char) in clean.enumerated() {
            if char == " " {
                blocks.append((false, wordSpaceFrames))
                continue
            }
            guard let pattern = morseTable[char] else { continue }

            for (sIdx, sym) in pattern.enumerated() {
                if sym == "." {
                    blocks.append((true, ditFrames))
                } else if sym == "-" {
                    blocks.append((true, dahFrames))
                }
                if sIdx < pattern.count - 1 {
                    blocks.append((false, intraCharSpaceFrames))
                }
            }

            if cIdx < clean.count - 1 {
                blocks.append((false, interCharSpaceFrames))
            }
        }

        return blocks
    }

    // MARK: - Goertzel DSP Primitives

    private func goertzelMagnitude(channelData: UnsafePointer<Float>, frameCount: Int, targetFreq: Double, sampleRate: Double) -> Float {
        guard frameCount > 0, sampleRate > 0 else { return 0.0 }
        let k = Int(0.5 + (Double(frameCount) * targetFreq / sampleRate))
        let omega = (2.0 * .pi * Double(k)) / Double(frameCount)
        let coeff = Float(2.0 * cos(omega))

        var q0: Float = 0.0
        var q1: Float = 0.0
        var q2: Float = 0.0

        for i in 0..<frameCount {
            q0 = coeff * q1 - q2 + channelData[i]
            q2 = q1
            q1 = q0
        }

        let power = q1 * q1 + q2 * q2 - coeff * q1 * q2
        return (power > 0.0) ? (sqrt(power) / Float(frameCount)) : 0.0
    }
}
