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
    private var pingDeadlineTask: Task<Void, Never>?
    private var pingID: UUID?
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var desiredEndpoint: String?
    private var pttReceivers = Set<Int>()
    private var tuneReceivers = Set<Int>()
    private var transmitWatchdog: Task<Void, Never>?
    private let noticeSource = TransmitNotices.Source(name: "TCI")
    private var cwMacroActive = false
    private var cwReceivers = Set<Int>()
    private var cwSawTransmit = Set<Int>()
    private var connectedEndpoint = ""
    private var uncertainReceivers: [String: Set<Int>] = [:]
    private var recoveryInFlight = false
    private let linkNoticeSource = TransmitNotices.Source(name: "TCI connection / release")
    var holdsTransmit: Bool { cwMacroActive || isPTTActive || isTuneActive || !pttReceivers.isEmpty || !tuneReceivers.isEmpty }

    private func rememberUncertainRelease(_ reason: String) {
        guard holdsTransmit else { return }
        let endpoint = connectedEndpoint
        uncertainReceivers[endpoint, default: []].formUnion(pttReceivers.union(tuneReceivers).union(cwReceivers).union([0]))
        let text = "TCI (\(endpoint)): \(reason) at \(TXLimits.utc()). The radio may still be transmitting; receive cannot be confirmed. Other YAAM tools remain available. Check the original SDR is on receive locally; reconnect to that same SDR to retry the release."
        lastError = text
        TransmitNotices.shared.post(linkNoticeSource, text: text)
    }

    private static func releaseCommands(_ receivers: Set<Int>) -> String {
        "cw_macros_stop;" + receivers.sorted().map { "trx:\($0),false;tune:\($0),false;" }.joined()
    }


    public init() {
        self.host = UserDefaults.standard.string(forKey: "tciHost") ?? "127.0.0.1"
        let savedPort = UserDefaults.standard.integer(forKey: "tciPort")
        self.port = savedPort > 0 ? savedPort : 40001
        TransmitShutdown.register("TCI", isTransmitting: { [weak self] in self?.holdsTransmit ?? false },
                                  owner: self, release: { [weak self] in self?.disconnect() })
    }

    public var frequencyMHz: String {
        let mhz = Double(vfoAFrequencyHz) / 1_000_000.0
        return String(format: "%.4f", mhz)
    }

    public var currentBand: String {
        AmateurBandPlan.band(forMHz: Double(vfoAFrequencyHz) / 1_000_000.0) ?? "20M"
    }

    // MARK: - Connection Management

    public func connect(host: String? = nil, port: Int? = nil, recovering: Bool = false) {
        if let h = host { self.host = h }
        if let p = port { self.port = p }

        UserDefaults.standard.set(self.host, forKey: "tciHost")
        UserDefaults.standard.set(self.port, forKey: "tciPort")

        disconnect()
        isIntentionalDisconnect = false
        if !recovering { retryAttempt = 0 }

        guard (1...65_535).contains(self.port), let url = URL(string: "ws://\(self.host):\(self.port)") else {
            self.lastError = "Invalid WebSocket URL"
            self.statusMessage = "Invalid URL"
            return
        }

        self.statusMessage = "Connecting to ws://\(self.host):\(self.port)..."

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.connectedEndpoint = url.absoluteString
        self.desiredEndpoint = url.absoluteString
        self.webSocketTask = task
        task.resume()

        listenForMessages()
        startPingTimer()

        // TCI servers send initialization followed by ready; clients wait for the server state.
    }

    public func disconnect() {
        if isConnected { NotificationCenter.default.post(name: Notification.Name("YAAMRadioConnectionLost"), object: self) }
        retryTask?.cancel()
        retryTask = nil
        desiredEndpoint = nil
        pingDeadlineTask?.cancel()
        pingDeadlineTask = nil
        pingID = nil
        isIntentionalDisconnect = true
        pingTimer?.invalidate()
        pingTimer = nil
        transmitWatchdog?.cancel()
        transmitWatchdog = nil
        let task = webSocketTask
        webSocketTask = nil
        recoveryInFlight = false
        if holdsTransmit, let task {
            rememberUncertainRelease("the connection was closed during TX; a release was requested")
            let endpoint = connectedEndpoint
            let commands = Self.releaseCommands(pttReceivers.union(tuneReceivers).union(cwReceivers).union([0]))
            // A completed WebSocket write is not confirmation of physical receive.
            task.send(.string(commands)) { [weak self] error in
                if let error {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        TransmitNotices.shared.post(self.linkNoticeSource, text: "TCI (\(endpoint)): release write failed at \(TXLimits.utc()): \(error.localizedDescription). Receive is unconfirmed. Other YAAM tools remain available; check the original SDR locally.")
                    }
                }
                task.cancel(with: .goingAway, reason: nil)
            }
            Task { try? await Task.sleep(for: .seconds(2)); task.cancel(with: .goingAway, reason: nil) }
        } else {
            task?.cancel(with: .goingAway, reason: nil)
        }
        cwMacroActive = false
        cwReceivers.removeAll(); cwSawTransmit.removeAll()
        isConnected = false
        isPTTActive = false
        isTuneActive = false
        pttReceivers.removeAll()
        tuneReceivers.removeAll()
        statusMessage = "Disconnected; check the radio is on receive"
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.probeLink() }
        }
        probeLink()
    }

    private func probeLink() {
        guard let task = webSocketTask, pingID == nil else { return }
        let id = UUID()
        pingID = id
        pingDeadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, self.webSocketTask === task, self.pingID == id else { return }
            self.handleDisconnect(reason: "No WebSocket pong within 3 s")
        }
        task.sendPing { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.webSocketTask === task, self.pingID == id else { return }
                self.pingDeadlineTask?.cancel()
                self.pingDeadlineTask = nil
                self.pingID = nil
                if error != nil { self.handleDisconnect(reason: "Ping failed") }
                else { self.retryAttempt = 0 }
            }
        }
    }

    private func handleDisconnect(reason: String) {
        guard !isIntentionalDisconnect else { return }
        rememberUncertainRelease("the link was lost (\(reason))")
        NotificationCenter.default.post(name: Notification.Name("YAAMRadioConnectionLost"), object: self)
        pingDeadlineTask?.cancel()
        pingDeadlineTask = nil
        pingID = nil
        self.isConnected = false
        self.statusMessage = "Connection lost: \(reason); check the SDR is on receive"
        if !holdsTransmit { self.lastError = reason }
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil // a queued success from the failed session cannot resurrect it
        guard let endpoint = desiredEndpoint, retryTask == nil, retryAttempt < 5,
              !TransmitShutdown.isShuttingDown else { return }
        let originalHost = host, originalPort = port
        retryAttempt += 1
        let delay = min(30, 1 << retryAttempt)
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.desiredEndpoint == endpoint, !self.isIntentionalDisconnect,
                  self.host == originalHost, self.port == originalPort, !Task.isCancelled else { return }
            self.retryTask = nil
            self.connect(host: originalHost, port: originalPort, recovering: true)
        }
    }

    // MARK: - Message Processing Loop

    private func listenForMessages() {
        guard let task = webSocketTask else { return }

        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self, self.webSocketTask === task else { return }

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
        if !isConnected, !recoveryInFlight, let task = webSocketTask {
            if let receivers = uncertainReceivers[connectedEndpoint] {
                recoveryInFlight = true
                let endpoint = connectedEndpoint
                // Recovery is scoped to the original destination. Never release an unrelated SDR.
                task.send(.string(Self.releaseCommands(receivers))) { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self, self.webSocketTask === task else { return }
                        self.recoveryInFlight = false
                        if let error { self.handleDisconnect(reason: "Recovery release failed: \(error.localizedDescription)"); return }
                        self.uncertainReceivers.removeValue(forKey: endpoint)
                        self.isConnected = true
                        self.statusMessage = "Connected; release sent. Check the SDR is on receive."
                    }
                }
            } else {
                isConnected = true
                statusMessage = "Connected (\(connectedEndpoint))"
            }
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
            if cmd.lowercased() == "ready", !recoveryInFlight {
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
                let receiver = args.count > 1 ? (Int(args[0]) ?? 0) : 0
                if last.lowercased() == "true" || last == "1" { pttReceivers.insert(receiver) }
                else { pttReceivers.remove(receiver) }
                if last.lowercased() == "true" || last == "1" {
                    if cwReceivers.contains(receiver) { cwSawTransmit.insert(receiver) }
                } else if cwSawTransmit.remove(receiver) != nil {
                    // A real TX→RX notification closes CW ownership. The local Morse clock cannot do so.
                    cwReceivers.remove(receiver)
                    cwMacroActive = !cwReceivers.isEmpty
                }
                self.isPTTActive = !pttReceivers.isEmpty
                if pttReceivers.isEmpty && tuneReceivers.isEmpty && !cwMacroActive { transmitWatchdog?.cancel(); transmitWatchdog = nil }
            }

        case "tune":
            // tune:<receiver>,<true|false>
            if let last = args.last {
                let receiver = args.count > 1 ? (Int(args[0]) ?? 0) : 0
                if last.lowercased() == "true" || last == "1" { tuneReceivers.insert(receiver) }
                else { tuneReceivers.remove(receiver) }
                self.isTuneActive = !tuneReceivers.isEmpty
                if pttReceivers.isEmpty && tuneReceivers.isEmpty && !cwMacroActive { transmitWatchdog?.cancel(); transmitWatchdog = nil }
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
        guard let task = webSocketTask, isConnected, !recoveryInFlight else { return }
        let msg = command.hasSuffix(";") ? command : "\(command);"
        let endpoint = connectedEndpoint
        let isRelease = command == "cw_macros_stop;" || command.hasSuffix(",false;")
        var releaseReceivers = pttReceivers.union(tuneReceivers).union(cwReceivers).union([0])
        if command.hasPrefix("trx:") || command.hasPrefix("tune:"),
           let payload = command.split(separator: ":", maxSplits: 1).last,
           let argument = payload.split(separator: ",").first, let receiver = Int(argument) {
            releaseReceivers.insert(receiver)
        }
        let failedReleaseReceivers = releaseReceivers
        task.send(.string(msg)) { [weak self] error in
            if let err = error {
                Task { @MainActor [weak self] in
                    guard let self, self.webSocketTask === task else { return }
                    if isRelease {
                        self.uncertainReceivers[endpoint, default: []].formUnion(failedReleaseReceivers)
                        TransmitNotices.shared.post(self.linkNoticeSource, text: "TCI (\(endpoint)): release write failed at \(TXLimits.utc()): \(err.localizedDescription). Receive is unconfirmed. Other YAAM tools remain available; check the original SDR locally.")
                    }
                    self.handleDisconnect(reason: err.localizedDescription)
                }
            }
        }
    }

    public func setFrequency(hz: UInt64, receiver: Int = 0, vfo: Int = 0) {
        self.vfoAFrequencyHz = hz
        sendCommand("vfo:\(receiver),\(vfo),\(hz);")
    }

    /// Sets the SDR's mode. The mode can come from outside (a DX cluster or WSJT-X spot, when tuning to it), and TCI
    /// reserves ":", "," and ";" in any argument (TCI Protocol 2.1, 3.1): a ";" would end the command and let the rest be
    /// read as another one (such as "trx:0,true;"). Such a mode, or an empty one, is not sent, and the operator is told.
    @discardableResult
    public func setMode(_ mode: String, receiver: Int = 0) -> Bool {
        guard isConnected, !recoveryInFlight else { return false }
        if let refusal = Self.modeRefusal(mode) {
            lastError = refusal
            return false
        }
        let clean = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.mode = clean.uppercased()
        sendCommand("modulation:\(receiver),\(clean);")
        return true
    }

    /// Why setMode would not send `mode` (B-018), or nil if it would.
    static func modeRefusal(_ mode: String) -> String? {
        let clean = mode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.isEmpty || hasReservedCharacter(clean) else { return nil }
        // Shown in the log: a line break or control character in outside text must not start a line of its own there.
        let printable = mode.prefix(16).map { $0.isNewline || $0.unicodeScalars.contains { $0.properties.generalCategory == .control } ? "?" : $0 }
        let shown = String(printable) + (mode.count > 16 ? "…" : "")
        return "TCI: mode \"\(shown)\" not sent to the SDR at \(TXLimits.utc()): it is empty or has \":\", \",\" or \";\", "
            + "which TCI reserves. The SDR keeps its mode; choose the mode by hand. The rest of YAAM is not affected."
    }

    public func setPTT(_ active: Bool, receiver: Int = 0) {
        if active {
            guard !TransmitShutdown.isShuttingDown, isConnected, !recoveryInFlight else { return }
            pttReceivers.insert(receiver)
            startTransmitWatchdog()
        } else {
            if !isConnected { rememberUncertainRelease("PTT release was requested without a working link") }
            pttReceivers.remove(receiver)
        }
        self.isPTTActive = !pttReceivers.isEmpty
        if pttReceivers.isEmpty && tuneReceivers.isEmpty && !cwMacroActive { transmitWatchdog?.cancel(); transmitWatchdog = nil }
        sendCommand("trx:\(receiver),\(active ? "true" : "false");")
    }

    public func setTune(_ active: Bool, receiver: Int = 0) {
        if active {
            guard !TransmitShutdown.isShuttingDown, isConnected, !recoveryInFlight else { return }
            tuneReceivers.insert(receiver)
            startTransmitWatchdog()
        } else {
            if !isConnected { rememberUncertainRelease("Tune release was requested without a working link") }
            tuneReceivers.remove(receiver)
        }
        self.isTuneActive = !tuneReceivers.isEmpty
        if pttReceivers.isEmpty && tuneReceivers.isEmpty && !cwMacroActive { transmitWatchdog?.cancel(); transmitWatchdog = nil }
        sendCommand("tune:\(receiver),\(active ? "true" : "false");")
    }

    private func startTransmitWatchdog() {
        guard transmitWatchdog == nil else { return }
        let keyedAt = Date(), started = ProcessInfo.processInfo.systemUptime
        transmitWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(TXLimits.hardPTT))
            guard !Task.isCancelled, let self else { return }
            self.disconnect()
            let text = TXLimits.safetyTimerMessage(radio: "TCI", keyedAt: keyedAt, limit: TXLimits.hardPTT,
                elapsed: ProcessInfo.processInfo.systemUptime - started)
            TransmitNotices.shared.post(self.noticeSource, text: text)
        }
    }

    public func setDrivePower(_ level: Int) {
        let clamped = max(0, min(100, level))
        self.drivePower = clamped
        sendCommand("drive:\(clamped);")
    }

    // MARK: - CW Transmission via SDR DSP

    public func sendCW(text: String, receiver: Int = 0, wpm: Int = 25) {
        guard !TransmitShutdown.isShuttingDown, isConnected, !recoveryInFlight, !text.isEmpty else { return }
        cwMacroActive = true
        cwReceivers.insert(receiver)
        startTransmitWatchdog()
        let wpm = min(60, max(5, wpm))
        sendCommand("cw_macros_speed:\(wpm);")
        // TCI Protocol 2.1 (Expert Electronics): "CW_MACROS:arg1,arg2;" (arg1 the transceiver, arg2 the text).
        sendCommand("cw_macros:\(receiver),\(Self.macroText(text));")
    }

    /// The text of a CW macro as TCI Protocol 2.1 asks: ":", "," and ";" end a command or an argument, so they are sent
    /// as "^", "~" and "*", and the TCI server turns them back. Otherwise "599, NAME" would end the macro at the comma.
    nonisolated static func macroText(_ text: String) -> String {
        text.replacingOccurrences(of: ":", with: "^")
            .replacingOccurrences(of: ",", with: "~")
            .replacingOccurrences(of: ";", with: "*")
    }

    public func stopCW() {
        if !isConnected { rememberUncertainRelease("CW stop was requested without a working link") }
        sendCommand("cw_macros_stop;")
        cwMacroActive = false
        cwReceivers.removeAll(); cwSawTransmit.removeAll()
        if pttReceivers.isEmpty && tuneReceivers.isEmpty { transmitWatchdog?.cancel(); transmitWatchdog = nil }
    }

    // MARK: - Spectrum Waterfall Spot Streaming

    /// Sends a spot to the SDR panorama. Spots come from the DX cluster or WSJT-X, so every field is text from outside: TCI
    /// reserves ":", "," and ";" in any argument (TCI Protocol 2.1, 3.1), and a ";" in it would end the command and
    /// let the rest be read as another one (such as "trx:0,true;"). The comment is sent as the protocol sends CW text
    /// (macroText); a spot whose callsign or mode has a reserved character is not sent. Returns whether it was sent.
    @discardableResult
    public func postSpot(
        callsign: String,
        mode: String,
        frequencyHz: UInt64,
        argbColor: UInt32 = 4278255360, // Default vibrant green
        text: String = ""
    ) -> Bool {
        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanText = Self.macroText(text.trimmingCharacters(in: .whitespacesAndNewlines))
        let cleanMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // An empty mode would be an empty argument, which TCI drops (Notes on the Command Format, 1): the fields shift.
        guard !cleanCall.isEmpty, !cleanMode.isEmpty, !Self.hasReservedCharacter(cleanCall),
              !Self.hasReservedCharacter(cleanMode) else {
            return false
        }
        // sendCommand sends nothing without a connection; say so to the caller.
        guard webSocketTask != nil, isConnected, !recoveryInFlight else { return false }

        // spot:<callsign>,<mode>,<frequency_hz>,<color_argb>,<text>;
        sendCommand("spot:\(cleanCall),\(cleanMode),\(frequencyHz),\(argbColor),\(cleanText);")
        return true
    }

    public func deleteSpot(callsign: String) {
        guard !Self.hasReservedCharacter(callsign) else { return }
        sendCommand("spot_delete:\(callsign.uppercased());")
    }

    /// Whether `text` has a character TCI reserves for its own syntax (":", "," or ";").
    nonisolated static func hasReservedCharacter(_ text: String) -> Bool {
        text.contains { $0 == ":" || $0 == "," || $0 == ";" } || text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    public func clearAllSpots() {
        sendCommand("spot_clear;")
    }
}
