//
//  HellschreiberEngine.swift
//  YAAM
//
//  Real-Time DSP Hellschreiber (Feld Hell) Modem & Facsimile Engine
//  Features 14x7 pixel font rasterization, 122.5 baud / 245 pixels/sec tone generation,
//  dual-line ticker tape buffer, slant correction, and vintage mechanical simulation.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

// MARK: - Hellschreiber Font Matrix (14 rows x 7 columns)

public struct HellFont: Sendable {
    // Each character is represented by 7 columns, each column has 14 pixels (14-bit integer, bit 0 is top, bit 13 is bottom)
    // Common ASCII 32..90 characters
    public static let glyphs: [Character: [UInt16]] = [
        " ": [0, 0, 0, 0, 0, 0, 0],
        "A": [0x0FE0, 0x1818, 0x1008, 0x1818, 0x0FE0, 0x0180, 0x0000],
        "B": [0x1FFE, 0x1082, 0x1082, 0x1082, 0x0F7C, 0x0000, 0x0000],
        "C": [0x07F0, 0x180C, 0x1002, 0x1002, 0x1804, 0x0000, 0x0000],
        "D": [0x1FFE, 0x1002, 0x1002, 0x180C, 0x07F0, 0x0000, 0x0000],
        "E": [0x1FFE, 0x1082, 0x1082, 0x1082, 0x1002, 0x0000, 0x0000],
        "F": [0x1FFE, 0x1080, 0x1080, 0x1080, 0x1000, 0x0000, 0x0000],
        "G": [0x07F0, 0x180C, 0x1002, 0x1042, 0x1E46, 0x0000, 0x0000],
        "H": [0x1FFE, 0x0080, 0x0080, 0x0080, 0x1FFE, 0x0000, 0x0000],
        "I": [0x1002, 0x1002, 0x1FFE, 0x1002, 0x1002, 0x0000, 0x0000],
        "J": [0x000C, 0x0002, 0x1002, 0x1002, 0x0FFE, 0x0000, 0x0000],
        "K": [0x1FFE, 0x0180, 0x0660, 0x1818, 0x1006, 0x0000, 0x0000],
        "L": [0x1FFE, 0x0002, 0x0002, 0x0002, 0x0002, 0x0000, 0x0000],
        "M": [0x1FFE, 0x0800, 0x0600, 0x0800, 0x1FFE, 0x0000, 0x0000],
        "N": [0x1FFE, 0x0600, 0x0180, 0x0060, 0x1FFE, 0x0000, 0x0000],
        "O": [0x07F0, 0x180C, 0x1002, 0x180C, 0x07F0, 0x0000, 0x0000],
        "P": [0x1FFE, 0x1080, 0x1080, 0x1080, 0x0F00, 0x0000, 0x0000],
        "Q": [0x07F0, 0x180C, 0x1012, 0x180E, 0x07F3, 0x0001, 0x0000],
        "R": [0x1FFE, 0x1080, 0x10E0, 0x1098, 0x0F06, 0x0000, 0x0000],
        "S": [0x0E04, 0x1102, 0x1082, 0x1042, 0x083C, 0x0000, 0x0000],
        "T": [0x1000, 0x1000, 0x1FFE, 0x1000, 0x1000, 0x0000, 0x0000],
        "U": [0x1FF8, 0x0006, 0x0002, 0x0006, 0x1FF8, 0x0000, 0x0000],
        "V": [0x1F80, 0x0078, 0x0006, 0x0078, 0x1F80, 0x0000, 0x0000],
        "W": [0x1FF0, 0x000E, 0x03E0, 0x000E, 0x1FF0, 0x0000, 0x0000],
        "X": [0x1806, 0x0660, 0x0180, 0x0660, 0x1806, 0x0000, 0x0000],
        "Y": [0x1C00, 0x0380, 0x007E, 0x0380, 0x1C00, 0x0000, 0x0000],
        "Z": [0x100E, 0x1072, 0x1182, 0x1602, 0x1802, 0x0000, 0x0000],
        "0": [0x07F0, 0x181C, 0x1062, 0x18C4, 0x07F0, 0x0000, 0x0000],
        "1": [0x0400, 0x0800, 0x1FFE, 0x0002, 0x0002, 0x0000, 0x0000],
        "2": [0x0C06, 0x1012, 0x1062, 0x1182, 0x0E02, 0x0000, 0x0000],
        "3": [0x0C04, 0x1082, 0x1082, 0x1142, 0x0E3C, 0x0000, 0x0000],
        "4": [0x0070, 0x0190, 0x0610, 0x1FFE, 0x0010, 0x0000, 0x0000],
        "5": [0x1E04, 0x1282, 0x1282, 0x1242, 0x103C, 0x0000, 0x0000],
        "6": [0x07F0, 0x128C, 0x1282, 0x1242, 0x103C, 0x0000, 0x0000],
        "7": [0x1800, 0x1000, 0x10F0, 0x1300, 0x1C00, 0x0000, 0x0000],
        "8": [0x0DB8, 0x1244, 0x1242, 0x1244, 0x0DB8, 0x0000, 0x0000],
        "9": [0x0F80, 0x1090, 0x1092, 0x1892, 0x07FE, 0x0000, 0x0000],
        "/": [0x0006, 0x0038, 0x01C0, 0x0E00, 0x1000, 0x0000, 0x0000],
        "?": [0x0C00, 0x1000, 0x116E, 0x1200, 0x0C00, 0x0000, 0x0000],
        ".": [0x0003, 0x0003, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000],
        "-": [0x0080, 0x0080, 0x0080, 0x0080, 0x0080, 0x0000, 0x0000],
        ",": [0x0001, 0x0006, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000]
    ]

