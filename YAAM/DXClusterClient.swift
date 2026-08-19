//
//  DXClusterClient.swift
//  YAAM
//

import Foundation
import Network
import Combine

final class DXClusterClient: ObservableObject {
    @Published private(set) var state: DXClusterConnectionState = .disconnected
    @Published private(set) var spots: [DXSpot] = []
    @Published private(set) var lastMessage = "Ready to connect"
    @Published private(set) var connectedSince: Date?
    @Published private(set) var receivedSpotCount = 0

    private let queue = DispatchQueue(label: "app.yaam.dx-cluster", qos: .userInitiated)
    private var connection: NWConnection?
    private var reconnectWorkItem: DispatchWorkItem?
    private var keepaliveTimer: DispatchSourceTimer?
    private var receiveBuffer = ""
    private var pendingSpots: [DXSpot] = []
    private var flushWorkItem: DispatchWorkItem?
    private var reconnectAttempt = 0
    private var userDisconnected = true
    private var host = ""
    private var port: UInt16 = 0
    private var callsign = ""
    private var connectionID = UUID()

    deinit {
        connection?.cancel()
        keepaliveTimer?.cancel()
        reconnectWorkItem?.cancel()
    }

    func connect(host rawHost: String, port rawPort: Int, callsign rawCallsign: String) {
        let cleanHost = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCallsign = rawCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanHost.isEmpty, (1...65_535).contains(rawPort), !cleanCallsign.isEmpty else {
            state = .failed("Enter a cluster host, port, and station callsign.")
            lastMessage = "Cluster settings are incomplete"
            return
        }

        disconnect(userInitiated: false)
        host = cleanHost
        port = UInt16(rawPort)
        callsign = cleanCallsign
        reconnectAttempt = 0
        userDisconnected = false
        startConnection(isReconnect: false)
    }

    func disconnect(userInitiated: Bool = true) {
        self.userDisconnected = userInitiated
        connectionID = UUID()
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        receiveBuffer = ""
        if userInitiated {
            state = .disconnected
            connectedSince = nil
            lastMessage = "Disconnected"
        }
    }

    func clearSpots() {
        spots.removeAll(keepingCapacity: true)
        receivedSpotCount = 0
    }

    func sendCommand(_ command: String) {
        let line = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        send("\(line)\r\n")
    }

    private func startConnection(isReconnect: Bool) {
        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
            state = .failed("Invalid TCP port")
            return
        }

