//
//  SyntheticRFSignalEngine.swift
//  YAAM
//
//  Created by factoreal on 9/13/26.
//

import Accelerate
import Foundation
import FT8Codec

// MARK: - Fading Profile
nonisolated enum ChannelFadingProfile: String, CaseIterable, Identifiable, Sendable {
    case clean = "Clean / Direct Line"
    case mildQSB = "Mild Ionospheric QSB (0.2 Hz)"
    case deepRayleigh = "Deep Rayleigh Flutter (1.5 Hz)"
    case auroralFading = "High-Doppler Auroral (4.0 Hz)"

    var id: String { rawValue }

    var dopplerSpreadHz: Double {
        switch self {
        case .clean: return 0.0
        case .mildQSB: return 0.2
        case .deepRayleigh: return 1.5
        case .auroralFading: return 4.0
        }
    }

    var ricianKFactor: Double {
        switch self {
        case .clean: return 100.0
        case .mildQSB: return 4.0
        case .deepRayleigh: return 0.0 // Pure Rayleigh
        case .auroralFading: return 0.0
        }
    }
}

// MARK: - Synthetic Signal Model
nonisolated struct SyntheticSignalProfile: Identifiable, Sendable {
    let id: UUID
    var message: String
    var mode: String
    var baseAudioFrequencyHz: Double
    var snrDB: Double
    var slotParity: FT8SlotParity
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        message: String,
        mode: String = "FT8",
        baseAudioFrequencyHz: Double = 1500,
        snrDB: Double = -10.0,
        slotParity: FT8SlotParity = .even,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.message = message
        self.mode = mode
        self.baseAudioFrequencyHz = baseAudioFrequencyHz
        self.snrDB = snrDB
        self.slotParity = slotParity
        self.isEnabled = isEnabled
    }

    func isTransmitting(at date: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        if mode.uppercased() != "FT8" { return true }
        if slotParity == .continuous { return true }

        let calendar = Calendar(identifier: .gregorian)
        var cal = calendar
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.second, .nanosecond], from: date)
        let secondsInMinute = Double(comps.second ?? 0) + Double(comps.nanosecond ?? 0) / 1_000_000_000.0

        let slotIndex = Int(secondsInMinute / 15.0)
        let isEven = (slotIndex % 2 == 0)
        if slotParity == .even && !isEven { return false }
        if slotParity == .odd && isEven { return false }

        let slotSecond = secondsInMinute - Double(slotIndex) * 15.0
        let txStartOffset = 0.5
        let duration = 12.64 // Standard FT8 79 symbols * 0.160s
        return slotSecond >= txStartOffset && slotSecond < (txStartOffset + duration)
    }

    func statusDescription(at date: Date = Date()) -> String {
        if !isEnabled { return "Disabled" }
        if isTransmitting(at: date) { return "ON AIR" }
        return "Standby"
    }
}

// MARK: - Slot Parity
nonisolated enum FT8SlotParity: String, CaseIterable, Identifiable, Sendable {
    case even = "Even Slot (:00 / :30)"
    case odd = "Odd Slot (:15 / :45)"
    case continuous = "Continuous Loop"

    var id: String { rawValue }
}

