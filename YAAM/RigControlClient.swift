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
    @Published private(set) var state: RigConnectionState = .disconnected
    @Published private(set) var snapshot: RigSnapshot?
    @Published private(set) var isTransmitting = false
    @Published private(set) var lastMessage = "Ready to connect to rigctld"

    private let queue = DispatchQueue(label: "app.yaam.rig-control", qos: .userInitiated)
    private var connection: NWConnection?
    private var pollTimer: DispatchSourceTimer?
    private var receiveBuffer = ""
    private var connectionID = UUID()
    private var pendingFrequency: UInt64?
    private var pendingMode = ""
    private var pendingPassband: Int?
    private var pttWatchdog: DispatchWorkItem?

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
        let id = UUID()
        connectionID = id
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        self.connection = connection
        state = .connecting
        lastMessage = "Opening \(host):\(rawPort)..."

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
        if isTransmitting { send("T 0\n") }
        pttWatchdog?.cancel()
        pttWatchdog = nil
        isTransmitting = false
        connectionID = UUID()
        pollTimer?.cancel()
        pollTimer = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        receiveBuffer = ""
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
        guard state.isConnected, !cleanMode.isEmpty else { return }
        send("M \(cleanMode) \(passbandHz)\n")
        queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refresh() }
    }

    /// Keys Hamlib PTT with a hard watchdog so a stalled FT8 task cannot leave
    /// the transmitter on. Calling with `false` is always safe and idempotent.
    func setPTT(_ enabled: Bool, maximumDuration: TimeInterval = 14) {
        guard state.isConnected else {
            if !enabled { isTransmitting = false }
            return
        }

        pttWatchdog?.cancel()
        pttWatchdog = nil
        send(enabled ? "T 1\n" : "T 0\n")
        isTransmitting = enabled
        lastMessage = enabled ? "PTT active" : "PTT released"

        guard enabled else { return }
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.isTransmitting else { return }
            self.send("T 0\n")
            DispatchQueue.main.async {
                self.isTransmitting = false
                self.lastMessage = "PTT released by safety timer"
            }
        }
        pttWatchdog = watchdog
        queue.asyncAfter(deadline: .now() + max(1, maximumDuration), execute: watchdog)
    }

    private func handle(_ newState: NWConnection.State, connectionID: UUID, host: String, port: Int) {
        switch newState {
        case .ready:
            DispatchQueue.main.async {
                guard self.connectionID == connectionID else { return }
                self.state = .connected
                self.lastMessage = "Connected to rigctld at \(host):\(port)"
            }
            receiveNext(connectionID: connectionID)
            startPolling()
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

    private func receiveNext(connectionID: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1_024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                guard self.connectionID == connectionID else { return }
                if let data, !data.isEmpty { self.consume(data) }
                if let error {
                    self.publishFailure(error.localizedDescription, connectionID: connectionID)
                } else if isComplete {
                    self.publishFailure("rigctld closed the connection", connectionID: connectionID)
                } else {
                    self.receiveNext(connectionID: connectionID)
                }
            }
        }
    }

    private func consume(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        receiveBuffer.append(chunk.replacingOccurrences(of: "\r\n", with: "\n"))
        let lines = receiveBuffer.components(separatedBy: "\n")
        guard lines.count > 1 else { return }
        receiveBuffer = lines.last ?? ""

        for rawLine in lines.dropLast() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            consume(line: line)
        }
    }

    private func consume(line: String) {
        if line.hasPrefix("Frequency:"), let value = UInt64(line.dropFirst("Frequency:".count).trimmingCharacters(in: .whitespaces)) {
            pendingFrequency = value
        } else if line.hasPrefix("Mode:") {
            pendingMode = String(line.dropFirst("Mode:".count)).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        } else if line.hasPrefix("Passband:") {
            pendingPassband = Int(line.dropFirst("Passband:".count).trimmingCharacters(in: .whitespaces))
        } else if let frequency = UInt64(line), frequency > 0 {
            pendingFrequency = frequency
        }

        guard let frequency = pendingFrequency else { return }
        let mode = pendingMode.isEmpty ? (snapshot?.mode ?? "") : pendingMode
        let next = RigSnapshot(
            frequencyHz: frequency,
            mode: mode,
            passbandHz: pendingPassband,
            updatedAt: Date()
        )
        DispatchQueue.main.async {
            self.snapshot = next
            self.lastMessage = [next.band, next.frequencyMHz + " MHz", next.mode]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
    }

    private func send(_ command: String) {
        guard let data = command.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error, let self else { return }
            self.queue.async {
                self.publishFailure(error.localizedDescription, connectionID: self.connectionID)
            }
        })
    }
}
