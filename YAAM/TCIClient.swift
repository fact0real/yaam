//
//  TCIClient.swift
//  YAAM
//
//  Transceiver Control Interface (TCI) WebSocket Client for SDR Radios
//  ExpertSDR2/3 (SunSDR2 / MB1), Thetis (ANAN), SDRUno, SDR-Console
//  Bi-directional VFO frequency control, Mode, PTT/Tune, S-meter, Power/SWR,
//  DSP Morse Keying, and Live Spectrum Waterfall Spot Streaming.
//

import Combine
import Foundation
import SwiftUI

@MainActor
public final class TCIClient: ObservableObject {
    public static let shared = TCIClient()

    // MARK: - Published State
    @Published public var isConnected: Bool = false
    @Published public var host: String = "127.0.0.1"
    @Published public var port: Int = 40001
    @Published public var vfoAFrequencyHz: UInt64 = 14074000
    @Published public var vfoBFrequencyHz: UInt64 = 14074000
    @Published public var mode: String = "USB"
    @Published public var isPTTActive: Bool = false
    @Published public var isTuneActive: Bool = false
    @Published public var drivePower: Int = 50
    @Published public var sMeterDbm: Double = -73.0 // S9 standard
    @Published public var txPowerWatts: Double = 0.0
    @Published public var txSWR: Double = 1.0
    @Published public var serverProtocol: String = "1.0"
    @Published public var statusMessage: String = "Disconnected"
    @Published public var lastError: String? = nil

    private var webSocketTask: URLSessionWebSocketTask?
    private var isIntentionalDisconnect: Bool = false
    private var pingTimer: Timer?

    public init() {
        self.host = UserDefaults.standard.string(forKey: "tciHost") ?? "127.0.0.1"
        let savedPort = UserDefaults.standard.integer(forKey: "tciPort")
        self.port = savedPort > 0 ? savedPort : 40001
    }

    public var frequencyMHz: String {
        let mhz = Double(vfoAFrequencyHz) / 1_000_000.0
        return String(format: "%.4f", mhz)
    }

    public var currentBand: String {
        AmateurBandPlan.band(forMHz: Double(vfoAFrequencyHz) / 1_000_000.0) ?? "20M"
    }

    // MARK: - Connection Management

    public func connect(host: String? = nil, port: Int? = nil) {
        if let h = host { self.host = h }
        if let p = port { self.port = p }

        UserDefaults.standard.set(self.host, forKey: "tciHost")
        UserDefaults.standard.set(self.port, forKey: "tciPort")

        disconnect()
        isIntentionalDisconnect = false

        guard let url = URL(string: "ws://\(self.host):\(self.port)") else {
            self.lastError = "Invalid WebSocket URL"
            self.statusMessage = "Invalid URL"
            return
        }

        self.statusMessage = "Connecting to ws://\(self.host):\(self.port)..."

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        listenForMessages()
        startPingTimer()

        // Send ready handshake
        sendCommand("ready;")
    }

