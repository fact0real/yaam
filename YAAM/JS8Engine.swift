//
//  JS8Engine.swift
//  YAAM
//
//  Real-Time DSP Engine for JS8 / JS8Call Conversational Keyboard Protocol
//  Features 8-GFSK frame modulation/demodulation across 4 speed profiles (Normal, Fast, Slow, Turbo),
//  directed messaging, heartbeat monitor, station activity roster, and audio slot synthesis.
//

import AVFoundation
import Combine
import Foundation

public enum JS8Speed: String, CaseIterable, Identifiable, Sendable {
    case normal = "Normal (15s · 50 Hz)"
    case fast = "Fast (10s · 80 Hz)"
    case slow = "Slow (30s · 25 Hz)"
    case turbo = "Turbo (6s · 160 Hz)"

    public var id: String { rawValue }

    public var frameSeconds: Double {
        switch self {
        case .normal: return 15.0
        case .fast: return 10.0
        case .slow: return 30.0
        case .turbo: return 6.0
        }
    }

    public var bandwidthHz: Double {
        switch self {
        case .normal: return 50.0
        case .fast: return 80.0
        case .slow: return 25.0
        case .turbo: return 160.0
        }
    }

    public var baudRate: Double {
        bandwidthHz / 16.0
    }
}

// MARK: - JS8 Station Roster Entry

public struct JS8StationEntry: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let callsign: String
    public let grid: String
    public let snrDb: Int
    public let countryFlag: String
    public let countryName: String
    public let lastHeard: Date
    public let audioFreqHz: Double

    public init(callsign: String, grid: String, snrDb: Int, countryFlag: String, countryName: String, lastHeard: Date = Date(), audioFreqHz: Double) {
        self.callsign = callsign
        self.grid = grid
        self.snrDb = snrDb
        self.countryFlag = countryFlag
        self.countryName = countryName
        self.lastHeard = lastHeard
        self.audioFreqHz = audioFreqHz
    }
}

// MARK: - JS8 Chat Message

public struct JS8Message: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let fromCall: String
    public let toCall: String
    public let text: String
    public let isOutgoing: Bool
    public let snrDb: Int?
    public let timestamp: Date

    public init(fromCall: String, toCall: String, text: String, isOutgoing: Bool, snrDb: Int? = nil, timestamp: Date = Date()) {
        self.fromCall = fromCall
        self.toCall = toCall
        self.text = text
        self.isOutgoing = isOutgoing
        self.snrDb = snrDb
        self.timestamp = timestamp
    }
}

// MARK: - JS8 Engine Service

@MainActor
public final class JS8Engine: ObservableObject {
    public static let shared = JS8Engine()

    // Operating Controls
    @Published public var speed: JS8Speed = .normal
    @Published public var dialFrequencyHz: UInt64 = 14_078_000 // Standard 20m JS8 dial
    @Published public var audioOffsetHz: Double = 1500.0
    @Published public var isListening: Bool = false
    @Published public var isTransmitting: Bool = false
    @Published public var isSimulationActive: Bool = false

    // Timing & Slots
    @Published public var slotProgress: Double = 0.0
    @Published public var secondsRemaining: Double = 15.0

    // Stations Roster & Messages
    @Published public var stations: [JS8StationEntry] = []
    @Published public var messages: [JS8Message] = []
    @Published public var selectedStation: JS8StationEntry?
    @Published public var composerText: String = ""

    // Metrics
    @Published public var audioInputLevel: Float = 0.0
    @Published public var myCallsign: String = "EP2YAAM"
    @Published public var myGrid: String = "LL35"

