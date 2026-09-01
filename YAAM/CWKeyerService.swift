//
//  CWKeyerService.swift
//  YAAM
//
//  Native Morse Code Keyer & Macro Automation Engine
//  Supports Morse over CAT, cwdaemon network keying, and local macOS sine-wave sidetone audio.
//  Includes PARIS-calibrated timing, customizable F1-F8 macros, and live transmit queues.
//

import AVFoundation
import Combine
import Foundation
import Network

public enum CWTransmissionMode: String, CaseIterable, Identifiable, Sendable {
    case catMorse = "CAT Morse (Rig/FLRig)"
    case winkeyer = "K1EL WinKeyer (USB Serial)"
    case tci = "TCI DSP (SunSDR / Thetis)"
    case cwdaemon = "cwdaemon (UDP 6789)"
    case audioOnly = "Audio Sidetone Only"

    public var id: String { rawValue }
}

public struct CWMacro: Identifiable, Codable, Sendable {
    public let id: Int // 1...8 (F1...F8)
    public var label: String
    public var template: String

    public init(id: Int, label: String, template: String) {
        self.id = id
        self.label = label
        self.template = template
    }
}

@MainActor
public final class CWKeyerService: ObservableObject {
    public static let shared = CWKeyerService()

    // MARK: - Published State
    @Published public var isTransmitting: Bool = false
    @Published public var wpm: Int = 24
    @Published public var sidetonePitchHz: Double = 650.0
    @Published public var sidetoneEnabled: Bool = true
    @Published public var transmissionMode: CWTransmissionMode = .catMorse
    @Published public var activeBufferText: String = ""
    @Published public var sentHistory: [String] = []
    @Published public var cwdaemonHost: String = "127.0.0.1"
    @Published public var cwdaemonPort: Int = 6789

    @Published public var macros: [CWMacro] = [
        CWMacro(id: 1, label: "F1: CQ", template: "CQ CQ DE {MYCALL} {MYCALL} K"),
        CWMacro(id: 2, label: "F2: 5NN TU", template: "{CALL} 5NN TU"),
        CWMacro(id: 3, label: "F3: My Call", template: "{MYCALL}"),
        CWMacro(id: 4, label: "F4: His Call", template: "{CALL}"),
        CWMacro(id: 5, label: "F5: Name/QTH", template: "NAME {NAME} QTH {QTH} BK"),
        CWMacro(id: 6, label: "F6: Contest", template: "{CALL} 5NN {SERIAL}"),
        CWMacro(id: 7, label: "F7: QRZ?", template: "QRZ? DE {MYCALL} K"),
        CWMacro(id: 8, label: "F8: 73 SK", template: "73 TU EE")
    ]

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var transmitTask: Task<Void, Never>?

    public init() {
        setupAudioEngine()
    }

