//
//  DigitalModemEngine.swift
//  YAAM
//
//  Real-Time DSP Digital Modem Engine for RTTY & PSK31
//  Provides complete demodulation, modulation, visual scope tracking (Lissajous crossed-ellipses),
//  audio waterfall FFT, type-ahead TX queue, macros, and HF on-air simulation.
//

import Accelerate
import AVFoundation
import Combine
import Foundation

// MARK: - Digital Mode Enumeration

public enum DigitalOperatingMode: String, CaseIterable, Identifiable, Sendable {
    case rtty45_170 = "RTTY 45.45 / 170"
    case rtty75_170 = "RTTY 75 / 170"
    case rtty45_850 = "RTTY 45.45 / 850"
    case psk31 = "BPSK31"
    case bpsk63 = "BPSK63"

    public var id: String { rawValue }

    public var isRTTY: Bool {
        switch self {
        case .rtty45_170, .rtty75_170, .rtty45_850: return true
        case .psk31, .bpsk63: return false
        }
    }

    public var isPSK: Bool {
        !isRTTY
    }

    public var baudRate: Double {
        switch self {
        case .rtty45_170, .rtty45_850: return 45.45
        case .rtty75_170: return 75.0
        case .psk31: return 31.25
        case .bpsk63: return 62.5
        }
    }

    public var shiftHz: Double {
        switch self {
        case .rtty45_170, .rtty75_170: return 170.0
        case .rtty45_850: return 850.0
        case .psk31, .bpsk63: return 0.0
        }
    }

    public var adifMode: String {
        switch self {
        case .rtty45_170, .rtty75_170, .rtty45_850: return "RTTY"
        case .psk31, .bpsk63: return "PSK31"
        }
    }
}

// MARK: - Baudot ITA2 Codec

public struct BaudotCodec: Sendable {
    public enum ShiftState: Sendable {
        case letters
        case figures
    }

    // 5-bit ITA2 code representation: bit 0 is Start/LSB, bit 4 is MSB
    // Index 0 to 31
    public static let lettersTable: [Character] = [
        "\0", "E", "\n", "A", " ", "S", "I", "U",
        "\r", "D", "R",  "J", "N", "F", "C", "K",
        "T",  "Z", "L",  "W", "H", "Y", "P", "Q",
        "O",  "B", "G",  "\0", "M", "X", "V", "\0"
    ]

    public static let figuresTable: [Character] = [
        "\0", "3", "\n", "-", " ", "\'", "8", "7",
        "\r", "$", "4",  "\u{0007}", ",", "!", ":", "(",
        "5",  "+", ")",  "2", "#", "6", "0", "1",
        "9",  "?", "&",  "\0", ".", "/", "=", "\0"
    ]

    public static let codeLTRS: UInt8 = 31 // 0b11111
    public static let codeFIGS: UInt8 = 27 // 0b11011
    public static let codeSpace: UInt8 = 4  // 0b00100
    public static let codeCR: UInt8 = 8     // 0b01000
    public static let codeLF: UInt8 = 2     // 0b00010

    public static func decode(code: UInt8, state: inout ShiftState, unshiftOnSpace: Bool) -> Character? {
        let cleanCode = Int(code & 0x1F)
        if cleanCode == Int(codeLTRS) {
            state = .letters
            return nil
        }
        if cleanCode == Int(codeFIGS) {
            state = .figures
            return nil
        }
        if cleanCode == Int(codeSpace) {
            if unshiftOnSpace {
                state = .letters
            }
            return " "
        }

        switch state {
        case .letters:
            let char = lettersTable[cleanCode]
            return char == "\0" ? nil : char
        case .figures:
            let char = figuresTable[cleanCode]
            return char == "\0" ? nil : char
        }
    }

    public static func encode(char: Character, currentState: inout ShiftState) -> [UInt8] {
        let upper = Character(char.uppercased())
        if upper == " " {
            return [codeSpace]
        }
        if upper == "\r" {
            return [codeCR]
        }
        if upper == "\n" {
            return [codeLF]
        }

        // Try letters first
        if let idx = lettersTable.firstIndex(of: upper), idx != Int(codeLTRS), idx != Int(codeFIGS), idx != 0 {
            if currentState != .letters {
                currentState = .letters
                return [codeLTRS, UInt8(idx)]
            }
            return [UInt8(idx)]
        }

        // Try figures
        if let idx = figuresTable.firstIndex(of: upper), idx != Int(codeLTRS), idx != Int(codeFIGS), idx != 0 {
            if currentState != .figures {
                currentState = .figures
                return [codeFIGS, UInt8(idx)]
            }
            return [UInt8(idx)]
        }

        return []
    }
}

// MARK: - Varicode (PSK31 / BPSK63) Codec

