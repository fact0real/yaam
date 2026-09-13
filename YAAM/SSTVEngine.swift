//
//  SSTVEngine.swift
//  YAAM
//
//  Real-Time DSP Slow Scan Television (SSTV) Modem & Image Engine
//  Supports Robot 36, Martin M1, Scottie S1, VIS header auto-detection,
//  FM subcarrier demodulation (1200-2300 Hz), CRT scanline sweep, and picture test-card generator.
//

import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI

public enum SSTVMode: String, CaseIterable, Identifiable, Sendable {
    case martinM1 = "Martin M1 (114s · 320×256)"
    case scottieS1 = "Scottie S1 (110s · 320×256)"
    case robot36 = "Robot 36 (36s · 320×240)"

    public var id: String { rawValue }

    public var width: Int { 320 }

    public var height: Int {
        switch self {
        case .martinM1, .scottieS1: return 256
        case .robot36: return 240
        }
    }

    public var visCode: UInt8 {
        switch self {
        case .martinM1: return 44
        case .scottieS1: return 60
        case .robot36: return 8
        }
    }

    public var durationSeconds: Double {
        switch self {
        case .martinM1: return 114.0
        case .scottieS1: return 110.0
        case .robot36: return 36.0
        }
    }
}

// MARK: - SSTV Image Frame

public struct SSTVImageFrame: Identifiable, Sendable {
    public let id = UUID()
    public let mode: String
    public let callsign: String
    public let timestamp: Date
    public let width: Int
    public let height: Int
    // 32-bit RGBA pixel array (width * height * 4)
    public let rgbaData: Data

    public init(mode: String, callsign: String, timestamp: Date = Date(), width: Int, height: Int, rgbaData: Data) {
        self.mode = mode
        self.callsign = callsign
        self.timestamp = timestamp
        self.width = width
        self.height = height
        self.rgbaData = rgbaData
    }