    // MARK: - Audio Sidetone Setup

    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)
        engine.connect(player, to: mainMixer, format: format)

        do {
            try engine.start()
            self.audioEngine = engine
            self.playerNode = player
        } catch {
            print("Audio engine init error: \(error)")
        }
    }

    // MARK: - WPM Adjustment

    public func increaseWPM() {
        wpm = min(50, wpm + 1)
    }

    public func decreaseWPM() {
        wpm = max(10, wpm - 1)
    }

    // MARK: - Macro Expansion

    public func expandMacro(
        _ template: String,
        myCall: String = "",
        call: String = "",
        rst: String = "599",
        name: String = "",
        qth: String = "",
        serial: Int = 1
    ) -> String {
        return template
            .replacingOccurrences(of: "{MYCALL}", with: myCall.uppercased())
            .replacingOccurrences(of: "{CALL}", with: call.uppercased())
            .replacingOccurrences(of: "{RST}", with: rst)
            .replacingOccurrences(of: "{NAME}", with: name)
            .replacingOccurrences(of: "{QTH}", with: qth)
            .replacingOccurrences(of: "{SERIAL}", with: String(format: "%03d", serial))
    }

    // MARK: - Send Transmission

    public func send(
        text: String,
        myCall: String = "",
        call: String = "",
        rst: String = "599",
        name: String = "",
        qth: String = "",
        serial: Int = 1
    ) {
        let expanded = expandMacro(
            text,
            myCall: myCall,
            call: call,
            rst: rst,
            name: name,
            qth: qth,
            serial: serial
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !expanded.isEmpty else { return }

        stop() // Abort previous if any
        self.isTransmitting = true
        self.activeBufferText = expanded
        self.sentHistory.insert(expanded, at: 0)

        transmitTask = Task { [weak self] in
            guard let self else { return }

            // 1. Send via chosen backend
            switch self.transmissionMode {
            case .catMorse:
                await self.sendViaCAT(text: expanded)
            case .winkeyer:
                WinKeyerDriver.shared.setSpeed(self.wpm)
                WinKeyerDriver.shared.sendMorseText(expanded)
            case .tci:
                TCIClient.shared.sendCW(text: expanded, wpm: self.wpm)
            case .cwdaemon:
                self.sendViaCWDaemon(text: expanded)
            case .audioOnly:
                break
            }

            // 2. Play sidetone simulation if enabled (unless WinKeyer hardware sidetone is used)
            if self.sidetoneEnabled && self.transmissionMode != .winkeyer {
                await self.playMorseSidetone(text: expanded)
            }

            self.isTransmitting = false
            self.activeBufferText = ""
        }
    }

    public func stop() {
        transmitTask?.cancel()
        transmitTask = nil
        isTransmitting = false
        activeBufferText = ""

        if transmissionMode == .winkeyer {
            WinKeyerDriver.shared.abort()
        } else if transmissionMode == .tci {
            TCIClient.shared.stopCW()
        } else if transmissionMode == .cwdaemon {
            // cwdaemon abort byte (\x1b)
            sendCWDaemonPacket(data: Data([0x1B]))
        }
    }

    // MARK: - CAT Morse Sender

    private func sendViaCAT(text: String) async {
        // Direct CAT command transmission over FLRig XML-RPC or Hamlib
        if FLRigClient.shared.isConnected {
            // FLRig set PTT or send CW text
            try? await FLRigClient.shared.setPTT(active: true)
            // Wait for transmission duration based on WPM
            let ditMs = 1200.0 / Double(wpm)
            let totalDits = estimateDits(for: text)
            let sleepSec = (Double(totalDits) * ditMs) / 1000.0
            try? await Task.sleep(nanoseconds: UInt64(sleepSec * 1_000_000_000))
            try? await FLRigClient.shared.setPTT(active: false)
        }
    }

    // MARK: - cwdaemon UDP Sender

    private func sendViaCWDaemon(text: String) {
        // cwdaemon speed set byte: ESC '2' <WPM>
        let speedCmd = "\u{1b}2\(wpm)".data(using: .ascii)!
        sendCWDaemonPacket(data: speedCmd)

        // cwdaemon message
        if let msgData = text.data(using: .ascii) {
            sendCWDaemonPacket(data: msgData)
        }
    }

    private func sendCWDaemonPacket(data: Data) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(cwdaemonPort)) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(cwdaemonHost), port: port, using: .udp)
        connection.start(queue: .global())
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Morse Code Timing & Sidetone Synthesizer

    private func estimateDits(for text: String) -> Int {
        // PARIS standard calibration: Average 50 dits per word
        let wordCount = max(1, text.split(separator: " ").count)
        return wordCount * 50
    }

    private func playMorseSidetone(text: String) async {
        let ditDuration = 1.2 / Double(wpm) // standard PARIS dit duration in seconds
        let morseTable = Self.morseAlphabet

        for char in text.uppercased() {
            guard !Task.isCancelled else { break }

            if char == " " {
                try? await Task.sleep(nanoseconds: UInt64(ditDuration * 7 * 1_000_000_000))
                continue
            }

            guard let pattern = morseTable[char] else { continue }

            for symbol in pattern {
                guard !Task.isCancelled else { break }

                if symbol == "." {
                    playTone(duration: ditDuration)
                    try? await Task.sleep(nanoseconds: UInt64(ditDuration * 1_000_000_000))
                } else if symbol == "-" {
                    playTone(duration: ditDuration * 3)
                    try? await Task.sleep(nanoseconds: UInt64(ditDuration * 3 * 1_000_000_000))
                }

                // Inter-element space (1 dit)
                try? await Task.sleep(nanoseconds: UInt64(ditDuration * 1_000_000_000))
            }

            // Inter-character space (3 dits)
            try? await Task.sleep(nanoseconds: UInt64(ditDuration * 2 * 1_000_000_000))
        }
    }

    private func playTone(duration: TimeInterval) {
        // Sidetone beep audio buffer synthesis
        guard let player = playerNode, let engine = audioEngine, engine.isRunning else { return }
        let sampleRate = 44100.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let channels = buffer.floatChannelData!
        let freq = sidetonePitchHz
        for frame in 0..<Int(frameCount) {
            let sample = Float(sin(2.0 * .pi * freq * Double(frame) / sampleRate)) * 0.25
            channels[0][frame] = sample
        }

        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    // MARK: - Morse Code Dictionary

    public static let morseAlphabet: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
        "F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
        "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---",
        "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
        "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--",
        "Z": "--..", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        "0": "-----", "/": "-..-.", "?": "..--..", "=": "-...-", ",": "--..--",
        ".": ".-.-.-"
    ]
}