    public static func getColumns(for character: Character) -> [UInt16] {
        let upper = Character(character.uppercased())
        return glyphs[upper] ?? glyphs[" "]!
    }
}

// MARK: - Hell Column Model for Ticker Tape

public struct HellColumn: Identifiable, Sendable {
    public let id = UUID()
    public let pixels: [Float] // 14 pixels top to bottom (0.0 to 1.0)
    public let timestamp: Date

    public init(pixels: [Float], timestamp: Date = Date()) {
        self.pixels = pixels
        self.timestamp = timestamp
    }
}

// MARK: - Hellschreiber Engine

@MainActor
public final class HellschreiberEngine: ObservableObject {
    public static let shared = HellschreiberEngine()

    // Operating Controls
    @Published public var isListening: Bool = false
    @Published public var isTransmitting: Bool = false
    @Published public var isSimulationActive: Bool = false
    @Published public var centerFrequencyHz: Double = 980.0
    @Published public var slantCorrectionPct: Double = 0.0 // -5.0% to +5.0%
    @Published public var tapeContrast: Float = 1.6
    @Published public var squelchLevel: Float = 0.06

    // Ticker Tape Buffer (Holds the last 240 rendered columns)
    @Published public var columns: [HellColumn] = []
    @Published public var txBufferText: String = ""
    @Published public var txTransmittedText: String = ""
    @Published public var txProgress: Double = 0.0

    // Live Metrics
    @Published public var audioInputLevel: Float = 0.0
    @Published public var signalStrengthDb: Double = 0.0

    // Station Settings
    /// The operator's saved callsign as entered; empty when none is set. The transmit buttons refuse while it is
    /// empty or not accepted.
    public var myCallsign: String { TransmitIdentity.savedEnteredCallsign() }
    /// Why the last transmission was refused (no callsign of the operator, or one that is not accepted); empty
    /// otherwise. The screen clears it when the active station profile changes.
    @Published public var txRefusal: String = ""
    @Published public var targetCallsign: String = ""