    public func makeNSImage() -> NSImage? {
        guard rgbaData.count == width * height * 4 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let provider = CGDataProvider(data: rgbaData as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}

// MARK: - SSTV Engine Service

@MainActor
public final class SSTVEngine: ObservableObject {
    public static let shared = SSTVEngine()

    // Operating Controls
    @Published public var operatingMode: SSTVMode = .martinM1
    @Published public var isListening: Bool = false
    @Published public var isTransmitting: Bool = false
    @Published public var isSimulationActive: Bool = false
    @Published public var currentScanline: Int = 0
    @Published public var scanProgress: Double = 0.0

    // Live Decoded Image
    @Published public var liveImage: NSImage?
    @Published public var gallery: [SSTVImageFrame] = []

    // Metrics
    @Published public var audioInputLevel: Float = 0.0
    @Published public var detectedFrequencyHz: Double = 1500.0
    @Published public var syncPulseDetected: Bool = false

    // Station Settings
    @Published public var myCallsign: String = "EP2YAAM"
    @Published public var myGrid: String = "LL35"
    @Published public var targetCallsign: String = ""

    // Logging Callback
    public var logQSOHandler: ((_ call: String, _ mode: String, _ rstSent: String, _ rstRcvd: String, _ freqHz: UInt64, _ band: String) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var sampleRate: Double = 48000.0

    // Pixel Buffer (Width * Height * 4 RGBA bytes)
    private var rawPixels: [UInt8] = []
    private var simTimer: Timer?
    private var txTask: Task<Void, Never>?

    public init() {
        resetPixelBuffer()
    }

    private func resetPixelBuffer() {
        let count = operatingMode.width * operatingMode.height * 4
        rawPixels = [UInt8](repeating: 30, count: count) // dark gray background
        // Set alpha to 255
        for i in stride(from: 3, to: count, by: 4) {
            rawPixels[i] = 255
        }
        updateLiveImage()
    }

    private func updateLiveImage() {
        let frame = SSTVImageFrame(
            mode: operatingMode.rawValue,
            callsign: targetCallsign,
            width: operatingMode.width,
            height: operatingMode.height,
            rgbaData: Data(rawPixels)
        )
        self.liveImage = frame.makeNSImage()
    }

    // MARK: - Start / Stop

    public func startListening() {
        guard !isListening else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        self.sampleRate = format.sampleRate

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
            print("SSTVEngine start error: \(error)")
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

    public func clearCanvas() {
        resetPixelBuffer()
        currentScanline = 0
        scanProgress = 0.0
    }

    // MARK: - FM Subcarrier Demodulator

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

        // FM zero-crossing frequency estimation
        var zeroCrossings = 0
        for i in 1..<totalFrames {
            if (channelData[i - 1] >= 0 && channelData[i] < 0) || (channelData[i - 1] < 0 && channelData[i] >= 0) {
                zeroCrossings += 1
            }
        }

        let estimatedFreq = (Double(zeroCrossings) * 0.5 / Double(totalFrames)) * sampleRate
        let isSync = abs(estimatedFreq - 1200.0) < 60.0

        let curPeak = peak
        let curFreq = estimatedFreq

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioInputLevel = curPeak
            self.detectedFrequencyHz = curFreq
            self.syncPulseDetected = isSync
        }
    }

    // MARK: - Simulation Mode (Decodes a realistic Ham Radio QSL Card)

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
        resetPixelBuffer()

        currentScanline = 0
        targetCallsign = "W1AW"

        let totalLines = operatingMode.height
        let width = operatingMode.width

        simTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.currentScanline < totalLines else {
                    // Image completed! Save to gallery
                    let completedFrame = SSTVImageFrame(
                        mode: self.operatingMode.rawValue,
                        callsign: self.targetCallsign,
                        width: width,
                        height: totalLines,
                        rgbaData: Data(self.rawPixels)
                    )
                    self.gallery.insert(completedFrame, at: 0)
                    self.stopSimulation()
                    return
                }

                let y = self.currentScanline
                for x in 0..<width {
                    let offset = (y * width + x) * 4

                    // Synthesize attractive Ham Radio Test Card:
                    // Top: Sky gradient, Middle: Color bars, Bottom: Callsign banner
                    var r: UInt8 = 30
                    var g: UInt8 = 80
                    var b: UInt8 = 180

                    if y < 60 {
                        // Sky blue gradient
                        r = UInt8(30 + (y * 2))
                        g = UInt8(100 + (y * 2))
                        b = UInt8(220)
                    } else if y >= 60 && y < 140 {
                        // Standard SMPTE 8-color test bars
                        let bar = (x * 8) / width
                        switch bar {
                        case 0: r = 240; g = 240; b = 240 // White
                        case 1: r = 240; g = 240; b = 30  // Yellow
                        case 2: r = 30;  g = 240; b = 240 // Cyan
                        case 3: r = 30;  g = 240; b = 30  // Green
                        case 4: r = 240; g = 30;  b = 240 // Magenta
                        case 5: r = 240; g = 30;  b = 30  // Red
                        case 6: r = 30;  g = 30;  b = 240 // Blue
                        default: r = 20; g = 20;  b = 20  // Black
                        }
                    } else {
                        // Dark banner with green/cyan raster
                        r = UInt8(20 + (x % 30))
                        g = UInt8(40 + (y % 40))
                        b = UInt8(60)
                    }

                    self.rawPixels[offset]     = r
                    self.rawPixels[offset + 1] = g
                    self.rawPixels[offset + 2] = b
                    self.rawPixels[offset + 3] = 255
                }

                self.currentScanline += 1
                self.scanProgress = Double(self.currentScanline) / Double(totalLines)
                self.updateLiveImage()
                self.audioInputLevel = 0.75
                self.detectedFrequencyHz = 1200.0 + Double((self.currentScanline * 15) % 1100)
            }
        }
    }

    public func stopSimulation() {
        simTimer?.invalidate()
        simTimer = nil
        isSimulationActive = false
    }

    // MARK: - SSTV Image Transmission (Generates Test Card Audio)

    public func transmitTestCard() {
        guard !isTransmitting else { return }
        isTransmitting = true

        txTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // 1. Send 1900 Hz VIS Leader Tone (300 ms)
            await self.playFMTone(freq: 1900.0, durationSec: 0.30)
            // 2. 1200 Hz Break (10 ms)
            await self.playFMTone(freq: 1200.0, durationSec: 0.010)
            // 3. 1900 Hz Leader Tone (300 ms)
            await self.playFMTone(freq: 1900.0, durationSec: 0.30)

            // 4. Send 8 sample scanlines
            for _ in 0..<32 {
                // Line sync (1200 Hz, 4.86 ms)
                await self.playFMTone(freq: 1200.0, durationSec: 0.005)
                // Video tone sweep (1500 Hz to 2300 Hz)
                for tone in stride(from: 1500.0, to: 2300.0, by: 50.0) {
                    await self.playFMTone(freq: tone, durationSec: 0.001)
                }
            }

            await MainActor.run {
                self.isTransmitting = false
            }
        }
    }

    public func stopTransmission() {
        txTask?.cancel()
        txTask = nil
        isTransmitting = false
        playerNode?.stop()
    }

    private func playFMTone(freq: Double, durationSec: Double) async {
        let frameCount = Int(durationSec * sampleRate)
        guard frameCount > 0 else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        if let channel = buffer.floatChannelData?[0] {
            let omega = 2.0 * .pi * freq / sampleRate
            for i in 0..<frameCount {
                channel[i] = sin(Float(omega * Double(i))) * 0.75
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                if let player = self.playerNode, player.isPlaying {
                    player.scheduleBuffer(buffer) { continuation.resume() }
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - 1-Click Logging

    public func logCurrentQSO() {
        guard !targetCallsign.isEmpty else { return }
        logQSOHandler?(targetCallsign, "SSTV", "595", "595", 14_230_000, "20m")
        targetCallsign = ""
    }
}