    public func disconnect() {
        isIntentionalDisconnect = true
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        isPTTActive = false
        isTuneActive = false
        statusMessage = "Disconnected"
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let task = self.webSocketTask, self.isConnected else { return }
                task.sendPing { error in
                    if error != nil {
                        Task { @MainActor [weak self] in
                            self?.handleDisconnect(reason: "Ping failed")
                        }
                    }
                }
            }
        }
    }

    private func handleDisconnect(reason: String) {
        guard !isIntentionalDisconnect else { return }
        self.isConnected = false
        self.statusMessage = "Connection lost: \(reason)"
        self.lastError = reason
    }

    // MARK: - Message Processing Loop

    private func listenForMessages() {
        guard let task = webSocketTask else { return }

        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.processIncomingCommands(text)
                    case .data(let data):
                        if let str = String(data: data, encoding: .utf8) {
                            self.processIncomingCommands(str)
                        }
                    @unknown default:
                        break
                    }
                    self.listenForMessages()

                case .failure(let error):
                    self.handleDisconnect(reason: error.localizedDescription)
                }
            }
        }
    }

    private func processIncomingCommands(_ raw: String) {
        if !self.isConnected {
            self.isConnected = true
            self.statusMessage = "Connected (ws://\(host):\(port))"
        }

        // TCI commands are delimited by semicolon (;)
        let commands = raw.components(separatedBy: ";")
        for cmd in commands {
            let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            parseSingleCommand(trimmed)
        }
    }

    private func parseSingleCommand(_ cmd: String) {
        let parts = cmd.components(separatedBy: ":")
        guard parts.count >= 2 else {
            if cmd.lowercased() == "ready" {
                self.isConnected = true
                self.statusMessage = "Connected to SDR"
            }
            return
        }

        let key = parts[0].lowercased().trimmingCharacters(in: .whitespaces)
        let payload = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
        let args = payload.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        switch key {
        case "vfo":
            // vfo:<receiver>,<vfo_id>,<frequency_hz>
            if args.count >= 3, let vfoIndex = Int(args[1]), let hz = UInt64(args[2]) {
                if vfoIndex == 0 {
                    self.vfoAFrequencyHz = hz
                } else {
                    self.vfoBFrequencyHz = hz
                }
            } else if args.count == 1, let hz = UInt64(args[0]) {
                self.vfoAFrequencyHz = hz
            }

        case "modulation":
            // modulation:<receiver>,<mode>
            if args.count >= 2 {
                self.mode = args[1].uppercased()
            } else if args.count == 1 {
                self.mode = args[0].uppercased()
            }

        case "trx":
            // trx:<receiver>,<true|false>
            if let last = args.last {
                self.isPTTActive = (last.lowercased() == "true" || last == "1")
            }

        case "tune":
            // tune:<receiver>,<true|false>
            if let last = args.last {
                self.isTuneActive = (last.lowercased() == "true" || last == "1")
            }

        case "drive":
            if let level = Int(args[0]) {
                self.drivePower = level
            }

        case "smeter":
            // smeter:<receiver>,<channel>,<dbm>
            if let val = Double(args.last ?? "") {
                self.sMeterDbm = val
            }

        case "power":
            if let watts = Double(args[0]) {
                self.txPowerWatts = watts
            }

        case "swr":
            if let swrVal = Double(args[0]) {
                self.txSWR = swrVal
            }

        case "protocol":
            if let p = args.first {
                self.serverProtocol = p
            }

        default:
            break
        }
    }

    // MARK: - Outgoing Control Commands

    public func sendCommand(_ command: String) {
        guard let task = webSocketTask, isConnected else { return }
        let msg = command.hasSuffix(";") ? command : "\(command);"
        task.send(.string(msg)) { error in
            if let err = error {
                Task { @MainActor [weak self] in
                    self?.lastError = err.localizedDescription
                }
            }
        }
    }

    public func setFrequency(hz: UInt64, receiver: Int = 0, vfo: Int = 0) {
        self.vfoAFrequencyHz = hz
        sendCommand("vfo:\(receiver),\(vfo),\(hz);")
    }

    public func setMode(_ mode: String, receiver: Int = 0) {
        let clean = mode.lowercased()
        self.mode = mode.uppercased()
        sendCommand("modulation:\(receiver),\(clean);")
    }

    public func setPTT(_ active: Bool, receiver: Int = 0) {
        self.isPTTActive = active
        sendCommand("trx:\(receiver),\(active ? "true" : "false");")
    }

    public func setTune(_ active: Bool, receiver: Int = 0) {
        self.isTuneActive = active
        sendCommand("tune:\(receiver),\(active ? "true" : "false");")
    }

    public func setDrivePower(_ level: Int) {
        let clamped = max(0, min(100, level))
        self.drivePower = clamped
        sendCommand("drive:\(clamped);")
    }

    // MARK: - CW Transmission via SDR DSP

    public func sendCW(text: String, receiver: Int = 0, wpm: Int = 25) {
        sendCommand("cw_macros_speed:\(wpm);")
        sendCommand("cw_macro:\(receiver),\(text);")
    }

    public func stopCW() {
        sendCommand("cw_macros_stop;")
    }

    // MARK: - Spectrum Waterfall Spot Streaming

    public func postSpot(
        callsign: String,
        mode: String,
        frequencyHz: UInt64,
        argbColor: UInt32 = 4278255360, // Default vibrant green
        text: String = ""
    ) {
        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCall.isEmpty else { return }

        // spot:<callsign>,<mode>,<frequency_hz>,<color_argb>,<text>;
        sendCommand("spot:\(cleanCall),\(mode.lowercased()),\(frequencyHz),\(argbColor),\(cleanText);")
    }

    public func deleteSpot(callsign: String) {
        sendCommand("spot_delete:\(callsign.uppercased());")
    }

    public func clearAllSpots() {
        sendCommand("spot_clear;")
    }
}