public struct VaricodeCodec: Sendable {
    // Standard Peter Martinez G3PLX Varicode table (ASCII 0 - 127)
    // Characters are encoded as binary strings where zeros are always single (never '00')
    // and terminated by '00' (inter-character delimiter).
    // G3PLX, QEX July/August 1999, Table 1:
    // https://www.arrl.org/files/file/Technology/tis/info/pdf/x9907003.pdf
    public static let asciiToVaricode: [String] = [
        /* 000-007 */ "1010101011", "1011011011", "1011101101", "1101110111", "1011101011", "1101011111", "1011101111", "1011111101",
        /* 008-015 */ "1011111111", "11101111", "11101", "1101101111", "1011011101", "11111", "1101110101", "1110101011",
        /* 016-023 */ "1011110111", "1011110101", "1110101101", "1110101111", "1101011011", "1101101011", "1101101101", "1101010111",
        /* 024-031 */ "1101111011", "1101111101", "1110110111", "1101010101", "1101011101", "1110111011", "1011111011", "1101111111",
        /* 032-039 */ "1", "111111111", "101011111", "111110101", "111011011", "1011010101", "1010111011", "101111111",
        /* 040-047 */ "11111011", "11110111", "101101111", "111011111", "1110101", "110101", "1010111", "110101111",
        /* 048-055 */ "10110111", "10111101", "11101101", "11111111", "101110111", "101011011", "101101011", "110101101",
        /* 056-063 */ "110101011", "110110111", "11110101", "110111101", "111101101", "1010101", "111010111", "1010101111",
        /* 064-071 */ "1010111101", "1111101", "11101011", "10101101", "10110101", "1110111", "11011011", "11111101",
        /* 072-079 */ "101010101", "1111111", "111111101", "101111101", "11010111", "10111011", "11011101", "10101011",
        /* 080-087 */ "11010101", "111011101", "10101111", "1101111", "1101101", "101010111", "110110101", "101011101",
        /* 088-095 */ "101110101", "101111011", "1010101101", "111110111", "111101111", "111111011", "1010111111", "101101101",
        /* 096-103 */ "1011011111", "1011", "1011111", "101111", "101101", "11", "111101", "1011011",
        /* 104-111 */ "101011", "1101", "111101011", "10111111", "11011", "111011", "1111", "111",
        /* 112-119 */ "111111", "110111111", "10101", "10111", "101", "110111", "1111011", "1101011",
        /* 120-127 */ "11011111", "1011101", "111010101", "1010110111", "110111011", "1010110101", "1011010111", "1110110101"
    ]

    public static let varicodeToAscii: [String: Character] = {
        var dict: [String: Character] = [:]
        for (i, pattern) in asciiToVaricode.enumerated() {
            if let scalar = UnicodeScalar(i) {
                dict[pattern] = Character(scalar)
            }
        }
        return dict
    }()

    public static func encode(char: Character) -> String {
        let ascii = char.asciiValue ?? 32
        let idx = Int(ascii & 0x7F)
        guard idx < asciiToVaricode.count else { return "100" }
        return asciiToVaricode[idx] + "00" // 00 is inter-character delimiter
    }
}

// MARK: - Lissajous XY Point (For Crossed-Ellipses Scope)

public struct DigitalScopeSample: Sendable {
    public let x: Float // Space deflection (Horizontal)
    public let y: Float // Mark deflection (Vertical)

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

// MARK: - Decoded Digital Token

public struct DigitalDecodedToken: Identifiable, Sendable {
    public let id = UUID()
    public let text: String
    public let isCallsign: Bool
    public let isReport: Bool
    public let isCQ: Bool
    public let isExchange: Bool
    public let timestamp: Date

    public init(text: String, isCallsign: Bool, isReport: Bool, isCQ: Bool, isExchange: Bool, timestamp: Date = Date()) {
        self.text = text
        self.isCallsign = isCallsign
        self.isReport = isReport
        self.isCQ = isCQ
        self.isExchange = isExchange
        self.timestamp = timestamp
    }
}

// MARK: - Macro Definition

public struct DigitalMacro: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public var template: String

    public init(id: Int, name: String, template: String) {
        self.id = id
        self.name = name
        self.template = template
    }

    public static let standardPresets: [DigitalMacro] = [
        .init(id: 1, name: "CQ", template: "CQ CQ DE {MYCALL} {MYCALL} K\r\n"),
        .init(id: 2, name: "Exch", template: "{CALL} UR {SENTRST} {SERIAL} {MYGRID} DE {MYCALL} K\r\n"),
        .init(id: 3, name: "TU", template: "TU 73 DE {MYCALL} QRZ?\r\n"),
        .init(id: 4, name: "MyCall", template: "{MYCALL} {MYCALL} \r\n"),
        .init(id: 5, name: "HisCall", template: "{CALL} \r\n"),
        .init(id: 6, name: "599", template: "UR 599 599 \r\n"),
        .init(id: 7, name: "73", template: "73 GL ES DX DE {MYCALL} SK\r\n"),
        .init(id: 8, name: "Brag", template: "RIG: YAAM SDR OP: {OP} QTH: {MYGRID} \r\n")
    ]
}

// MARK: - Digital Modem Engine Service

@MainActor
public final class DigitalModemEngine: ObservableObject {
    public static let shared = DigitalModemEngine()

    // MARK: - Published Operating Controls
    @Published public var operatingMode: DigitalOperatingMode = .rtty45_170
    @Published public var centerFrequencyHz: Double = 1500.0
    @Published public var customShiftHz: Double = 170.0
    @Published public var afcEnabled: Bool = true
    @Published public var unshiftOnSpace: Bool = true
    @Published public var reversePolarity: Bool = false // Normal: Mark is low/high depending on USB/LSB
    @Published public var squelchThreshold: Float = 0.08
    @Published public var isListening: Bool = false
    @Published public var isTransmitting: Bool = false
    @Published public var isSimulationActive: Bool = false