    // Logging Callback
    public var logQSOHandler: ((_ call: String, _ mode: String, _ rstSent: String, _ rstRcvd: String, _ freqHz: UInt64, _ band: String) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var sampleRate: Double = 48000.0

    // DSP pixel timing
    // Feld Hell standard: 122.5 baud (symbol rate). Each column has 14 pixels.
    // Pixel rate = 122.5 * (14 / 7) = 245 pixels/sec. Pixel duration = 1.0 / 245 = 4.0816 ms.
    private var samplesPerPixel: Double = 48000.0 / 245.0
    private var pixelAccumulator: Float = 0.0
    private var pixelSampleCount: Int = 0
    private var currentColumnPixels: [Float] = []

    private var txTask: Task<Void, Never>?
    private var simTimer: Timer?
    private var simPhraseIdx = 0
    private var simCharIdx = 0

    public init() {
        self.samplesPerPixel = 48000.0 / 245.0
    }

    // MARK: - Audio Start / Stop

    public func startListening() {
        guard !isListening else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        self.sampleRate = format.sampleRate
        self.updatePixelTiming()

        let player = AVAudioPlayerNode()
        engine.attach(player)
        let mixer = engine.mainMixerNode
        engine.connect(player, to: mixer, format: mixer.outputFormat(forBus: 0))
        self.playerNode = player

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            self.audioEngine = engine
            self.isListening = true
        } catch {
            print("HellschreiberEngine start error: \(error)")
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
    }

    public func clearTape() {
        columns.removeAll()
        txBufferText = ""
        txTransmittedText = ""
        txProgress = 0.0
    }

    private func updatePixelTiming() {
        let baseRate = 245.0 * (1.0 + (slantCorrectionPct / 100.0))
        self.samplesPerPixel = sampleRate / baseRate
    }

    public func setSlant(_ pct: Double) {
        slantCorrectionPct = max(-5.0, min(5.0, pct))
        updatePixelTiming()
    }

    // MARK: - DSP Audio Demodulator

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let totalFrames = Int(buffer.frameLength)
        guard totalFrames > 0 else { return }

        // Peak Level
        var peak: Float = 0.0
        for i in stride(from: 0, to: totalFrames, by: 16) {
            let v = abs(channelData[i])
            if v > peak { peak = v }
        }

        let targetFreq = centerFrequencyHz
        let omega = 2.0 * .pi * targetFreq / sampleRate

        var newCols: [HellColumn] = []

        // Slicing into small 32-sample chunks for envelope detection
        let sub = 32
        let subCount = totalFrames / sub

        for s in 0..<subCount {
            let offset = s * sub
            var sumReal: Float = 0.0
            var sumImag: Float = 0.0

            for i in 0..<sub {
                let sample = channelData[offset + i]
                let angle = Float(omega * Double(offset + i))
                sumReal += sample * cos(angle)
                sumImag -= sample * sin(angle)
            }

            let env = sqrt(sumReal * sumReal + sumImag * sumImag) / Float(sub)
            let normalized = min(1.0, env * tapeContrast * 6.0)

            pixelAccumulator += normalized * Float(sub)
            pixelSampleCount += sub

            if Double(pixelSampleCount) >= samplesPerPixel {
                let pixelVal = pixelAccumulator / Float(pixelSampleCount)
                pixelAccumulator = 0.0
                pixelSampleCount = 0

                let finalPixel = pixelVal > squelchLevel ? pixelVal : 0.0
                currentColumnPixels.append(finalPixel)

                if currentColumnPixels.count >= 14 {
                    // One full column of 14 pixels completed!
                    newCols.append(HellColumn(pixels: currentColumnPixels))
                    currentColumnPixels.removeAll()
                }
            }
        }

        let currentPeak = peak
        let sigDb = 20.0 * log10(max(0.001, Double(currentPeak)))

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioInputLevel = currentPeak
            self.signalStrengthDb = max(0.0, sigDb + 60.0)

            if !newCols.isEmpty {
                self.columns.append(contentsOf: newCols)
                if self.columns.count > 320 {
                    self.columns.removeFirst(self.columns.count - 320)
                }
            }
        }
    }

    // MARK: - Hellschreiber Audio Transmitter

    public func queueTextForTransmission(_ text: String) {
        if let issue = TransmitIdentity.callsignRefusal(myCallsign) {
            txRefusal = issue
            return
        }
        txRefusal = ""
        txBufferText += text
        if !isTransmitting {
            startTransmission()
        }
    }

    public func startTransmission() {
        guard !txBufferText.isEmpty, !isTransmitting else { return }
        if let issue = TransmitIdentity.callsignRefusal(myCallsign) {
            txRefusal = issue
            return
        }
        isTransmitting = true

        txTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            while true {
                let nextChar: Character? = await MainActor.run {
                    guard self.isTransmitting, !self.txBufferText.isEmpty else { return nil }
                    let ch = self.txBufferText.removeFirst()
                    self.txTransmittedText.append(ch)
                    return ch
                }

                guard let ch = nextChar else { break }
                await self.synthesizeAndPlayHellChar(ch)
            }

            await MainActor.run {
                self.isTransmitting = false
                self.txProgress = 1.0
            }
        }
    }

    public func stopTransmission() {
        txTask?.cancel()
        txTask = nil
        isTransmitting = false
        playerNode?.stop()
    }

    private func synthesizeAndPlayHellChar(_ char: Character) async {
        let cols = HellFont.getColumns(for: char)
        let sRate = sampleRate
        let freq = centerFrequencyHz
        let pixDuration = 1.0 / 245.0
        let framesPerPixel = Int(pixDuration * sRate)

        for colMask in cols {
            for row in 0..<14 {
                let isPixelOn = (colMask & (1 << row)) != 0
                if isPixelOn {
                    await playTone(frequency: freq, frameCount: framesPerPixel)
                } else {
                    await playSilence(frameCount: framesPerPixel)
                }
            }
        }

        // Inter-character space column (all silent)
        await playSilence(frameCount: framesPerPixel * 14)
    }

    private func playTone(frequency: Double, frameCount: Int) async {
        guard frameCount > 0 else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        if let channel = buffer.floatChannelData?[0] {
            let omega = 2.0 * .pi * frequency / sampleRate
            for i in 0..<frameCount {
                // Raised-cosine edge shaping to prevent clicks
                var env: Float = 1.0
                let edge = min(32, frameCount / 4)
                if i < edge {
                    env = 0.5 * (1.0 - cos(Float(i) * .pi / Float(edge)))
                } else if i > frameCount - edge {
                    env = 0.5 * (1.0 - cos(Float(frameCount - i) * .pi / Float(edge)))
                }
                channel[i] = sin(Float(omega * Double(i))) * env * 0.70
            }
        }

        if let player = self.playerNode, player.isPlaying {
            await player.scheduleBuffer(buffer)
        }
    }

    private func playSilence(frameCount: Int) async {
        guard frameCount > 0 else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        if let channel = buffer.floatChannelData?[0] {
            for i in 0..<frameCount { channel[i] = 0.0 }
        }

        if let player = self.playerNode, player.isPlaying {
            await player.scheduleBuffer(buffer)
        }
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
        guard !isSimulationActive else { return }
        isSimulationActive = true

        let simPhrases = [
            "CQ CQ DE DL1XYZ FELD HELL K ",
            "W1AW 599 001 BK ",
            "73 DE DL1XYZ SK "
        ]

        simPhraseIdx = 0
        simCharIdx = 0

        simTimer = Timer.scheduledTimer(withTimeInterval: 0.065, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let phrase = Array(simPhrases[self.simPhraseIdx % simPhrases.count])
                guard !phrase.isEmpty else { return }
                let ch = phrase[self.simCharIdx % phrase.count]
                self.simCharIdx += 1
                if self.simCharIdx >= phrase.count {
                    self.simCharIdx = 0
                    self.simPhraseIdx += 1
                }

                let fontCols = HellFont.getColumns(for: ch)
                var batchCols: [HellColumn] = []
                for mask in fontCols {
                    var pix: [Float] = []
                    for row in 0..<14 {
                        let on = (mask & (1 << row)) != 0
                        // Add realistic ink smudge & noise
                        let noise = Float.random(in: 0.02...0.10)
                        let v = on ? Float.random(in: 0.85...1.0) : noise
                        pix.append(v)
                    }
                    batchCols.append(HellColumn(pixels: pix))
                }
                // Inter-glyph space
                batchCols.append(HellColumn(pixels: Array(repeating: 0.03, count: 14)))

                self.columns.append(contentsOf: batchCols)
                if self.columns.count > 320 {
                    self.columns.removeFirst(self.columns.count - 320)
                }
                self.audioInputLevel = 0.65
            }
        }
    }

    public func stopSimulation() {
        simTimer?.invalidate()
        simTimer = nil
        isSimulationActive = false
    }

    // MARK: - 1-Click Logging

    public func logCurrentQSO() {
        guard !targetCallsign.isEmpty else { return }
        logQSOHandler?(targetCallsign, "HELL", "599", "599", 14_063_000, "20m")
        targetCallsign = ""
    }
}
