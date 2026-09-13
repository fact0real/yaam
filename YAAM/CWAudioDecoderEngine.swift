//
//  CWAudioDecoderEngine.swift
//  YAAM
//
//  Real-Time DSP Morse Code Audio Decoder Engine
//  Extracts CW tones from microphone, USB audio codec, or practice simulation using
//  sub-chunk Goertzel tone tracking, narrow-band SNR discrimination, adaptive Schmitt-trigger
//  hysteresis, sample-accurate mark/space timing, and intelligent WPM adaptation.
//

import AVFoundation
import Combine
import Foundation

public struct CWSpectrumBin: Identifiable, Sendable {
    public let id: Int
    public let frequencyHz: Double
    public let magnitude: Float
}

public struct CWDecodedToken: Identifiable, Sendable {
    public let id = UUID()
    public let text: String
    public let isCallsign: Bool
    public let isQCode: Bool
    public let isReport: Bool
    public let timestamp: Date
}

@MainActor
public final class CWAudioDecoderEngine: ObservableObject {
    public static let shared = CWAudioDecoderEngine()

    // MARK: - Published Metrics
    @Published public var isListening: Bool = false
    @Published public var isAudioAvailable: Bool = false
    @Published public var isSignalDetected: Bool = false
    @Published public var centerFrequencyHz: Double = 650.0
    @Published public var nominalPitchHz: Double = 650.0 // User setpoint for AFC constraint
    @Published public var afcEnabled: Bool = true
    @Published public var estimatedWPM: Double = 20.0
    @Published public var signalToNoiseRatioDb: Double = 0.0
    @Published public var ditDahRatio: Double = 3.0
    @Published public var audioInputLevel: Float = 0.0

    // Decoded Output Stream
    @Published public var rawDecodedText: String = ""
    @Published public var decodedTokens: [CWDecodedToken] = []
    @Published public var activeCharacterBuffer: String = "" // Current dit-dah sequence like ".-"
    @Published public var spectrumBins: [CWSpectrumBin] = []

    // Simulation / Practice Mode
    @Published public var isSimulationActive: Bool = false

    private var audioEngine: AVAudioEngine?
    private var sampleRate: Double = 44100.0

    // DSP Timing & State Variables (Sample-Accurate)
    private var isMarkActive: Bool = false
    private var currentMarkDuration: Double = 0.0
    private var currentSpaceDuration: Double = 0.0
    private var currentDitEstimate: Double = 0.060 // 20 WPM baseline (60ms)
    private var recentDitDurations: [Double] = []
    private var recentDahDurations: [Double] = []
    private var hasCommittedWordBreak: Bool = true
    private var consecutiveCarrierWarnings: Int = 0

    // Reverse Morse Lookup Dictionary (Morse String -> Character)
    private static let reverseMorseAlphabet: [String: String] = {
        var dict: [String: String] = [:]
        for (char, pattern) in CWKeyerService.morseAlphabet {
            dict[pattern] = String(char)
        }
        // Additional procedural signals (Prosigns)
        dict[".-.-."] = "<AR>"
        dict["...-.-"] = "<SK>"
        dict["-...-"] = "<BT>"
        dict[".-..."] = "<AS>"
        dict["-.--."] = "<KN>"
        dict["........"] = "<HH>"
        return dict
    }()

    private var simulationTimer: Timer?

    public init() {
        let savedFreq = UserDefaults.standard.double(forKey: "cwDecoderFreq")
        self.nominalPitchHz = savedFreq >= 400.0 && savedFreq <= 950.0 ? savedFreq : 650.0
        self.centerFrequencyHz = self.nominalPitchHz
    }

    // MARK: - Pitch Controls

    public func setPitch(_ hz: Double) {
        let clamped = max(450.0, min(900.0, hz))
        self.nominalPitchHz = clamped
        self.centerFrequencyHz = clamped
        UserDefaults.standard.set(clamped, forKey: "cwDecoderFreq")
    }

    public func increasePitch() {
        setPitch(nominalPitchHz + 25.0)
    }

    public func decreasePitch() {
        setPitch(nominalPitchHz - 25.0)
    }

    // MARK: - Start & Stop Listening

    public func startListening() {
        guard !isListening else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            print("CWAudioDecoder: Invalid audio input sample rate")
            return
        }

        self.sampleRate = format.sampleRate
        self.resetTimingState()