// MARK: - Synthetic RF & Audio Signal Engine
nonisolated final class SyntheticRFSignalEngine: @unchecked Sendable {
    static let sampleRate: Double = 48_000.0
    static let samplesPerFrame: Int = 480 // 10 ms at 48 kHz

    // Channel Parameters
    var targetSNR: Double = -6.0 // dB
    var channelFading: ChannelFadingProfile = .mildQSB
    var dopplerShiftHz: Double = 0.0
    var dopplerDriftHzPerMin: Double = 0.0
    var qrnImpulseRate: Double = 0.0 // 0.0 = off, 1.0 = heavy static
    var simulatedPacketLossPercent: Double = 0.0 // 0% to 25%
    var simulatedJitterMs: Double = 0.0 // 0 to 100ms
    var isNoiseEnabled: Bool = true

    // Audio Output Callback
    var onFrameGenerated: (@Sendable ([Float]) -> Void)?
    var onSpectrumCalculated: (@Sendable ([Float]) -> Void)?
    var onSignalsChanged: (@Sendable ([SyntheticSignalProfile]) -> Void)?

    // Internal State
    private let queue = DispatchQueue(label: "app.yaam.synthetic-rf-engine", qos: .userInteractive)
    private var isRunning = false
    private var frameTimer: DispatchSourceTimer?
    private var sampleCounter: UInt64 = 0

    // Fading filter state
    private var fadingPhaseI: Double = 0.0
    private var fadingPhaseQ: Double = 0.5
    private var fadingI: Double = 1.0
    private var fadingQ: Double = 0.0

    // Doppler phase accumulator
    private var dopplerPhase: Double = 0.0

    // Active signal generators
    private var activeSignals: [SyntheticSignalProfile] = []
    private var signalGenerators: [UUID: SignalWaveformPlayer] = [:]

    // FFT analysis buffer for visual waterfall (512 points)
    private var fftAccumulator: [Float] = []
    private let fftSize: Int = 512
    private var fftSetup: vDSP_DFT_Setup?
    private var lastSpectrumPublishUptime: UInt64 = 0

    /// Controls whether FFT spectrum is computed (only active when visualizer tab is displayed)
    var isSpectrumActive: Bool = false

    init() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
        setupDefaultSignals()
    }

    deinit {
        stop()
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    func setupDefaultSignals() {
        queue.async { [weak self] in
            guard let self else { return }
            self.activeSignals = [
                SyntheticSignalProfile(message: "CQ EP2AES LL45", baseAudioFrequencyHz: 1250, snrDB: 0.0, slotParity: .even),
                SyntheticSignalProfile(message: "K1ABC EP2AES -08", baseAudioFrequencyHz: 1680, snrDB: -8.0, slotParity: .even),
                SyntheticSignalProfile(message: "CQ DX JA1XYZ PM95", baseAudioFrequencyHz: 850, snrDB: 2.0, slotParity: .odd),
                SyntheticSignalProfile(message: "DL3DXX W1AW FN31", baseAudioFrequencyHz: 2150, snrDB: -12.0, slotParity: .odd),
                SyntheticSignalProfile(message: "CQ DX EP2AES LL45", baseAudioFrequencyHz: 1450, snrDB: 4.0, slotParity: .odd)
            ]
            self.rebuildGenerators()
            let list = self.activeSignals
            self.onSignalsChanged?(list)
        }
    }

    func setSignals(_ signals: [SyntheticSignalProfile]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.activeSignals = signals
            self.rebuildGenerators()
            let list = self.activeSignals
            self.onSignalsChanged?(list)
        }
    }

    func addSignal(_ signal: SyntheticSignalProfile) {
        queue.async { [weak self] in
            guard let self else { return }
            self.activeSignals.append(signal)
            self.rebuildGenerators()
            let list = self.activeSignals
            self.onSignalsChanged?(list)
        }
    }

    func removeSignal(id: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            self.activeSignals.removeAll(where: { $0.id == id })
            self.signalGenerators.removeValue(forKey: id)
            let list = self.activeSignals
            self.onSignalsChanged?(list)
        }
    }

    func toggleSignal(id: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            if let idx = self.activeSignals.firstIndex(where: { $0.id == id }) {
                self.activeSignals[idx].isEnabled.toggle()
                self.rebuildGenerators()
                let list = self.activeSignals
                self.onSignalsChanged?(list)
            }
        }
    }

    func clearSignals() {
        queue.async { [weak self] in
            guard let self else { return }
            self.activeSignals.removeAll()
            self.signalGenerators.removeAll()
            self.onSignalsChanged?([])
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.rebuildGenerators()
            self.startTimer()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.isRunning = false
            self.frameTimer?.cancel()
            self.frameTimer = nil
        }
    }

    private func startTimer() {
        frameTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        // Strictly every 10 ms (100 times per second)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in
            self?.produceNextFrame()
        }
        timer.resume()
        frameTimer = timer
    }

    private func rebuildGenerators() {
        var updated: [UUID: SignalWaveformPlayer] = [:]
        for profile in activeSignals where profile.isEnabled {
            if let existing = signalGenerators[profile.id] {
                existing.update(profile: profile)
                updated[profile.id] = existing
            } else {
                updated[profile.id] = SignalWaveformPlayer(profile: profile)
            }
        }
        signalGenerators = updated
    }

    // MARK: - Frame Production Pipeline
    private func produceNextFrame() {
        guard isRunning else { return }
        let count = Self.samplesPerFrame
        var combinedSignal = [Float](repeating: 0.0, count: count)

        // 1. Synthesize all active signals
        let now = Date()
        for (_, generator) in signalGenerators {
            generator.render(into: &combinedSignal, at: now, count: count, sampleRate: Self.sampleRate)
        }

        // 2. Channel Simulation: Apply Doppler Shift & Drift
        if dopplerShiftHz != 0.0 || dopplerDriftHzPerMin != 0.0 {
            applyDoppler(to: &combinedSignal, count: count)
        }

        // 3. Channel Simulation: Apply Ionospheric Multipath Fading (Rayleigh / Rician)
        if channelFading != .clean {
            applyFading(to: &combinedSignal, count: count)
        }

        // 4. Channel Simulation: Additive White Gaussian Noise (AWGN) to match target SNR
        if isNoiseEnabled {
            applyAWGN(to: &combinedSignal, count: count)
        }

        // 5. Channel Simulation: Atmospheric Static & QRN Bursts
        if qrnImpulseRate > 0.0 {
            applyQRN(to: &combinedSignal, count: count)
        }

        // 6. Hard-limit output to [-1.0, 1.0]
        for i in 0..<count {
            combinedSignal[i] = max(-1.0, min(1.0, combinedSignal[i]))
        }

        // 7. Push spectrum slice to FFT visualizer
        accumulateForFFT(samples: combinedSignal)

        // 8. Simulated Packet Loss: Drop frame if simulated loss triggers
        if simulatedPacketLossPercent > 0.0 {
            let roll = Double.random(in: 0...100)
            if roll < simulatedPacketLossPercent {
                return // Dropped frame
            }
        }

        // 9. Dispatch audio frame
        sampleCounter &+= UInt64(count)
        onFrameGenerated?(combinedSignal)
    }

    // MARK: - DSP: Doppler Shift & Drift
    private func applyDoppler(to buffer: inout [Float], count: Int) {
        let elapsedMinutes = Double(sampleCounter) / (Self.sampleRate * 60.0)
        let currentDopplerHz = dopplerShiftHz + (dopplerDriftHzPerMin * elapsedMinutes)
        let phaseStep = (2.0 * Double.pi * currentDopplerHz) / Self.sampleRate

        for i in 0..<count {
            dopplerPhase += phaseStep
            if dopplerPhase > 2.0 * Double.pi { dopplerPhase -= 2.0 * Double.pi }
            let mod = Float(cos(dopplerPhase))
            buffer[i] *= mod
        }
    }

    // MARK: - DSP: Rayleigh / Rician Fading
    private func applyFading(to buffer: inout [Float], count: Int) {
        let fm = channelFading.dopplerSpreadHz
        let phaseStep = (2.0 * Double.pi * fm) / Self.sampleRate
        let kFactor = channelFading.ricianKFactor

        for i in 0..<count {
            fadingPhaseI += phaseStep * 1.07
            fadingPhaseQ += phaseStep * 0.93
            if fadingPhaseI > 2.0 * Double.pi { fadingPhaseI -= 2.0 * Double.pi }
            if fadingPhaseQ > 2.0 * Double.pi { fadingPhaseQ -= 2.0 * Double.pi }

            // Low-pass filtered complex Gaussian process
            let inoise = cos(fadingPhaseI) + 0.3 * sin(fadingPhaseI * 2.3)
            let qnoise = sin(fadingPhaseQ) + 0.3 * cos(fadingPhaseQ * 1.7)

            fadingI = (fadingI * 0.998) + (inoise * 0.002)
            fadingQ = (fadingQ * 0.998) + (qnoise * 0.002)

            // Rayleigh envelope with Rician specular component
            let specular = sqrt(kFactor / (kFactor + 1.0))
            let diffuse = sqrt(1.0 / (kFactor + 1.0))
            let envelope = Float(specular + diffuse * sqrt((fadingI * fadingI) + (fadingQ * fadingQ)))

            buffer[i] *= envelope
        }
    }

    // MARK: - DSP: Additive White Gaussian Noise (AWGN) with Exact SNR
    private func applyAWGN(to buffer: inout [Float], count: Int) {
        // Calibrated receiver noise floor: ~ -36 dBFS (sigma = 0.015)
        // Scaled smoothly with targetSNR if user adjusts noise slider
        let baseNoiseSigma: Double = 0.015
        let noiseSigma = baseNoiseSigma * pow(10.0, min(10.0, max(-20.0, -targetSNR)) / 40.0)
        let clampedSigma = min(0.035, max(0.005, noiseSigma))

        // Box-Muller transform to generate Gaussian noise
        for i in stride(from: 0, to: count, by: 2) {
            let u1 = max(1e-12, Double.random(in: 0...1))
            let u2 = Double.random(in: 0...1)
            let radius = sqrt(-2.0 * log(u1)) * clampedSigma
            let theta = 2.0 * Double.pi * u2

            buffer[i] += Float(radius * cos(theta))
            if i + 1 < count {
                buffer[i + 1] += Float(radius * sin(theta))
            }
        }
    }

    // MARK: - DSP: Atmospheric Static / QRN Impulses
    private func applyQRN(to buffer: inout [Float], count: Int) {
        // Poisson probability of atmospheric crackle in this 10ms frame
        let probability = qrnImpulseRate * 0.08
        if Double.random(in: 0...1) < probability {
            let impulseLocation = Int.random(in: 0..<count)
            let impulseAmplitude = Float.random(in: 0.15...0.30) * (Bool.random() ? 1.0 : -1.0)
            let decayLength = min(count - impulseLocation, Int.random(in: 20...120))

            for j in 0..<decayLength {
                let decay = exp(-Float(j) / 25.0)
                buffer[impulseLocation + j] += impulseAmplitude * decay
            }
        }
    }

    // MARK: - FFT Waterfall & Spectrum Accumulation
    private func accumulateForFFT(samples: [Float]) {
        guard isSpectrumActive else {
            if !fftAccumulator.isEmpty { fftAccumulator.removeAll() }
            return
        }
        fftAccumulator.append(contentsOf: samples)
        // Prevent unbounded memory growth if UI is paused
        if fftAccumulator.count > fftSize * 4 {
            fftAccumulator = Array(fftAccumulator.suffix(fftSize))
        }
        while fftAccumulator.count >= fftSize {
            let slice = Array(fftAccumulator.prefix(fftSize))
            fftAccumulator.removeFirst(fftSize / 2) // 50% overlap
            computeFFT(slice: slice)
        }
    }

    private func computeFFT(slice: [Float]) {
        // Rate-limit UI spectrum calculation to ~15 Hz (every 66 ms) to keep main thread light
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastSpectrumPublishUptime >= 66_000_000 else { return }
        lastSpectrumPublishUptime = now

        guard let setup = fftSetup, isSpectrumActive else { return }
        guard slice.count >= fftSize else { return }

        var windowed = [Float](repeating: 0.0, count: fftSize)
        var window = [Float](repeating: 0.0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(slice, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var imagIn = [Float](repeating: 0.0, count: fftSize)
        var realOut = [Float](repeating: 0.0, count: fftSize)
        var imagOut = [Float](repeating: 0.0, count: fftSize)

        vDSP_DFT_Execute(setup, windowed, imagIn, &realOut, &imagOut)

        var magnitudes = [Float](repeating: 0.0, count: fftSize / 2)
        realOut.withUnsafeMutableBufferPointer { rOut in
            imagOut.withUnsafeMutableBufferPointer { iOut in
                var split = DSPSplitComplex(realp: rOut.baseAddress!, imagp: iOut.baseAddress!)
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        // Convert to dB
        var normalized = [Float](repeating: 0.0, count: fftSize / 2)
        var zero: Float = 1e-6
        vDSP_vdbcon(magnitudes, 1, &zero, &normalized, 1, vDSP_Length(fftSize / 2), 0)

        // Sanitize: ensure all values are finite and non-NaN
        for i in 0..<normalized.count {
            let val = normalized[i]
            if !val.isFinite || val.isNaN {
                normalized[i] = -120.0
            } else {
                normalized[i] = max(-120.0, min(10.0, val))
            }
        }

        // Publish to UI spectrum callback safely
        DispatchQueue.main.async { [weak self] in
            self?.onSpectrumCalculated?(normalized)
        }
    }
}

// MARK: - Individual Waveform Generator / Player
nonisolated final class SignalWaveformPlayer: @unchecked Sendable {
    private var profile: SyntheticSignalProfile
    private var tones: [UInt8] = []
    private var preRenderedSamples: [Float] = []
    private var isPrepared = false
    private var continuousPlaybackIndex: Int = 0
    private var phase: Double = 0.0

    // CW Morse Constants
    private var morseElements: [Bool] = [] // true = tone on, false = space
    private var morseElementIndex: Int = 0
    private var morseSampleCounter: Int = 0

    init(profile: SyntheticSignalProfile) {
        self.profile = profile
        prepare()
    }

    func update(profile: SyntheticSignalProfile) {
        let changed = self.profile.message != profile.message ||
                      self.profile.mode != profile.mode ||
                      self.profile.baseAudioFrequencyHz != profile.baseAudioFrequencyHz
        self.profile = profile
        if changed {
            prepare()
        }
    }

    private func prepare() {
        if profile.mode.uppercased() == "FT8" {
            prepareFT8()
        } else if profile.mode.uppercased() == "CW" {
            prepareCW()
        } else {
            // Default two-tone test or single tone
            isPrepared = true
        }
    }

    private func prepareFT8() {
        let text = profile.message.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        do {
            let encodedTones = try FT8Codec.encode(text, protocol: .ft8)
            tones = encodedTones
            let samples = FT8Codec.synthesize(
                tones: encodedTones,
                baseFrequencyHz: Float(profile.baseAudioFrequencyHz),
                protocol: .ft8,
                sampleRate: Int(SyntheticRFSignalEngine.sampleRate)
            )
            preRenderedSamples = samples
            isPrepared = !samples.isEmpty
        } catch {
            // Fallback synthetic tones if message cannot be packed (uses Costas sync arrays)
            let fallbackTones: [UInt8] = [3, 1, 4, 0, 6, 5, 2] + Array(repeating: 2, count: 65) + [3, 1, 4, 0, 6, 5, 2]
            tones = fallbackTones
            let samples = FT8Codec.synthesize(
                tones: fallbackTones,
                baseFrequencyHz: Float(profile.baseAudioFrequencyHz),
                protocol: .ft8,
                sampleRate: Int(SyntheticRFSignalEngine.sampleRate)
            )
            preRenderedSamples = samples
            isPrepared = !samples.isEmpty
        }
    }

    private func prepareCW() {
        morseElements = MorseCodeEncoder.elements(for: profile.message)
        isPrepared = true
    }

    func render(into buffer: inout [Float], at date: Date, count: Int, sampleRate: Double) {
        guard isPrepared, profile.isEnabled else { return }
        let snrClamped = min(10.0, max(-24.0, profile.snrDB))
        let amplitude: Float = Float(0.18 * pow(10.0, snrClamped / 40.0))

        if profile.mode.uppercased() == "FT8" {
            renderFT8(into: &buffer, at: date, count: count, sampleRate: sampleRate, amplitude: amplitude)
        } else if profile.mode.uppercased() == "CW" {
            renderCW(into: &buffer, count: count, sampleRate: sampleRate, amplitude: amplitude)
        } else {
            // Pure tone carrier
            let freq = profile.baseAudioFrequencyHz
            let step = (2.0 * Double.pi * freq) / sampleRate
            for i in 0..<count {
                phase += step
                if phase > 2.0 * Double.pi { phase -= 2.0 * Double.pi }
                buffer[i] += Float(sin(phase)) * amplitude
            }
        }
    }

    private func renderFT8(into buffer: inout [Float], at date: Date, count: Int, sampleRate: Double, amplitude: Float) {
        guard !preRenderedSamples.isEmpty else { return }

        if profile.slotParity == .continuous {
            // Continuous loop with 0.5s inter-transmission pause
            let silenceGap = Int(sampleRate * 0.5)
            let totalLoopCount = preRenderedSamples.count + silenceGap
            for i in 0..<count {
                let pos = continuousPlaybackIndex
                if pos < preRenderedSamples.count {
                    buffer[i] += preRenderedSamples[pos] * amplitude
                }
                continuousPlaybackIndex = (continuousPlaybackIndex + 1) % totalLoopCount
            }
            return
        }

        // Slot-aligned FT8 playback (:00 / :30 even slot, :15 / :45 odd slot)
        let calendar = Calendar(identifier: .gregorian)
        var cal = calendar
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.second, .nanosecond], from: date)
        let secondsInMinute = Double(comps.second ?? 0) + Double(comps.nanosecond ?? 0) / 1_000_000_000.0

        let slotIndex = Int(secondsInMinute / 15.0)
        let isEven = (slotIndex % 2 == 0)
        if profile.slotParity == .even && !isEven { return }
        if profile.slotParity == .odd && isEven { return }

        let slotSecond = secondsInMinute - Double(slotIndex) * 15.0
        let txStartOffset = 0.5
        let duration = Double(preRenderedSamples.count) / sampleRate

        if slotSecond < txStartOffset || slotSecond >= (txStartOffset + duration) {
            return
        }

        let startSampleIndex = Int((slotSecond - txStartOffset) * sampleRate)
        for i in 0..<count {
            let sampleIdx = startSampleIndex + i
            if sampleIdx >= 0 && sampleIdx < preRenderedSamples.count {
                buffer[i] += preRenderedSamples[sampleIdx] * amplitude
            }
        }
    }

    private func renderCW(into buffer: inout [Float], count: Int, sampleRate: Double, amplitude: Float) {
        guard !morseElements.isEmpty else { return }
        let wpm = 20.0
        let ditSamples = Int(sampleRate * (1.2 / wpm))
        let freq = profile.baseAudioFrequencyHz > 0 ? profile.baseAudioFrequencyHz : 700.0
        let step = (2.0 * Double.pi * freq) / sampleRate

        for i in 0..<count {
            let isToneOn = morseElements[morseElementIndex % morseElements.count]
            if isToneOn {
                phase += step
                if phase > 2.0 * Double.pi { phase -= 2.0 * Double.pi }

                // Cosine raised envelope (5ms smoothing) to prevent key clicks
                let rampSamples = Int(sampleRate * 0.005)
                let pos = morseSampleCounter
                let remain = ditSamples - morseSampleCounter
                var env: Float = 1.0
                if pos < rampSamples {
                    env = 0.5 * (1.0 - Float(cos(Double.pi * Double(pos) / Double(rampSamples))))
                } else if remain < rampSamples {
                    env = 0.5 * (1.0 - Float(cos(Double.pi * Double(remain) / Double(rampSamples))))
                }
                buffer[i] += Float(sin(phase)) * amplitude * env
            }

            morseSampleCounter += 1
            if morseSampleCounter >= ditSamples {
                morseSampleCounter = 0
                morseElementIndex = (morseElementIndex + 1) % morseElements.count
            }
        }
    }
}

// MARK: - Morse Code Helper
nonisolated enum MorseCodeEncoder {
    private static let table: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
        "F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
        "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---",
        "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
        "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--",
        "Z": "--..", "0": "-----", "1": ".----", "2": "..---", "3": "...--",
        "4": "....-", "5": ".....", "6": "-....", "7": "--...", "8": "---..",
        "9": "----.", "/": "-..-.", "?": "..--..", " ": " "
    ]

    static func elements(for text: String) -> [Bool] {
        var result: [Bool] = []
        for char in text.uppercased() {
            if char == " " {
                result.append(contentsOf: Array(repeating: false, count: 4))
                continue
            }
            guard let pattern = table[char] else { continue }
            for symbol in pattern {
                if symbol == "." {
                    result.append(true) // 1 dit
                    result.append(false) // 1 inter-element space
                } else if symbol == "-" {
                    result.append(contentsOf: [true, true, true]) // 3 dits (dah)
                    result.append(false)
                }
            }
            result.append(contentsOf: [false, false]) // 3 total spaces between letters
        }
        result.append(contentsOf: Array(repeating: false, count: 6)) // word space
        return result.isEmpty ? [true, false] : result
    }
}