        let id = UUID()
        connectionID = id
        let connection = NWConnection(host: NWEndpoint.Host(host), port: networkPort, using: .tcp)
        self.connection = connection
        state = isReconnect ? .reconnecting(attempt: reconnectAttempt) : .connecting
        lastMessage = "Opening \(host):\(port)..."

        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            self.queue.async {
                guard self.connectionID == id else { return }
                self.handleConnectionState(newState, connectionID: id)
            }
        }
        connection.start(queue: queue)
    }

    private func handleConnectionState(_ newState: NWConnection.State, connectionID: UUID) {
        switch newState {
        case .ready:
            reconnectAttempt = 0
            DispatchQueue.main.async {
                guard self.connectionID == connectionID else { return }
                self.state = .connected
                self.connectedSince = Date()
                self.lastMessage = "Connected to \(self.host):\(self.port)"
            }
            send("\(callsign)\r\n")
            receiveNext(connectionID: connectionID)
            startKeepalive()

        case .waiting(let error):
            DispatchQueue.main.async {
                guard self.connectionID == connectionID else { return }
                self.lastMessage = "Waiting for network: \(error.localizedDescription)"
            }

        case .failed(let error):
            scheduleReconnect(after: error, connectionID: connectionID)

        case .cancelled:
            if !userDisconnected {
                scheduleReconnect(after: nil, connectionID: connectionID)
            }

        default:
            break
        }
    }

    private func receiveNext(connectionID: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                guard self.connectionID == connectionID else { return }
                if let data, !data.isEmpty {
                    self.consume(data)
                }
                if let error {
                    self.scheduleReconnect(after: error, connectionID: connectionID)
                } else if isComplete {
                    self.scheduleReconnect(after: nil, connectionID: connectionID)
                } else {
                    self.receiveNext(connectionID: connectionID)
                }
            }
        }
    }

    private func consume(_ data: Data) {
        let cleanData = removeTelnetNegotiation(from: data)
        guard let chunk = String(data: cleanData, encoding: .utf8) ?? String(data: cleanData, encoding: .isoLatin1) else { return }
        receiveBuffer.append(chunk)
        receiveBuffer = receiveBuffer
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = receiveBuffer.components(separatedBy: "\n")
        guard lines.count > 1 else { return }
        receiveBuffer = lines.last ?? ""

        for rawLine in lines.dropLast() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.localizedCaseInsensitiveContains("login:") || line.localizedCaseInsensitiveContains("call:") {
                send("\(callsign)\r\n")
            }
            if let spot = DXSpotParser.parse(line: line) {
                enqueue(spot)
            } else if line.localizedCaseInsensitiveContains("welcome") || line.localizedCaseInsensitiveContains("connected") {
                DispatchQueue.main.async { self.lastMessage = line }
            }
        }
    }

    private func enqueue(_ spot: DXSpot) {
        pendingSpots.append(spot)
        guard flushWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let batch = self.pendingSpots
            self.pendingSpots.removeAll(keepingCapacity: true)
            self.flushWorkItem = nil
            DispatchQueue.main.async {
                self.apply(batch)
            }
        }
        flushWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func apply(_ batch: [DXSpot]) {
        guard !batch.isEmpty else { return }
        var updated = spots
        var indexByID = Dictionary(uniqueKeysWithValues: updated.enumerated().map { ($0.element.id, $0.offset) })

        for spot in batch {
            receivedSpotCount += 1
            if let index = indexByID[spot.id], updated.indices.contains(index) {
                updated[index].lastSeenAt = spot.lastSeenAt
                updated[index].comment = spot.comment.isEmpty ? updated[index].comment : spot.comment
                updated[index].grid = spot.grid.isEmpty ? updated[index].grid : spot.grid
                updated[index].spotter = spot.spotter
                updated[index].reportCount += 1
            } else {
                updated.insert(spot, at: 0)
                indexByID = Dictionary(uniqueKeysWithValues: updated.enumerated().map { ($0.element.id, $0.offset) })
            }
        }

        updated.sort { $0.lastSeenAt > $1.lastSeenAt }
        spots = Array(updated.prefix(500))
        lastMessage = "\(receivedSpotCount) spots received"
    }

    private func send(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            self?.queue.async {
                guard let self else { return }
                self.scheduleReconnect(after: error, connectionID: self.connectionID)
            }
        })
    }

    private func scheduleReconnect(after error: Error?, connectionID: UUID) {
        guard self.connectionID == connectionID, !userDisconnected, reconnectWorkItem == nil else { return }
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
        connection?.cancel()
        connection = nil
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), 30)

        DispatchQueue.main.async {
            guard self.connectionID == connectionID else { return }
            self.state = .reconnecting(attempt: self.reconnectAttempt)
            self.connectedSince = nil
            self.lastMessage = error.map { "\($0.localizedDescription). Retry in \(Int(delay))s" } ?? "Connection closed. Retry in \(Int(delay))s"
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connectionID == connectionID, !self.userDisconnected else { return }
            self.reconnectWorkItem = nil
            DispatchQueue.main.async {
                self.startConnection(isReconnect: true)
            }
        }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startKeepalive() {
        keepaliveTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in self?.send("\r\n") }
        timer.resume()
        keepaliveTimer = timer
    }

    private func removeTelnetNegotiation(from data: Data) -> Data {
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if bytes[index] == 255 {
                if index + 1 < bytes.count, bytes[index + 1] == 250 {
                    index += 2
                    while index + 1 < bytes.count, !(bytes[index] == 255 && bytes[index + 1] == 240) {
                        index += 1
                    }
                    index = min(index + 2, bytes.count)
                } else {
                    index = min(index + 3, bytes.count)
                }
            } else {
                output.append(bytes[index])
                index += 1
            }
        }
        return Data(output)
    }
}