    // Audio & Transceiver State
    @Published public var audioInputLevel: Float = 0.0
    @Published public var signalToNoiseRatioDb: Double = 0.0
    @Published public var markLevel: Float = 0.0
    @Published public var spaceLevel: Float = 0.0
    @Published public var afcOffsetHz: Double = 0.0
    @Published public var baudotState: BaudotCodec.ShiftState = .letters

    // Decoded Output & Terminals
    @Published public var rxText: String = ""
    @Published public var decodedTokens: [DigitalDecodedToken] = []
    /// The TX box: what the operator typed and the macros added. Its first txSentCount characters have been sent.
    @Published public var txBufferText: String = "" {
        didSet { followEdit(from: oldValue) }
    }
    /// How many characters at the start of txBufferText have been sent; what is still to send is the rest.
    private(set) var txSentCount = 0
    private var restoringTXBuffer = false

    /// Only the pending suffix is editable in the station UI. Sent text is immutable history, so repeated text
    /// such as AAAA or ABAB never needs an inferred edit location.
    public var pendingTransmitText: String {
        get { String(txBufferText.dropFirst(txSentCount)) }
        set { txBufferText = String(txBufferText.prefix(txSentCount)) + newValue }
    }

    private func followEdit(from oldValue: String) {
        guard !restoringTXBuffer else { return }
        if txBufferText.isEmpty { txSentCount = 0; return }
        guard txSentCount > 0 else { return }
        let sent = String(oldValue.prefix(txSentCount))
        if !txBufferText.hasPrefix(sent) {
            restoringTXBuffer = true
            txBufferText = oldValue
            restoringTXBuffer = false
            txRefusal = "Sent text is kept as history. Edit the pending text, or stop and use Clear TX for a new message."
        }
    }
    @Published public var txTransmittedText: String = ""
    @Published public var txRemainingText: String = ""
    @Published public var txProgress: Double = 0.0

    // Visual Oscilloscope & Spectrum Feeds
    @Published public var scopeSamples: [DigitalScopeSample] = []
    @Published public var waterfallSpectrum: [Float] = Array(repeating: 0.0, count: 128)
    @Published public var constellationPoints: [CGPoint] = []

    // Active Target DX Info
    @Published public var targetCallsign: String = ""
    @Published public var targetReportSent: String = "599"
    @Published public var targetReportReceived: String = "599"
    @Published public var targetSerial: Int = 1
    @Published public var targetCountryName: String = ""
    @Published public var targetCountryFlag: String = "🌐"
    @Published public var targetContinent: String = ""
    @Published public var targetDistanceKm: Double? = nil

    // Station Settings
    @Published public var myCallsign: String = ""
    @Published public var myGrid: String = ""
    /// Why the last transmission was refused (no callsign of the operator, or one that is not accepted); empty
    /// otherwise. The station screen clears it when the active station profile changes.
    @Published public var txRefusal: String = ""
    @Published public var macros: [DigitalMacro] = DigitalMacro.standardPresets

    // Logging Callback
    public var logQSOHandler: ((_ call: String, _ mode: String, _ rstSent: String, _ rstRcvd: String, _ freqHz: UInt64, _ band: String) -> Void)?

    // Audio Engine
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var sampleRate: Double = 48000.0

    // DSP Timing & RTTY State
    private var sampleCounter: Int = 0
    private var currentBaudotCode: UInt8 = 0
    private var currentBitIndex: Int = 0
    private var samplesPerBit: Double = 0.0
    private var rttyRxState: RTTYRxFSM = .idle
    private var bitSampleAccumulator: Float = 0.0
    private var bitSampleCount: Int = 0
    private var pendingDecodedWord = ""
    private var decodedWordOverflow = false
    private var recentScopeBuffer: [DigitalScopeSample] = []

    // PSK31 State
    private var pskCarrierPhase: Double = 0.0
    private var pskLastPhase: Double = 0.0
    private var pskBitAccumulator: String = ""
    private var pskSamplesPerBit: Double = 0.0
    private var pskSampleIndex: Int = 0

    // TX Generation
    private var txTask: Task<Void, Never>?
    private var releaseTransmitPTT: (() -> Void)?
    private var simulationTimer: Timer?
    private var simulationPhraseIndex: Int = 0

    private enum RTTYRxFSM {
        case idle // Listening for start bit (Space)
        case startBit
        case dataBits
        case stopBit
    }

    public init() {
        self.samplesPerBit = 48000.0 / operatingMode.baudRate
        self.pskSamplesPerBit = 48000.0 / 31.25
        self.recentScopeBuffer.reserveCapacity(256)
        // Registered so that quitting YAAM can release this path (TransmitShutdown).
        TransmitShutdown.register("Digital modes", isTransmitting: { [weak self] in self?.isTransmitting ?? false }, producer: true,
                                  owner: self, release: { [weak self] in self?.stopTransmission() })
    }

    // MARK: - Pitch & Frequency Tuning Controls

    public func setCenterFrequency(_ hz: Double) {
        centerFrequencyHz = max(400.0, min(2800.0, hz))
    }

    public func adjustCenterFrequency(by deltaHz: Double) {
        setCenterFrequency(centerFrequencyHz + deltaHz)
    }

    public var effectiveMarkFrequency: Double {
        let shift = operatingMode.isRTTY ? (operatingMode.shiftHz > 0 ? operatingMode.shiftHz : customShiftHz) : 0.0
        let baseMark = centerFrequencyHz - (shift * 0.5)
        let actualMark = reversePolarity ? (centerFrequencyHz + (shift * 0.5)) : baseMark
        return actualMark + (afcEnabled ? afcOffsetHz : 0.0)
    }