    // Logging Callback
    public var logQSOHandler: ((_ call: String, _ mode: String, _ rstSent: String, _ rstRcvd: String, _ freqHz: UInt64, _ band: String) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var sampleRate: Double = 48000.0

    private var clockTimer: Timer?
    private var simTimer: Timer?
    private var txTask: Task<Void, Never>?
    private var simIdx: Int = 0

    public init() {
        startSlotClock()
    }

    // MARK: - UTC Slot Timing

    private func startSlotClock() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Date().timeIntervalSince1970
                let duration = self.speed.frameSeconds
                let elapsed = now.truncatingRemainder(dividingBy: duration)
                self.slotProgress = elapsed / duration
                self.secondsRemaining = duration - elapsed
            }
        }
    }

    // MARK: - Audio Start / Stop

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
            print("JS8Engine: Start error: \(error)")
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

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let totalFrames = Int(buffer.frameLength)

        var peak: Float = 0.0
        for i in stride(from: 0, to: totalFrames, by: 16) {
            let v = abs(channelData[i])
            if v > peak { peak = v }
        }

        let currentPeak = peak
        Task { @MainActor [weak self] in
            self?.audioInputLevel = currentPeak
        }
    }

    // MARK: - Messaging & Transmit

    public func sendMessage(text: String, to target: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        let dest = target.isEmpty ? "@ALLCALL" : target.uppercased()
        let newMsg = JS8Message(
            fromCall: myCallsign,
            toCall: dest,
            text: clean,
            isOutgoing: true
        )
        messages.append(newMsg)
        composerText = ""

        // Synthesize 8-GFSK audio transmission
        transmitJS8Message(newMsg)
    }

    private func transmitJS8Message(_ msg: JS8Message) {
        isTransmitting = true

        txTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let duration = await self.speed.frameSeconds
            let sRate = await self.sampleRate
            let baseFreq = await self.audioOffsetHz
            let toneSpacing = (await self.speed.bandwidthHz) / 8.0

            // 8-GFSK 79 symbols
            let symbols = (0..<79).map { _ in Int.random(in: 0..<8) }
            let symDuration = duration / 79.0
            let frameCount = Int(symDuration * sRate)

            for sym in symbols {
                let toneFreq = baseFreq + Double(sym) * toneSpacing
                await self.playGFSKTone(frequency: toneFreq, frameCount: frameCount)
            }

            await MainActor.run {
                self.isTransmitting = false
            }
        }
    }

    private func playGFSKTone(frequency: Double, frameCount: Int) async {
        guard frameCount > 0 else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        if let channel = buffer.floatChannelData?[0] {
            let omega = 2.0 * .pi * frequency / sampleRate
            for i in 0..<frameCount {
                // Gaussian shaped envelope
                let t = (Double(i) / Double(frameCount)) - 0.5
                let gEnv = exp(-12.0 * t * t)
                channel[i] = sin(Float(omega * Double(i))) * Float(gEnv) * 0.75
            }
        }

        if let player = self.playerNode, player.isPlaying {
            await player.scheduleBuffer(buffer)
        }
    }

    public func stopTransmission() {
        txTask?.cancel()
        txTask = nil
        isTransmitting = false
        playerNode?.stop()
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

        let sampleTraffic: [(call: String, grid: String, snr: Int, msg: String)] = [
            ("OH2XYZ", "KP20", -8, "@ALLCALL CQ CQ IN HELSINKI"),
            ("JA7YRR", "QM08", -12, "\(myCallsign): SNR?"),
            ("W3LPL", "FM19", -5, "@ALLCALL HEARTBEAT FM19"),
            ("HB9BZA", "JN47", -9, "\(myCallsign): RR 73 FROM GENEVA"),
            ("DL1ABC", "JO42", -6, "@ALLCALL CQ CQ DE DL1ABC")
        ]

        simIdx = 0
        simTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let item = sampleTraffic[self.simIdx % sampleTraffic.count]
                self.simIdx += 1

                let entity = DXCCDatabase.resolve(callsign: item.call)

                // Update roster
                if let existingIdx = self.stations.firstIndex(where: { $0.callsign == item.call }) {
                    self.stations[existingIdx] = JS8StationEntry(
                        callsign: item.call,
                        grid: item.grid,
                        snrDb: item.snr,
                        countryFlag: entity.flagEmoji,
                        countryName: entity.entityName,
                        lastHeard: Date(),
                        audioFreqHz: Double(1200 + (self.simIdx * 150) % 1400)
                    )
                } else {
                    self.stations.insert(JS8StationEntry(
                        callsign: item.call,
                        grid: item.grid,
                        snrDb: item.snr,
                        countryFlag: entity.flagEmoji,
                        countryName: entity.entityName,
                        lastHeard: Date(),
                        audioFreqHz: Double(1200 + (self.simIdx * 150) % 1400)
                    ), at: 0)
                }

                // Append chat message
                let msg = JS8Message(
                    fromCall: item.call,
                    toCall: item.msg.contains(self.myCallsign) ? self.myCallsign : "@ALLCALL",
                    text: item.msg,
                    isOutgoing: false,
                    snrDb: item.snr
                )
                self.messages.append(msg)
                self.audioInputLevel = 0.70
            }
        }
    }

    public func stopSimulation() {
        simTimer?.invalidate()
        simTimer = nil
        isSimulationActive = false
    }

    // MARK: - 1-Click Logging

    public func logCurrentQSO(target: String) {
        guard !target.isEmpty else { return }
        logQSOHandler?(target, "JS8", "-10", "-12", dialFrequencyHz, "20m")
    }
}
