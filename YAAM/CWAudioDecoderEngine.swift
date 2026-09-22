//
//  CWAudioDecoderEngine.swift
//  YAAM
//
//  Real-Time DSP Morse Code Audio Decoder Engine
//  Extracts CW tones from microphone, USB audio codec, or audio recordings using
//  wideband spectrum auto-pitch hunting (300 - 1800 Hz), continuous Quadrature I/Q
//  analytic envelope demodulation, adaptive dual-threshold Schmitt hysteresis,
//  sample-accurate mark/space timing, and Farnsworth-tolerant WPM adaptation.
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
    @Published public var nominalPitchHz: Double = 650.0 // User setpoint or auto-tuned pitch
    @Published public var afcEnabled: Bool = true
    @Published public var autoTrackPitch: Bool = true {
        didSet { UserDefaults.standard.set(autoTrackPitch, forKey: "cwDecoderAutoTrack") }
    }
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
    private var sampleRate: Double = 48000.0

    // DSP Demodulator State (Quadrature I/Q Analytic Envelope)
    private var phase: Double = 0.0
    private var envI: Double = 0.0
    private var envQ: Double = 0.0
    private var peakEnvelope: Double = 0.01
    private var noiseFloorEnvelope: Double = 0.001

    // DSP Timing & State Variables (Sample-Accurate)
    private var isMarkActive: Bool = false
    private var currentMarkDuration: Double = 0.0
    private var currentSpaceDuration: Double = 0.0
    private var currentDitEstimate: Double = 0.080 // Baseline ~15 WPM (80ms)
    private var recentDitDurations: [Double] = []
    private var recentDahDurations: [Double] = []
    private var hasCommittedWordBreak: Bool = true

    // Reverse Morse Lookup Dictionary (Morse String -> Character)
    private static let reverseMorseAlphabet: [String: String] = {
        var dict: [String: String] = [:]
        for (char, pattern) in CWKeyerService.morseAlphabet {
            dict[pattern] = String(char)
        }
        // Procedural signals (Prosigns)
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
        self.nominalPitchHz = savedFreq >= 300.0 && savedFreq <= 1800.0 ? savedFreq : 650.0
        self.centerFrequencyHz = self.nominalPitchHz
        if let autoTrack = UserDefaults.standard.object(forKey: "cwDecoderAutoTrack") as? Bool {
            self.autoTrackPitch = autoTrack
        } else {
            self.autoTrackPitch = true
        }
    }

    // MARK: - Pitch Controls (Wideband 300 Hz - 1800 Hz)

    public func setPitch(_ hz: Double) {
        let clamped = max(300.0, min(1800.0, hz))
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

    /// One-click Auto-Tune to the highest spectral peak in the passband (300..1800 Hz)
    public func autoTunePitch() {
        guard !spectrumBins.isEmpty else { return }
        if let best = spectrumBins.max(by: { $0.magnitude < $1.magnitude }), best.magnitude > 0.002 {
            setPitch(best.frequencyHz)
        }
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

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.processAudioBuffer(buffer)
            }
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
        phase = 0.0
        envI = 0.0
        envQ = 0.0
        peakEnvelope = 0.01
        noiseFloorEnvelope = 0.001
        isMarkActive = false
        currentMarkDuration = 0.0
        currentSpaceDuration = 0.0
        currentDitEstimate = 1.2 / max(8.0, estimatedWPM)
        recentDitDurations.removeAll()
        recentDahDurations.removeAll()
        hasCommittedWordBreak = true
    }

    // MARK: - DSP Audio Buffer Processing (Quadrature I/Q Analytic Envelope)

    public func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let totalFrames = Int(buffer.frameLength)
        guard totalFrames > 0 else { return }

        // 1. Audio Peak Level for VU Meter
        var peak: Float = 0.0
        for i in stride(from: 0, to: totalFrames, by: 8) {
            let val = abs(channelData[i])
            if val > peak { peak = val }
        }

        // 2. Wideband Spectrum Analysis (300 Hz - 1800 Hz) with Hann Windowing
        let fullBins = evaluateFilterBank(channelData: channelData, frameCount: totalFrames)

        // 3. Auto-Track Pitch & AFC Lock
        if autoTrackPitch && peak > 0.012 {
            if let best = fullBins.max(by: { $0.magnitude < $1.magnitude }) {
                let avgMag = fullBins.reduce(0.0) { $0 + Double($1.magnitude) } / Double(max(1, fullBins.count))
                if Double(best.magnitude) > avgMag * 3.0 && best.magnitude > 0.003 {
                    // Lock onto carrier
                    if abs(best.frequencyHz - centerFrequencyHz) > 30.0 {
                        centerFrequencyHz = centerFrequencyHz * 0.70 + best.frequencyHz * 0.30
                        nominalPitchHz = centerFrequencyHz
                    }
                }
            }
        } else if afcEnabled {
            updateNarrowbandAFC(bins: fullBins)
        }

        // 4. Sample-Accurate Quadrature I/Q Analytic Demodulation
        let omega = (2.0 * .pi * centerFrequencyHz) / sampleRate
        let lpfCutoffHz = 65.0 // ~65 Hz lowpass captures keying up to ~50 WPM without tone ripple
        let lpfAlpha = 1.0 - exp(-2.0 * .pi * lpfCutoffHz / sampleRate)
        let sampleDuration = 1.0 / sampleRate

        var markOccurredInBlock = false

        for i in 0..<totalFrames {
            let x = Double(channelData[i])
            let iVal = x * cos(phase)
            let qVal = -x * sin(phase)
            phase += omega
            if phase > (2.0 * .pi) { phase -= (2.0 * .pi) }

            // I/Q Low-Pass Filter
            envI += lpfAlpha * (iVal - envI)
            envQ += lpfAlpha * (qVal - envQ)
            let env = sqrt(envI * envI + envQ * envQ)

            // Dynamic Leaky Peak and Floor Tracking
            if env > peakEnvelope {
                peakEnvelope = peakEnvelope * 0.999 + env * 0.001
            } else {
                peakEnvelope = max(0.003, peakEnvelope * 0.99998)
            }

            if env < noiseFloorEnvelope {
                noiseFloorEnvelope = noiseFloorEnvelope * 0.999 + env * 0.001
            } else {
                noiseFloorEnvelope = noiseFloorEnvelope * 0.99999 + env * 0.00001
            }

            noiseFloorEnvelope = min(noiseFloorEnvelope, peakEnvelope * 0.40)
            let dynamicRange = max(0.002, peakEnvelope - noiseFloorEnvelope)
            let vOn = noiseFloorEnvelope + 0.38 * dynamicRange
            let vOff = noiseFloorEnvelope + 0.20 * dynamicRange

            // Adaptive Schmitt Trigger
            if !isMarkActive {
                if env >= vOn {
                    // Space -> Mark transition
                    handleMarkOnset(spaceDuration: currentSpaceDuration)
                    isMarkActive = true
                    markOccurredInBlock = true
                    currentMarkDuration = sampleDuration
                    currentSpaceDuration = 0.0
                } else {
                    currentSpaceDuration += sampleDuration
                    handleSpaceProgression(spaceDuration: currentSpaceDuration)
                }
            } else {
                if env < vOff {
                    // Mark -> Space transition
                    handleMarkEnd(markDuration: currentMarkDuration)
                    isMarkActive = false
                    currentSpaceDuration = sampleDuration
                    currentMarkDuration = 0.0
                } else {
                    currentMarkDuration += sampleDuration
                    markOccurredInBlock = true

                    // Anti-stuck tone / continuous carrier guard (> 2.5 seconds is not Morse)
                    if currentMarkDuration > 2.5 {
                        isMarkActive = false
                        currentMarkDuration = 0.0
                        activeCharacterBuffer = ""
                    }
                }
            }
        }

        // 5. Update Published UI State
        let snrDb = 20.0 * log10(max(1.0, peakEnvelope / max(0.0001, noiseFloorEnvelope)))
        self.audioInputLevel = peak
        self.spectrumBins = fullBins
        self.signalToNoiseRatioDb = max(0.0, min(45.0, snrDb))
        self.isSignalDetected = isMarkActive || markOccurredInBlock
    }

    // MARK: - Sub-Chunk Morse State Logic

    private func handleMarkOnset(spaceDuration: Double) {
        // Space was long enough to separate characters (> 1.75 dits)
        if spaceDuration >= currentDitEstimate * 1.75 {
            commitActiveCharacter()
        }
        // Space was long enough to separate words (> 4.2 dits)
        if spaceDuration >= currentDitEstimate * 4.2 && !hasCommittedWordBreak {
            commitWordBreak()
        }
    }

    private func handleSpaceProgression(spaceDuration: Double) {
        // Character timeout while idling in space
        if !activeCharacterBuffer.isEmpty && spaceDuration >= currentDitEstimate * 1.90 {
            commitActiveCharacter()
        }
        // Word timeout while idling in space
        if spaceDuration >= currentDitEstimate * 4.5 && !hasCommittedWordBreak && !rawDecodedText.isEmpty {
            commitWordBreak()
        }
    }

    private func handleMarkEnd(markDuration: Double) {
        // Glitch rejection: ignore pulses shorter than 15ms
        guard markDuration >= 0.015 else { return }

        // Carrier rejection: ignore continuous tones longer than 2.0 seconds
        guard markDuration <= 2.0 else {
            activeCharacterBuffer = ""
            return
        }

        hasCommittedWordBreak = false

        // Dit vs Dah Decision
        // Nominal: Dit = 1 unit, Dah = 3 units. Midpoint boundary at 1.85 units.
        let ditThreshold = currentDitEstimate * 1.85

        if markDuration < ditThreshold {
            // Dit "."
            activeCharacterBuffer.append(".")
            recentDitDurations.append(markDuration)
            if recentDitDurations.count > 10 { recentDitDurations.removeFirst() }
            currentDitEstimate = currentDitEstimate * 0.82 + markDuration * 0.18
        } else {
            // Dah "-"
            activeCharacterBuffer.append("-")
            recentDahDurations.append(markDuration)
            if recentDahDurations.count > 10 { recentDahDurations.removeFirst() }
            let ditFromDah = markDuration / 3.0
            currentDitEstimate = currentDitEstimate * 0.82 + ditFromDah * 0.18
        }

        // Clamp speed estimate to realistic limits (8 WPM to 50 WPM)
        currentDitEstimate = max(0.024, min(0.150, currentDitEstimate))

        // Update WPM and Dit/Dah ratio
        let newWpm = 1.2 / currentDitEstimate
        let ditAvg = recentDitDurations.isEmpty ? currentDitEstimate : recentDitDurations.reduce(0, +) / Double(recentDitDurations.count)
        let dahAvg = recentDahDurations.isEmpty ? currentDitEstimate * 3.0 : recentDahDurations.reduce(0, +) / Double(recentDahDurations.count)
        let ratio = dahAvg / max(0.01, ditAvg)

        self.estimatedWPM = min(50.0, max(8.0, self.estimatedWPM * 0.85 + newWpm * 0.15))
        self.ditDahRatio = min(6.0, max(1.5, ratio))
    }

    private func commitActiveCharacter() {
        guard !activeCharacterBuffer.isEmpty else { return }
        let pattern = activeCharacterBuffer
        activeCharacterBuffer = ""

        if let char = Self.reverseMorseAlphabet[pattern] {
            self.rawDecodedText.append(char)
            self.tokenizeStream()
        }
    }

    private func commitWordBreak() {
        guard !hasCommittedWordBreak else { return }
        hasCommittedWordBreak = true

        if !self.rawDecodedText.isEmpty && !self.rawDecodedText.hasSuffix(" ") {
            self.rawDecodedText.append(" ")
            self.tokenizeStream()
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

    // MARK: - Narrowband AFC & Wideband Filter Bank

    private func updateNarrowbandAFC(bins: [CWSpectrumBin]) {
        let minFreq = max(300.0, nominalPitchHz - 60.0)
        let maxFreq = min(1800.0, nominalPitchHz + 60.0)

        var localMaxMag: Float = 0.0
        var bestFreq: Double = centerFrequencyHz

        for bin in bins where bin.frequencyHz >= minFreq && bin.frequencyHz <= maxFreq {
            if bin.magnitude > localMaxMag {
                localMaxMag = bin.magnitude
                bestFreq = bin.frequencyHz
            }
        }

        if localMaxMag > 0.003 && abs(bestFreq - centerFrequencyHz) > 4.0 {
            centerFrequencyHz = centerFrequencyHz * 0.90 + bestFreq * 0.10
        }
    }

    /// Evaluates spectrum from 300 Hz to 1800 Hz in 35 Hz intervals with Hann windowing
    func evaluateFilterBank(channelData: UnsafePointer<Float>, frameCount: Int) -> [CWSpectrumBin] {
        var results: [CWSpectrumBin] = []
        var id = 0

        for freq in stride(from: 300.0, through: 1800.0, by: 35.0) {
            let mag = windowedGoertzelMagnitude(channelData: channelData, frameCount: frameCount, targetFreq: freq)
            results.append(CWSpectrumBin(id: id, frequencyHz: freq, magnitude: mag))
            id += 1
        }

        return results
    }

    /// Goertzel algorithm with Hann windowing to suppress spectral leakage
    private func windowedGoertzelMagnitude(channelData: UnsafePointer<Float>, frameCount: Int, targetFreq: Double) -> Float {
        guard frameCount > 0, sampleRate > 0 else { return 0.0 }
        let k = Int(0.5 + (Double(frameCount) * targetFreq / sampleRate))
        let omega = (2.0 * .pi * Double(k)) / Double(frameCount)
        let coeff = Float(2.0 * cos(omega))

        var q0: Float = 0.0
        var q1: Float = 0.0
        var q2: Float = 0.0

        let invN = 1.0 / Double(frameCount)
        for i in 0..<frameCount {
            // Hann window: 0.5 * (1 - cos(2*pi*i/N))
            let w = Float(0.5 * (1.0 - cos(2.0 * .pi * Double(i) * invN)))
            let sample = channelData[i] * w
            q0 = coeff * q1 - q2 + sample
            q2 = q1
            q1 = q0
        }

        let real = q1 - q2 * Float(cos(omega))
        let imag = q2 * Float(sin(omega))
        let power = real * real + imag * imag
        return (sqrt(power) * 2.0) / Float(frameCount)
    }

    // MARK: - Direct Audio File Decoder API

    /// Decodes an audio file (.m4a, .wav, .mp3, etc.) through the DSP pipeline.
    public func decodeAudioFile(at fileURL: URL) async throws -> String {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let frameCount = UInt32(file.length)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "CWAudioDecoder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not allocate audio buffer for file"])
        }
        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw NSError(domain: "CWAudioDecoder", code: 2, userInfo: [NSLocalizedDescriptionKey: "No float audio data found"])
        }

        self.sampleRate = format.sampleRate

        // Pass 1: Find dominant pitch across whole file in 300..1800 Hz range
        var peakBins: [Double: Float] = [:]
        let scanStep = 2048
        let total = Int(buffer.frameLength)

        for i in stride(from: 0, to: total - scanStep, by: scanStep) {
            let chunkPtr = channelData.advanced(by: i)
            var localPeak: Float = 0.0
            for j in 0..<scanStep {
                let v = abs(chunkPtr[j])
                if v > localPeak { localPeak = v }
            }
            if localPeak > 0.015 {
                let bins = evaluateFilterBank(channelData: chunkPtr, frameCount: scanStep)
                for b in bins {
                    peakBins[b.frequencyHz] = max(peakBins[b.frequencyHz] ?? 0.0, b.magnitude)
                }
            }
        }

        if let best = peakBins.max(by: { $0.value < $1.value }) {
            self.setPitch(best.key)
        }

        // Pass 2: Process audio in standard blocks and stream demodulate
        self.clearBuffer()
        let blockSize = 2048
        for i in stride(from: 0, to: total, by: blockSize) {
            let len = min(blockSize, total - i)
            guard let subBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(len)) else { continue }
            subBuf.frameLength = UInt32(len)
            if let dest = subBuf.floatChannelData?[0] {
                memcpy(dest, channelData.advanced(by: i), len * MemoryLayout<Float>.size)
            }
            self.processAudioBuffer(subBuf)
        }

        // Commit any trailing character
        commitActiveCharacter()
        return rawDecodedText.trimmingCharacters(in: .whitespacesAndNewlines)
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