        // 1024 or 2048 buffer tap; we slice internally into 256-sample sub-chunks (~5.3ms resolution)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            self.audioEngine = engine
            self.isListening = true
            self.isAudioAvailable = true
        } catch {
            print("CWAudioDecoder: Failed to start audio engine: \(error)")
            self.isAudioAvailable = false
        }
    }

    public func stopListening() {
        guard isListening else { return }
        stopSimulation()

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.audioEngine = nil
        }

        isListening = false
        isSignalDetected = false
        audioInputLevel = 0.0
        signalToNoiseRatioDb = 0.0
        resetTimingState()
    }

    public func clearBuffer() {
        rawDecodedText = ""
        decodedTokens.removeAll()
        activeCharacterBuffer = ""
        resetTimingState()
    }

    private func resetTimingState() {
        isMarkActive = false
        currentMarkDuration = 0.0
        currentSpaceDuration = 0.0
        currentDitEstimate = 1.2 / max(10.0, estimatedWPM)
        recentDitDurations.removeAll()
        recentDahDurations.removeAll()
        hasCommittedWordBreak = true
        consecutiveCarrierWarnings = 0
    }

    // MARK: - DSP Audio Buffer Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let totalFrames = Int(buffer.frameLength)
        guard totalFrames > 0 else { return }

        // 1. Peak Audio Level for VU Meter
        var peak: Float = 0.0
        for i in stride(from: 0, to: totalFrames, by: 8) {
            let val = abs(channelData[i])
            if val > peak { peak = val }
        }

        // 2. Full Spectrum Analysis for Visual Scope
        let fullBins = evaluateFilterBank(channelData: channelData, frameCount: totalFrames)

        // 3. Controlled AFC within narrow window (+/- 50 Hz of nominal setpoint)
        if afcEnabled {
            updateAFC(bins: fullBins)
        }

        // 4. Sub-Chunk Time Slicing for Precise Morse Mark/Space Timing
        // We process in 256-sample chunks (approx 5.3ms resolution at 48kHz)
        let chunkSize = 256
        let chunkCount = totalFrames / chunkSize
        let chunkDurationSec = Double(chunkSize) / sampleRate

        var lastChunkSNR: Double = 0.0
        var markOccurredInBlock = false

        for c in 0..<chunkCount {
            let offset = c * chunkSize
            let chunkPtr = channelData.advanced(by: offset)

            // Measure energy at target frequency
            let targetMag = goertzelMagnitude(channelData: chunkPtr, frameCount: chunkSize, targetFreq: centerFrequencyHz)

            // Measure background noise floor at flanking reference frequencies (+/- 140 Hz)
            let noiseLow = goertzelMagnitude(channelData: chunkPtr, frameCount: chunkSize, targetFreq: max(350.0, centerFrequencyHz - 140.0))
            let noiseHigh = goertzelMagnitude(channelData: chunkPtr, frameCount: chunkSize, targetFreq: min(1000.0, centerFrequencyHz + 140.0))
            let localNoiseFloor = max(0.0008, (noiseLow + noiseHigh) * 0.5)

            // Narrow-band SNR
            let snrRatio = Double(targetMag) / Double(localNoiseFloor)
            lastChunkSNR = 20.0 * log10(max(1.0, snrRatio))

            // Schmitt Trigger with dual threshold and absolute floor
            // Must be at least +7 dB SNR AND absolute magnitude above 0.003 to be a valid CW carrier
            let onThreshold: Float = max(0.0030, localNoiseFloor * 2.2)
            let offThreshold: Float = max(0.0016, localNoiseFloor * 1.4)

            if !isMarkActive {
                if targetMag >= onThreshold && snrRatio >= 2.2 {
                    // Space -> Mark transition
                    handleMarkOnset(spaceDuration: currentSpaceDuration)
                    currentSpaceDuration = 0.0
                    currentMarkDuration = chunkDurationSec
                    isMarkActive = true
                    markOccurredInBlock = true
                } else {
                    currentSpaceDuration += chunkDurationSec
                    handleSpaceProgression(spaceDuration: currentSpaceDuration)
                }
            } else {
                if targetMag < offThreshold || snrRatio < 1.4 {
                    // Mark -> Space transition
                    handleMarkEnd(markDuration: currentMarkDuration)
                    currentMarkDuration = 0.0
                    currentSpaceDuration = chunkDurationSec
                    isMarkActive = false
                } else {
                    currentMarkDuration += chunkDurationSec
                    markOccurredInBlock = true

                    // Anti-Carrier / Stuck tone filter: if tone persists > 1.2 seconds, it is NOT Morse!
                    if currentMarkDuration > 1.2 {
                        isMarkActive = false
                        currentMarkDuration = 0.0
                        activeCharacterBuffer = "" // discard stuck tone
                    }
                }
            }
        }

        // 5. Publish updates to UI
        let isToneActive = isMarkActive || markOccurredInBlock
        let finalPeak = peak
        let finalBins = fullBins
        let finalSNR = max(0.0, min(40.0, lastChunkSNR))

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioInputLevel = finalPeak
            self.spectrumBins = finalBins
            self.signalToNoiseRatioDb = finalSNR
            self.isSignalDetected = isToneActive
        }
    }

    // MARK: - Sub-Chunk Morse State Logic

    private func handleMarkOnset(spaceDuration: Double) {
        // Space was long enough to separate characters
        if spaceDuration >= currentDitEstimate * 2.1 {
            commitActiveCharacter()
        }
        // Space was long enough to separate words
        if spaceDuration >= currentDitEstimate * 5.0 && !hasCommittedWordBreak {
            commitWordBreak()
        }
    }

    private func handleSpaceProgression(spaceDuration: Double) {
        // Character timeout while in idle space
        if !activeCharacterBuffer.isEmpty && spaceDuration >= currentDitEstimate * 2.3 {
            commitActiveCharacter()
        }
        // Word timeout while in idle space
        if spaceDuration >= currentDitEstimate * 5.5 && !hasCommittedWordBreak && !rawDecodedText.isEmpty {
            commitWordBreak()
        }
    }

    private func handleMarkEnd(markDuration: Double) {
        // Glitch rejection: ignore pulses shorter than 18ms
        guard markDuration >= 0.018 else { return }

        // Carrier rejection: ignore continuous tones longer than 1.0 second
        guard markDuration <= 1.0 else {
            activeCharacterBuffer = ""
            return
        }

        hasCommittedWordBreak = false

        // Dit vs Dah Decision
        // Nominal: Dit = 1 unit, Dah = 3 units. Boundary at 1.85 units.
        let ditThreshold = currentDitEstimate * 1.85

        if markDuration < ditThreshold {
            // Dit "."
            activeCharacterBuffer.append(".")
            recentDitDurations.append(markDuration)
            if recentDitDurations.count > 12 { recentDitDurations.removeFirst() }
            // Smoothly adapt dit speed
            currentDitEstimate = currentDitEstimate * 0.88 + markDuration * 0.12
        } else {
            // Dah "-"
            activeCharacterBuffer.append("-")
            recentDahDurations.append(markDuration)
            if recentDahDurations.count > 12 { recentDahDurations.removeFirst() }
            // Smoothly adapt dit speed from Dah (dah / 3.0)
            let ditFromDah = markDuration / 3.0
            currentDitEstimate = currentDitEstimate * 0.88 + ditFromDah * 0.12
        }

        // Clamp speed estimate to realistic amateur radio limits (8 WPM to 48 WPM)
        currentDitEstimate = max(0.025, min(0.150, currentDitEstimate))

        // Update WPM and Dit/Dah ratio
        let newWpm = 1.2 / currentDitEstimate
        let ditAvg = recentDitDurations.isEmpty ? currentDitEstimate : recentDitDurations.reduce(0, +) / Double(recentDitDurations.count)
        let dahAvg = recentDahDurations.isEmpty ? currentDitEstimate * 3.0 : recentDahDurations.reduce(0, +) / Double(recentDahDurations.count)
        let ratio = dahAvg / max(0.01, ditAvg)

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.estimatedWPM = min(50.0, max(8.0, self.estimatedWPM * 0.85 + newWpm * 0.15))
            self.ditDahRatio = min(6.0, max(1.5, ratio))
        }
    }

    private func commitActiveCharacter() {
        guard !activeCharacterBuffer.isEmpty else { return }
        let pattern = activeCharacterBuffer
        activeCharacterBuffer = ""

        if let char = Self.reverseMorseAlphabet[pattern] {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rawDecodedText.append(char)
                self.tokenizeStream()
            }
        }
    }

    private func commitWordBreak() {
        guard !hasCommittedWordBreak else { return }
        hasCommittedWordBreak = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.rawDecodedText.isEmpty && !self.rawDecodedText.hasSuffix(" ") {
                self.rawDecodedText.append(" ")
                self.tokenizeStream()
            }
        }
    }

    private func tokenizeStream() {
        let words = rawDecodedText.components(separatedBy: " ").filter { !$0.isEmpty }
        var tokens: [CWDecodedToken] = []

        for word in words.suffix(40) {
            let isCall = isLikelyCallsign(word)
            let isQ = word.hasPrefix("Q") && word.count == 3
            let isRep = word == "5NN" || word == "599"

            tokens.append(CWDecodedToken(
                text: word,
                isCallsign: isCall,
                isQCode: isQ,
                isReport: isRep,
                timestamp: Date()
            ))
        }

        self.decodedTokens = tokens

        // Notify Adaptive Assistant
        CWAdaptiveAssistant.shared.analyzeDecodedStream(rawDecodedText)
    }

    private func isLikelyCallsign(_ word: String) -> Bool {
        guard word.count >= 3 && word.count <= 8 else { return false }
        let hasDigit = word.contains(where: \.isNumber)
        let hasLetter = word.contains(where: \.isLetter)
        let excluded = ["5NN", "599", "73", "88", "TEST", "CQ", "AGN", "TU", "NAME", "QTH", "RIG", "ANT"]
        return hasDigit && hasLetter && !excluded.contains(word)
    }

    // MARK: - AFC & Filter Bank

    private func updateAFC(bins: [CWSpectrumBin]) {
        // AFC is strictly constrained within +/- 60 Hz of nominal setpoint to prevent drifting to low-frequency noise
        let minFreq = max(400.0, nominalPitchHz - 60.0)
        let maxFreq = min(950.0, nominalPitchHz + 60.0)

        var localMaxMag: Float = 0.0
        var bestFreq: Double = centerFrequencyHz

        for bin in bins where bin.frequencyHz >= minFreq && bin.frequencyHz <= maxFreq {
            if bin.magnitude > localMaxMag {
                localMaxMag = bin.magnitude
                bestFreq = bin.frequencyHz
            }
        }

        // Only lock if there is a true peak with substantial carrier power
        if localMaxMag > 0.005 && abs(bestFreq - centerFrequencyHz) > 5.0 {
            centerFrequencyHz = centerFrequencyHz * 0.90 + bestFreq * 0.10
        }
    }

    private func evaluateFilterBank(channelData: UnsafePointer<Float>, frameCount: Int) -> [CWSpectrumBin] {
        var results: [CWSpectrumBin] = []
        var id = 0

        for freq in stride(from: 400.0, through: 950.0, by: 25.0) {
            let mag = goertzelMagnitude(channelData: channelData, frameCount: frameCount, targetFreq: freq)
            results.append(CWSpectrumBin(id: id, frequencyHz: freq, magnitude: mag))
            id += 1
        }

        return results
    }

    // Optimized Goertzel Magnitude Calculation
    private func goertzelMagnitude(channelData: UnsafePointer<Float>, frameCount: Int, targetFreq: Double) -> Float {
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

        let real = q1 - q2 * Float(cos(omega))
        let imag = q2 * Float(sin(omega))
        let power = real * real + imag * imag
        return sqrt(power) / Float(frameCount)
    }

    // MARK: - Simulation Mode

    public func toggleSimulation() {
        if isSimulationActive {
            stopSimulation()
        } else {
            startSimulation()
        }
    }

    public func startSimulation() {
        stopSimulation()
        isSimulationActive = true
        isListening = true
        isAudioAvailable = true

        let simulatedMessages = [
            "CQ TEST W1AW W1AW TEST",
            "EP2AES 5NN 042",
            "TU W1AW CQ",
            "CQ DX JA1ZLO JA1ZLO K",
            "NAME IS ALI QTH TEHRAN 73 SK"
        ]

        var index = 0
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let msg = simulatedMessages[index % simulatedMessages.count]
            index += 1

            Task { @MainActor in
                guard self.isSimulationActive else { return }
                self.estimatedWPM = Double.random(in: 22.0...26.0)
                self.signalToNoiseRatioDb = Double.random(in: 20.0...28.0)
                self.ditDahRatio = 3.01
                self.audioInputLevel = 0.60
                self.isSignalDetected = true

                self.rawDecodedText.append((self.rawDecodedText.isEmpty ? "" : " ") + msg)
                self.tokenizeStream()
            }
        }
    }

    public func stopSimulation() {
        isSimulationActive = false
        simulationTimer?.invalidate()
        simulationTimer = nil
    }
}
