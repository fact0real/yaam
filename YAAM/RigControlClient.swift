//
//  RigControlClient.swift
//  YAAM
//

import Combine
import Foundation
import Network

nonisolated enum RigConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var title: String {
        switch self {
        case .disconnected: return "Offline"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .failed: return "Connection failed"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

nonisolated struct RigSnapshot: Equatable, Sendable {
    var frequencyHz: UInt64
    var mode: String
    var passbandHz: Int?
    var updatedAt: Date

    var frequencyMHz: String {
        AmateurBandPlan.formattedMHz(Double(frequencyHz) / 1_000_000)
    }

    var band: String {
        AmateurBandPlan.band(forMHz: Double(frequencyHz) / 1_000_000) ?? ""
    }
}

final class RigControlClient: ObservableObject {
    public static let shared = RigControlClient()

    @Published private(set) var state: RigConnectionState = .disconnected
    @Published private(set) var snapshot: RigSnapshot?
    @Published private(set) var isTransmitting = false
    @Published private(set) var lastMessage = "Ready to connect to rigctld"

    private let queue = DispatchQueue(label: "app.yaam.rig-control", qos: .userInitiated)
    private var connection: NWConnection?
    private var pollTimer: DispatchSourceTimer?
    private var replies: RigctldReplyStream?
    private var connectionID = UUID()
    private var pendingFrequency: UInt64?
    private var pendingMode = ""
    private var pendingPassband: Int?
    private var pttWatchdog: DispatchWorkItem?
    private var pttGeneration = UUID()
    private var noticeSource = TransmitNotices.Source(name: "rigctld") // this radio's own safety notices

    private let releaseNoticeSource = TransmitNotices.Source(name: "rigctld connection / release")

    private func releaseUncertain(_ reason: String, sourceName: String? = nil) {
        let text = "\(sourceName ?? noticeSource.name): \(reason) at \(TXLimits.utc()). Receive is unconfirmed. Other YAAM tools remain available. Release PTT locally and check the radio is on receive."
        lastMessage = text
        TransmitNotices.shared.post(releaseNoticeSource, text: text)
    }

    init() {
        TransmitShutdown.register("rigctld", isTransmitting: { [weak self] in (self?.isTransmitting ?? false) || (self?.replies?.hasTransmitRisk ?? false) },
                                  owner: self, release: { [weak self] in self?.setPTT(false) })
    }

    deinit {
        pttWatchdog?.cancel()
        pollTimer?.cancel()
        connection?.cancel()
    }

    func connect(host rawHost: String, port rawPort: Int) {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, (1...65_535).contains(rawPort), let port = NWEndpoint.Port(rawValue: UInt16(rawPort)) else {
            state = .failed("Enter a valid rigctld host and port.")
            lastMessage = "Rig Control settings are incomplete"
            return
        }

        disconnect()
        pendingFrequency = nil
        pendingMode = ""
        pendingPassband = nil
        snapshot = nil
        noticeSource.name = "rigctld (\(host):\(rawPort))"
        let id = UUID()
        connectionID = id
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        self.connection = connection
        let reader = RigctldReplyStream(connection)
        replies = reader
        let source = releaseNoticeSource, sourceName = noticeSource.name
        reader.onError = { [weak self] reason, safety in
            if safety {
                let text = "\(sourceName): \(reason) at \(TXLimits.utc()). Receive is unconfirmed. Release PTT locally and check the original radio."
                TransmitNotices.shared.post(source, text: text)
            }
            guard let self, self.connectionID == id else { return }
            self.lastMessage = reason
        }
        reader.onReply = { [weak self] reply in
            guard let self, self.connectionID == id, reply.result == 0,
                  reply.command == "get_freq" || reply.command == "get_mode" else { return }
            if let value = reply.fields["Frequency"].flatMap(UInt64.init) { self.pendingFrequency = value }
            if let mode = reply.fields["Mode"] { self.pendingMode = mode }
            if let band = reply.fields["Passband"].flatMap(Int.init) { self.pendingPassband = band }
            guard let frequency = self.pendingFrequency else { return }
            self.snapshot = RigSnapshot(frequencyHz: frequency, mode: self.pendingMode,
                passbandHz: self.pendingPassband, updatedAt: Date())
        }
        DispatchQueue.main.async {
            self.state = .connecting
            self.lastMessage = "Opening \(host):\(rawPort)..."
        }

        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            self.queue.async {
                guard self.connectionID == id else { return }
                self.handle(newState, connectionID: id, host: host, port: rawPort)
            }
        }
        connection.start(queue: queue)
    }

    func disconnect() {
        let old = connection
        let wasTransmitting = isTransmitting || (replies?.hasTransmitRisk ?? false)
        pttGeneration = UUID()
        pttWatchdog?.cancel()
        pttWatchdog = nil
        isTransmitting = false
        connectionID = UUID()
        pollTimer?.cancel()
        pollTimer = nil
        old?.stateUpdateHandler = nil
        connection = nil
        if wasTransmitting, let reader = replies {
            reader.send("\\stop_morse\nT 0\n", closeAfterRelease: true)
        } else { old?.cancel() }
        replies = nil
        state = .disconnected
        lastMessage = "Rig Control disconnected"
    }

    func refresh() {
        guard state.isConnected else { return }
        send("+f\n+m\n")
    }

    func setFrequencyHz(_ frequencyHz: UInt64) {
        guard state.isConnected, frequencyHz > 0 else { return }
        send("F \(frequencyHz)\n")
        queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refresh() }
    }

    func setMode(_ mode: String, passbandHz: Int = 0) {
        let cleanMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard state.isConnected, !cleanMode.isEmpty, cleanMode.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return }
        send("M \(cleanMode) \(passbandHz)\n")
        queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refresh() }
    }

    /// Keys Hamlib PTT with a hard watchdog so a stalled FT8 task cannot leave
    /// the transmitter on. Calling with `false` is always safe and idempotent.
    func setPTT(_ enabled: Bool, maximumDuration: TimeInterval = TXLimits.rigctldPTT) {
        if enabled {
            guard !TransmitShutdown.isShuttingDown else { return }
            guard state.isConnected else {
                lastMessage = TXLimits.notConnectedMessage(radio: "rigctld")
                return
            }
            if pttWatchdog != nil { return }
        }
        pttGeneration = UUID()
        let generation = pttGeneration
        pttWatchdog?.cancel()
        pttWatchdog = nil
        if !enabled, isTransmitting, !state.isConnected { releaseUncertain("PTT release requested without a working link") }
        send(enabled ? "T 1\n" : "T 0\n")
        isTransmitting = enabled
        lastMessage = enabled ? "PTT active" : "PTT release requested; verify receive on the radio"
        guard enabled else { return }
        let keyedAt = Date(), started = ProcessInfo.processInfo.systemUptime
        let limit = TXLimits.pttSafetyTimer(maximumDuration)
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.pttGeneration == generation, self.isTransmitting else { return }
            self.setPTT(false)
            self.lastMessage = TXLimits.safetyTimerMessage(radio: self.noticeSource.name, keyedAt: keyedAt, limit: limit,
                elapsed: ProcessInfo.processInfo.systemUptime - started)
            TransmitNotices.shared.post(self.noticeSource, text: self.lastMessage)
        }
        pttWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + limit, execute: watchdog)
    }

    // MARK: - Hamlib CAT CW Keying

    /// Sends Morse text directly to transceiver's internal keyer via Hamlib \\send_morse
    func sendMorse(_ text: String) {
        guard state.isConnected else { return }
        guard let clean = MorseTiming.safeText(text) else {
            lastMessage = "Nothing sent: unsupported CW text or message too long."
            return
        }
        send("b \(clean)\n")
        DispatchQueue.main.async {
            self.lastMessage = "Transmitting CW: \(clean)"
        }
    }

    /// Aborts current Morse transmission on transceiver via Hamlib \\stop_morse
    /// ("b" alone is a send_morse with no text: it stops nothing).
    func stopMorse() {
        guard state.isConnected else { return }
        send("\\stop_morse\n")
        DispatchQueue.main.async {
            self.lastMessage = "CW stop requested; radio acknowledgement not verified"
        }
    }

    /// Sets transceiver internal keyer speed in WPM
    func setKeyerSpeed(_ wpm: Int) {
        guard state.isConnected else { return }
        let clamped = max(5, min(60, wpm))
        send("L KEYSPD \(clamped)\n")
    }

    private func handle(_ newState: NWConnection.State, connectionID: UUID, host: String, port: Int) {
        switch newState {
        case .ready:
            DispatchQueue.main.async {
                guard self.connectionID == connectionID else { return }
                self.state = .connected
                self.lastMessage = "Connected to rigctld at \(host):\(port)"
            }
            DispatchQueue.main.async {
                guard self.connectionID == connectionID else { return }
                self.replies?.start()
                self.startPolling()
            }
            refresh()
        case .waiting(let error):
            publishFailure("Waiting for rigctld: \(error.localizedDescription)", connectionID: connectionID)
        case .failed(let error):
            publishFailure(error.localizedDescription, connectionID: connectionID)
        case .cancelled:
            break
        default:
            break
        }
    }

    private func publishFailure(_ message: String, connectionID: UUID) {
        pollTimer?.cancel()
        pollTimer = nil
        DispatchQueue.main.async {
            guard self.connectionID == connectionID else { return }
            self.state = .failed(message)
            self.replies?.fail("the link failed during TX or release: \(message)")
            self.lastMessage = message
        }
    }

    private func startPolling() {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        pollTimer = timer
    }

    private func send(_ command: String) {
        replies?.send(command)
    }
}