    public var effectiveSpaceFrequency: Double {
        let shift = operatingMode.isRTTY ? (operatingMode.shiftHz > 0 ? operatingMode.shiftHz : customShiftHz) : 0.0
        let baseSpace = centerFrequencyHz + (shift * 0.5)
        let actualSpace = reversePolarity ? (centerFrequencyHz - (shift * 0.5)) : baseSpace
        return actualSpace + (afcEnabled ? afcOffsetHz : 0.0)
    }

    // MARK: - Start & Stop Audio Processing

    public func startListening() {
        guard !isListening else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            print("DigitalModemEngine: Invalid sample rate")
            return
        }

        self.sampleRate = format.sampleRate
        self.samplesPerBit = sampleRate / operatingMode.baudRate
        self.pskSamplesPerBit = sampleRate / 31.25

        // Player node for soundcard transmission audio
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let mixer = engine.mainMixerNode
        engine.connect(player, to: mixer, format: mixer.outputFormat(forBus: 0))
        self.playerNode = player

        // Install audio tap on input bus (2048 buffer size ~42ms at 48kHz)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            self.audioEngine = engine
            self.isListening = true
        } catch {
            print("DigitalModemEngine: AudioEngine start error: \(error)")
        }
    }

    public func stopListening() {
        guard isListening else { return }
        stopSimulation()
        stopTransmission()

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.audioEngine = nil
            self.playerNode = nil
        }

        isListening = false
        audioInputLevel = 0.0
        signalToNoiseRatioDb = 0.0
        markLevel = 0.0
        spaceLevel = 0.0
        scopeSamples.removeAll()
    }

    public func clearTerminals() {
        rxText = ""
        decodedTokens.removeAll()
        pendingDecodedWord = ""
        decodedWordOverflow = false
        txBufferText = ""
        txTransmittedText = ""
        txRemainingText = ""
        txProgress = 0.0
    }

    // MARK: - DSP Audio Buffer Demodulator

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let totalFrames = Int(buffer.frameLength)
        guard totalFrames > 0 else { return }

        // 1. Peak Audio Level for VU Meter
        var peak: Float = 0.0
        for i in stride(from: 0, to: totalFrames, by: 16) {
            let val = abs(channelData[i])
            if val > peak { peak = val }
        }

        // 2. Spectrum FFT for Waterfall (300 Hz - 3200 Hz)
        let spectrum = computeSpectrum(channelData: channelData, frameCount: min(1024, totalFrames))

        // 3. Mark and Space Tone Analysis
        let markFreq = effectiveMarkFrequency
        let spaceFreq = effectiveSpaceFrequency

        var localScope: [DigitalScopeSample] = []
        localScope.reserveCapacity(64)

        // Process in 64-sample sub-chunks for high temporal and phase resolution
        let subChunk = 64
        let subCount = totalFrames / subChunk

        var avgMark: Float = 0.0
        var avgSpace: Float = 0.0
        var decodedChars: [Character] = []
        var pskConstellationBatch: [CGPoint] = []

        for s in 0..<subCount {
            let offset = s * subChunk
            let ptr = channelData.advanced(by: offset)

            let (mReal, mImag) = quadratureDetect(channelData: ptr, frameCount: subChunk, targetFreq: markFreq)
            let (sReal, sImag) = quadratureDetect(channelData: ptr, frameCount: subChunk, targetFreq: spaceFreq)

            let mMag = sqrt(mReal * mReal + mImag * mImag)
            let sMag = sqrt(sReal * sReal + sImag * sImag)

            avgMark += mMag
            avgSpace += sMag

            // Generate Lissajous crossed-ellipses coordinates
            // X = Space deflection (Horizontal), Y = Mark deflection (Vertical)
            // Normalized with soft non-linear compression for glowing CRT appearance
            let scopeX = tanh(sMag * 14.0) * (sReal >= 0 ? 1.0 : -1.0)
            let scopeY = tanh(mMag * 14.0) * (mReal >= 0 ? 1.0 : -1.0)
            if s % 2 == 0 {
                localScope.append(DigitalScopeSample(x: scopeX, y: scopeY))
            }

            // Execute Mode-Specific Demodulation
            if operatingMode.isRTTY {
                // RTTY Slicer: Mark (1) vs Space (0)
                let discriminator = mMag - sMag
                let isMark = discriminator >= 0

                let newChar = processRTTYSymbol(isMark: isMark, samples: subChunk)
                if let newChar {
                    decodedChars.append(newChar)
                }
            } else {
                // PSK31 Coherent Phase & Varicode
                let (pskChar, constPt) = processPSKSymbol(real: mReal, imag: mImag, samples: subChunk)
                if let pskChar {
                    decodedChars.append(pskChar)
                }
                if let constPt {
                    pskConstellationBatch.append(constPt)
                }
            }
        }

        if subCount > 0 {
            avgMark /= Float(subCount)
            avgSpace /= Float(subCount)
        }

        let totalEnergy = max(0.0001, avgMark + avgSpace)
        let noiseFloor = max(0.0001, (spectrum.first ?? 0.01) * 0.5)
        let snr = 20.0 * log10(Double(totalEnergy) / Double(noiseFloor))

        // Update AFC Tracking
        if afcEnabled && operatingMode.isRTTY && totalEnergy > squelchThreshold {
            let balance = Double(avgSpace - avgMark) / Double(totalEnergy)
            // Gentle nudge toward center frequency
            afcOffsetHz += balance * 2.5
            afcOffsetHz = max(-45.0, min(45.0, afcOffsetHz))
        }

        // Dispatch UI updates to MainActor
        let currentPeak = peak
        let finalMark = avgMark
        let finalSpace = avgSpace
        let finalSNR = max(0.0, min(40.0, snr))
        let finalSpectrum = spectrum
        let finalScope = localScope
        let finalDecoded = decodedChars
        let finalConst = pskConstellationBatch

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioInputLevel = currentPeak
            self.markLevel = finalMark
            self.spaceLevel = finalSpace
            self.signalToNoiseRatioDb = finalSNR
            self.waterfallSpectrum = finalSpectrum
            self.scopeSamples = finalScope
            if !finalConst.isEmpty {
                self.constellationPoints = finalConst
            }
            if !finalDecoded.isEmpty {
                self.appendDecodedText(String(finalDecoded))
            }
        }
    }

    // MARK: - RTTY FSM Bit & Character Recovery

    private func processRTTYSymbol(isMark: Bool, samples: Int) -> Character? {
        let bitVal: Float = isMark ? 1.0 : -1.0
        bitSampleAccumulator += bitVal * Float(samples)
        bitSampleCount += samples

        switch rttyRxState {
        case .idle:
            // Continuous Mark carrier or noise; watch for falling edge to Space (Start Bit = 0)
            if !isMark && (markLevel + spaceLevel) > squelchThreshold {
                rttyRxState = .startBit
                bitSampleAccumulator = 0.0
                bitSampleCount = 0
            }
            return nil

        case .startBit:
            // Verify start bit at center (samplesPerBit)
            if Double(bitSampleCount) >= samplesPerBit {
                let decidedSpace = bitSampleAccumulator < 0
                if decidedSpace {
                    // Valid start bit confirmed! Proceed to 5 data bits
                    rttyRxState = .dataBits
                    currentBaudotCode = 0
                    currentBitIndex = 0
                    bitSampleAccumulator = 0.0
                    bitSampleCount = 0
                } else {
                    // False start/noise glitch, return to idle
                    rttyRxState = .idle
                }
            }
            return nil

        case .dataBits:
            if Double(bitSampleCount) >= samplesPerBit {
                let decidedBit = bitSampleAccumulator >= 0 ? 1 : 0
                if decidedBit == 1 {
                    currentBaudotCode |= (1 << currentBitIndex)
                }
                currentBitIndex += 1
                bitSampleAccumulator = 0.0
                bitSampleCount = 0

                if currentBitIndex >= 5 {
                    // All 5 data bits received; advance to stop bit
                    rttyRxState = .stopBit
                }
            }
            return nil

        case .stopBit:
            // Stop bit is Mark (1), duration at least 1.0 to 1.5 bits
            if Double(bitSampleCount) >= (samplesPerBit * 1.2) {
                let codeToDecode = currentBaudotCode
                rttyRxState = .idle
                bitSampleAccumulator = 0.0
                bitSampleCount = 0

                // Decode Baudot character
                var state = self.baudotState
                let char = BaudotCodec.decode(code: codeToDecode, state: &state, unshiftOnSpace: self.unshiftOnSpace)
                self.baudotState = state
                return char
            }
            return nil
        }
    }

    // MARK: - PSK31 Coherent Phase Demodulator

    private func processPSKSymbol(real: Float, imag: Float, samples: Int) -> (Character?, CGPoint?) {
        let phase = Double(atan2(imag, real))
        let deltaPhase = phase - pskLastPhase
        pskLastPhase = phase

        // Normalize deltaPhase between -pi and +pi
        var normalizedDelta = deltaPhase.truncatingRemainder(dividingBy: 2.0 * .pi)
        if normalizedDelta > .pi { normalizedDelta -= 2.0 * .pi }
        if normalizedDelta < -.pi { normalizedDelta += 2.0 * .pi }

        let constPoint = CGPoint(x: Double(real) * 10.0, y: Double(imag) * 10.0)

        pskSampleIndex += samples
        if Double(pskSampleIndex) >= pskSamplesPerBit {
            pskSampleIndex = 0
            // In BPSK31, ~180 degree phase shift (|delta| > pi/2) represents bit 0.
            // Steady phase represents bit 1.
            let isBitZero = abs(normalizedDelta) > (.pi * 0.45)
            let bitChar: Character = isBitZero ? "0" : "1"
            pskBitAccumulator.append(bitChar)

            // Varicode characters are delimited by "00"
            if pskBitAccumulator.hasSuffix("00") {
                let code = String(pskBitAccumulator.dropLast(2))
                pskBitAccumulator = ""
                if let char = VaricodeCodec.varicodeToAscii[code] {
                    return (char, constPoint)
                }
            }
        }

        return (nil, constPoint)
    }

    // MARK: - Spectrum FFT & Quadrature DSP Helpers

    private func computeSpectrum(channelData: UnsafePointer<Float>, frameCount: Int) -> [Float] {
        let binCount = 128
        var spectrum = [Float](repeating: 0.0, count: binCount)
        let minF = 300.0
        let maxF = 3200.0
        let step = (maxF - minF) / Double(binCount)

        for b in 0..<binCount {
            let freq = minF + Double(b) * step
            let (r, i) = quadratureDetect(channelData: channelData, frameCount: frameCount, targetFreq: freq)
            let mag = sqrt(r * r + i * i)
            spectrum[b] = min(1.0, mag * 8.0)
        }
        return spectrum
    }

    private func quadratureDetect(channelData: UnsafePointer<Float>, frameCount: Int, targetFreq: Double) -> (Float, Float) {
        guard frameCount > 0, sampleRate > 0 else { return (0, 0) }
        let omega = 2.0 * .pi * targetFreq / sampleRate

        var sumReal: Float = 0.0
        var sumImag: Float = 0.0

        for n in 0..<frameCount {
            let sample = channelData[n]
            let angle = Float(omega * Double(n))
            sumReal += sample * cos(angle)
            sumImag -= sample * sin(angle)
        }

        let inv = 1.0 / Float(frameCount)
        return (sumReal * inv, sumImag * inv)
    }

    // MARK: - Decoded Stream & Callsign Highlighting

    public func appendDecodedText(_ text: String) {
        rxText += text
        // Keep terminal bounded to last 6,000 characters
        if rxText.count > 6000 {
            rxText = String(rxText.suffix(5000))
        }

        // Tokenize and highlight callsigns & signal reports
        var rawTokens: [String] = []
        for character in text {
            if character.isWhitespace {
                if !decodedWordOverflow, !pendingDecodedWord.isEmpty { rawTokens.append(pendingDecodedWord) }
                pendingDecodedWord = ""
                decodedWordOverflow = false
            } else if pendingDecodedWord.count < 64, !decodedWordOverflow {
                pendingDecodedWord.append(character)
            } else {
                pendingDecodedWord = ""
                decodedWordOverflow = true
            }
        }
        for tok in rawTokens {
            let clean = tok.trimmingCharacters(in: .punctuationCharacters).uppercased()
            guard !clean.isEmpty else { continue }

            let isCQ = clean == "CQ" || clean == "TEST"
            let isRpt = clean == "599" || clean == "579" || clean == "559"
            let isExch = clean.count >= 2 && clean.allSatisfy { $0.isNumber }
            let isCall = isHamCallsign(clean)

            let token = DigitalDecodedToken(
                text: clean,
                isCallsign: isCall,
                isReport: isRpt,
                isCQ: isCQ,
                isExchange: isExch
            )
            decodedTokens.append(token)
            if decodedTokens.count > 100 {
                decodedTokens.removeFirst(decodedTokens.count - 100)
            }

            // If a valid callsign was clicked or decoded, automatically suggest as target
            if isCall && targetCallsign.isEmpty && clean != myCallsign.uppercased() {
                selectTargetCallsign(clean)
            }
        }
    }

    public func selectTargetCallsign(_ call: String) {
        let clean = call.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }
        targetCallsign = clean

        // Resolve DXCC Info
        let info = DXCCDatabase.resolve(callsign: clean)
        targetCountryName = info.entityName
        targetCountryFlag = info.flagEmoji
        targetContinent = info.continent

        if !myGrid.isEmpty {
            // Find grid or default distance
            targetDistanceKm = 1200.0 // Default baseline or maidenhead lookup
        }
    }

    private func isHamCallsign(_ s: String) -> Bool {
        TransmitIdentity.isValidCallsign(s)
    }

    // MARK: - Macro Tag Expansion

    public func expandMacroTemplate(_ template: String) -> String {
        var text = template
        text = text.replacingOccurrences(of: "{MYCALL}", with: TransmitIdentity.usableCallsign(myCallsign) ?? "")
        text = text.replacingOccurrences(of: "{CALL}", with: targetCallsign.isEmpty ? "CQ" : targetCallsign.uppercased())
        text = text.replacingOccurrences(of: "{SENTRST}", with: targetReportSent)
        text = text.replacingOccurrences(of: "{RCVD_RST}", with: targetReportReceived)
        text = text.replacingOccurrences(of: "{MYGRID}", with: TransmitIdentity.locator(myGrid) ?? "")
        text = text.replacingOccurrences(of: "{SERIAL}", with: String(format: "%03d", targetSerial))
        text = text.replacingOccurrences(of: "{OP}", with: "HAM")
        return text
    }

    public func triggerMacro(_ macro: DigitalMacro) {
        let expanded = expandMacroTemplate(macro.template)
        queueTextForTransmission(expanded)
    }

    // MARK: - Transmission Engine (AFSK & PSK Audio Synthesis)

    public func queueTextForTransmission(_ text: String) {
        if let issue = TransmitIdentity.callsignRefusal(myCallsign) {
            txRefusal = issue
            return
        }
        // With Radio Control unable to key the radio, a macro is not added: pressing it again would queue it twice.
        if !isTransmitting, let issue = radioControlRefusal(textKept: false) {
            txRefusal = issue
            return
        }
        txRefusal = ""
        txBufferText += text
        txRemainingText = String(txBufferText.dropFirst(txSentCount))
        if !isTransmitting {
            startTransmission()
        }
    }

    /// Why a transmission cannot start because no radio can be keyed, or nil. Radio Control must be able to key its
    /// radio, or a TX-500 or X6100 must be connected from its own panel (they are keyed directly); otherwise the
    /// transmission would play with no PTT (or, with VOX, keyed and unseen). With Radio Control "Disabled" (VOX or an
    /// external PTT) nothing is checked.
    func radioControlRefusal(textKept: Bool) -> String? {
        if Lab599TX500Driver.shared.isConnected && Xiegu6100Driver.shared.isConnected,
           !RigControlEngine.shared.isConnected || RigControlEngine.shared.driverType == .disabled {
            return "\(operatingMode.rawValue): nothing sent at \(TXLimits.utc()). Two direct radio panels are connected; select one connected radio in Radio Control before sending. Receiving and logging remain available."
        }
        let rig = RigControlEngine.shared
        guard rig.driverType != .disabled, !rig.isConnected,
              !Lab599TX500Driver.shared.isConnected, !Xiegu6100Driver.shared.isConnected else { return nil }
        return "\(operatingMode.rawValue): nothing sent. Radio Control is set to \(rig.driverType.rawValue), which is not "
            + "connected, so YAAM could not key the radio. Connect it in Radio Control, or set Radio Control to Disabled "
            + "to transmit with VOX or an external PTT. Receiving and logging remain available. At \(TXLimits.utc()). " + (textKept ? "The text in the TX box is kept." : "The text was not added.")
    }

    public func startTransmission() {
        guard !TransmitShutdown.isShuttingDown else { return }
        guard !isTransmitting else { return }
        // What is still to send: the part of the box not sent yet, typed or from a macro.
        txRemainingText = String(txBufferText.dropFirst(txSentCount))
        guard !txRemainingText.isEmpty else {
            if !txBufferText.isEmpty {
                txRefusal = "\(operatingMode.rawValue): nothing new to send. Everything in the TX box has been processed (or "
                    + "dropped with ABORT TX). Type new text, or use Clear TX to start again."
            }
            return
        }
        if let issue = TransmitIdentity.callsignRefusal(myCallsign) {
            txRefusal = issue
            return
        }
        if let issue = radioControlRefusal(textKept: true) {
            txRefusal = issue
            return
        }
        if audioEngine?.isRunning == true { playerNode?.play() }
        guard audioEngine?.isRunning == true, playerNode?.isPlaying == true else {
            txRefusal = "Audio transmitter is unavailable. No message was sent; the queued text is kept."
            return
        }
        txRefusal = "" // a refusal from an earlier attempt no longer applies
        isTransmitting = true
        acquireTransmitPTT()

        txTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let nextChar: Character? = await MainActor.run { self.nextCharacterToSend() }

                guard let char = nextChar else { break }

                // Synthesize character audio tones and play via playerNode
                await self.synthesizeAndPlay(character: char)
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isTransmitting = false
                self.txProgress = 1.0
                self.releaseTransmitPTT?()
                self.releaseTransmitPTT = nil
            }
        }
    }

    /// Acquires at most one transport. A second connected panel must not key an unrelated radio.
    func acquireTransmitPTT() {
        guard !TransmitShutdown.isShuttingDown, radioControlRefusal(textKept: true) == nil else { return }
        // One chosen route only. A second connected panel must never key an unrelated radio.
        let rig = RigControlEngine.shared
        if rig.driverType != .disabled, rig.isConnected {
            rig.setPTT(true)
            releaseTransmitPTT = rig.capturePTTRelease()
        } else if Lab599TX500Driver.shared.isConnected {
            let radio = Lab599TX500Driver.shared
            radio.setPTT(true)
            releaseTransmitPTT = { radio.setPTT(false) }
        } else if Xiegu6100Driver.shared.isConnected {
            let radio = Xiegu6100Driver.shared
            radio.setPTT(true)
            releaseTransmitPTT = { radio.setPTT(false) }
        }
    }

    /// The next character of the box not sent yet (text typed while transmitting included), marked as sent; nil when
    /// there is none or the transmission has stopped.
    func nextCharacterToSend() -> Character? {
        guard !Task.isCancelled, isTransmitting else { return nil }
        let pending = txBufferText.dropFirst(txSentCount)
        guard let char = pending.first else {
            txRemainingText = ""
            return nil
        }
        txSentCount += 1
        txRemainingText = String(pending.dropFirst())
        txTransmittedText.append(char)
        txProgress = Double(txSentCount) / Double(max(1, txBufferText.count))
        return char
    }

    public func stopTransmission() {
        let wasTransmitting = isTransmitting
        txTask?.cancel()
        txTask = nil
        isTransmitting = false
        releaseTransmitPTT?()
        releaseTransmitPTT = nil
        playerNode?.stop()
        // ABORT TX drops what was still to send: it is not sent by a later TRANSMIT. Stopping when nothing was being
        // transmitted (for example when the receiver stops) keeps the text still to send.
        if wasTransmitting { txSentCount = txBufferText.count }
        txRemainingText = ""
    }

    private func synthesizeAndPlay(character: Character) async {
        let mode = operatingMode
        let markF = effectiveMarkFrequency
        let spaceF = effectiveSpaceFrequency
        let sRate = sampleRate

        if mode.isRTTY {
            var state = baudotState
            let baudotCodes = BaudotCodec.encode(char: character, currentState: &state)
            self.baudotState = state

            for code in baudotCodes {
                // Sequence of bits: Start (0), Data0..Data4, Stop (1, 1.5 duration)
                var bits: [(isMark: Bool, durationSec: Double)] = []
                bits.append((isMark: false, durationSec: 1.0 / mode.baudRate)) // Start bit
                for i in 0..<5 {
                    let bitIsMark = (code & (1 << i)) != 0
                    bits.append((isMark: bitIsMark, durationSec: 1.0 / mode.baudRate))
                }
                bits.append((isMark: true, durationSec: 1.5 / mode.baudRate)) // 1.5 Stop bits

                for bit in bits {
                    let freq = bit.isMark ? markF : spaceF
                    let frameCount = Int(bit.durationSec * sRate)
                    await playSineTone(frequency: freq, frameCount: frameCount)
                }
            }
        } else {
            // PSK31 Varicode transmission
            let bitPattern = VaricodeCodec.encode(char: character)
            let bitDuration = 1.0 / mode.baudRate
            for bit in bitPattern {
                let frameCount = Int(bitDuration * sRate)
                let phaseShift = bit == "0" ? .pi : 0.0
                await playPSKTone(centerFreq: markF, phaseShift: phaseShift, frameCount: frameCount)
            }
        }
    }

    private func playSineTone(frequency: Double, frameCount: Int) async {
        guard !Task.isCancelled, isTransmitting, frameCount > 0 else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        if let channel = buffer.floatChannelData?[0] {
            let omega = 2.0 * .pi * frequency / sampleRate
            for i in 0..<frameCount {
                // Raised-cosine edge shaping to eliminate key-clicks
                var envelope: Float = 1.0
                let edge = min(64, frameCount / 4)
                if i < edge {
                    envelope = 0.5 * (1.0 - cos(Float(i) * .pi / Float(edge)))
                } else if i > frameCount - edge {
                    envelope = 0.5 * (1.0 - cos(Float(frameCount - i) * .pi / Float(edge)))
                }
                channel[i] = sin(Float(omega * Double(i))) * envelope * 0.70
            }
        }

        if !Task.isCancelled, isTransmitting, let player = self.playerNode, player.isPlaying {
            await player.scheduleBuffer(buffer)
        }
    }

    private func playPSKTone(centerFreq: Double, phaseShift: Double, frameCount: Int) async {
        guard !Task.isCancelled, isTransmitting, frameCount > 0 else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        if let channel = buffer.floatChannelData?[0] {
            let omega = 2.0 * .pi * centerFreq / sampleRate
            for i in 0..<frameCount {
                // Classic PSK31 raised cosine pulse shape
                let envelope = Float(cos(Double(i) * .pi / Double(frameCount) - (.pi * 0.5)))
                channel[i] = sin(Float(omega * Double(i) + phaseShift)) * abs(envelope) * 0.70
            }
        }

        if !Task.isCancelled, isTransmitting, let player = self.playerNode, player.isPlaying {
            await player.scheduleBuffer(buffer)
        }
    }

    // MARK: - Simulation & On-Air Practice Feed

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

        let simulatedPhrases = [
            "CQ CQ CQ DE DL1ABC DL1ABC TEST K",
            "K3LR UR 599 001 001 BK",
            "TU 73 DE DL1ABC QRZ?",
            "CQ TEST JA7YRR JA7YRR K",
            "W3LPL 599 042 042 DE JA7YRR K",
            "73 GL DE K3LR SK",
            "CQ CQ DE EP2NBC EP2NBC K",
            "UR 599 003 003 TU 73"
        ]

        simulationPhraseIndex = 0
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let phrase = simulatedPhrases[self.simulationPhraseIndex % simulatedPhrases.count]
                self.simulationPhraseIndex += 1

                // Inject simulated characters into stream
                for ch in phrase {
                    self.appendDecodedText(String(ch))
                }
                self.appendDecodedText("\r\n")

                // Synthesize realistic Lissajous crossed-ellipses coordinates
                var simScope: [DigitalScopeSample] = []
                for i in 0..<32 {
                    let t = Double(i) * 0.2
                    // Mark produces vertical ellipse with slight phase wobble
                    let my = Float(sin(t)) * 0.85
                    // Space produces horizontal ellipse
                    let sx = Float(cos(t * 1.05)) * 0.82
                    simScope.append(DigitalScopeSample(x: sx, y: my))
                }

                self.scopeSamples = simScope
                self.markLevel = 0.78
                self.spaceLevel = 0.75
                self.signalToNoiseRatioDb = 24.5
                self.audioInputLevel = 0.72

                // Fake waterfall spectrum around center frequency
                var simSpec = [Float](repeating: 0.05, count: 128)
                let centerBin = Int((self.centerFrequencyHz - 300.0) / (3200.0 - 300.0) * 128.0)
                if centerBin >= 5 && centerBin < 123 {
                    simSpec[centerBin - 3] = 0.90 // Mark
                    simSpec[centerBin + 3] = 0.88 // Space
                }
                self.waterfallSpectrum = simSpec
            }
        }
    }

    public func stopSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        isSimulationActive = false
    }

    // MARK: - 1-Click QSO Logging

    public func logCurrentQSO() {
        guard !targetCallsign.isEmpty else { return }
        let call = targetCallsign
        let mode = operatingMode.adifMode
        let rstSent = targetReportSent
        let rstRcvd = targetReportReceived
        let freqHz: UInt64 = 14_080_000 // Standard 20m digital frequency or from rig
        let band = "20m"

        logQSOHandler?(call, mode, rstSent, rstRcvd, freqHz, band)

        // Increment serial and clear target
        targetSerial += 1
        targetCallsign = ""
        targetCountryName = ""
        targetCountryFlag = "🌐"
    }
}
