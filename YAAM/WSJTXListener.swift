//
//  WSJTXListener.swift
//  YAAM
//

import Combine
import Foundation
import Network

nonisolated enum WSJTXListenerState: Equatable, Sendable {
    case stopped
    case starting
    case listening(UInt16)
    case failed(String)

    var title: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .listening(let port): return "Listening on UDP \(port)"
        case .failed: return "Listener failed"
        }
    }

    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

nonisolated struct WSJTXStatusSnapshot: Equatable, Sendable {
    var sourceID: String
    var dialFrequencyHz: UInt64
    var mode: String
    var dxCallsign: String
    var report: String
    var transmitting: Bool
    var decoding: Bool
    var ownCallsign: String
    var ownGrid: String
    var dxGrid: String
    var receivedAt: Date

    var frequencyMHz: String {
        AmateurBandPlan.formattedMHz(Double(dialFrequencyHz) / 1_000_000)
    }

    var band: String {
        AmateurBandPlan.band(forMHz: Double(dialFrequencyHz) / 1_000_000) ?? ""
    }
}

nonisolated struct WSJTXLoggedEvent: Identifiable, Equatable, Sendable {
    var id = UUID()
    var sourceID: String
    var adif: String
    var receivedAt = Date()
}

nonisolated struct WSJTXPendingQSO: Identifiable, Equatable, Sendable {
    var id: UUID
    var sourceID: String
    var fields: [String: String]
    var receivedAt: Date
    var isDuplicate: Bool

    var callsign: String { fields["CALL"] ?? "" }
    var band: String { fields["BAND"] ?? "" }
    var mode: String { fields["SUBMODE"] ?? fields["MODE"] ?? "" }
}

nonisolated enum WSJTXPacket: Sendable {
    case heartbeat(sourceID: String)
    case status(WSJTXStatusSnapshot)
    case loggedADIF(WSJTXLoggedEvent)
}

final class WSJTXListener: ObservableObject {
    @Published private(set) var state: WSJTXListenerState = .stopped
    @Published private(set) var lastStatus: WSJTXStatusSnapshot?
    @Published private(set) var loggedEvents: [WSJTXLoggedEvent] = []
    @Published private(set) var packetCount = 0
    @Published private(set) var lastMessage = "Ready to listen for WSJT-X or JTDX"

    private let queue = DispatchQueue(label: "app.yaam.wsjtx-udp", qos: .userInitiated)
    private var listener: NWListener?
    private var peers: [NWConnection] = []
    private var listenerID = UUID()

    deinit {
        listener?.cancel()
        peers.forEach { $0.cancel() }
    }

    func start(port rawPort: Int) {
        guard (1...65_535).contains(rawPort), let port = NWEndpoint.Port(rawValue: UInt16(rawPort)) else {
            state = .failed("Enter a valid UDP port.")
            lastMessage = "WSJT-X UDP port is invalid"
            return
        }

        stop()
        let id = UUID()
        listenerID = id
        do {
            let listener = try NWListener(using: .udp, on: port)
            self.listener = listener
            state = .starting
            lastMessage = "Opening UDP \(rawPort)..."

            listener.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                self.queue.async {
                    guard self.listenerID == id else { return }
                    self.handle(newState, port: UInt16(rawPort), listenerID: id)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.queue.async {
                    guard self.listenerID == id else {
                        connection.cancel()
                        return
                    }
                    self.peers.append(connection)
                    connection.start(queue: self.queue)
                    self.receive(on: connection, listenerID: id)
                }
            }
            listener.start(queue: queue)
        } catch {
            state = .failed(error.localizedDescription)
            lastMessage = error.localizedDescription
        }
    }

    func stop() {
        listenerID = UUID()
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        peers.forEach { $0.cancel() }
        peers.removeAll(keepingCapacity: true)
        state = .stopped
        lastMessage = "WSJT-X listener stopped"
    }

    func removeLoggedEvent(id: UUID) {
        loggedEvents.removeAll { $0.id == id }
    }

    func clearLoggedEvents() {
        loggedEvents.removeAll(keepingCapacity: true)
    }

    private func handle(_ newState: NWListener.State, port: UInt16, listenerID: UUID) {
        switch newState {
        case .ready:
            DispatchQueue.main.async {
                guard self.listenerID == listenerID else { return }
                self.state = .listening(port)
                self.lastMessage = "Waiting for WSJT-X/JTDX packets"
            }
        case .waiting(let error):
            publishFailure("Waiting for UDP socket: \(error.localizedDescription)", listenerID: listenerID)
        case .failed(let error):
            publishFailure(error.localizedDescription, listenerID: listenerID)
        case .cancelled:
            break
        default:
            break
        }
    }

    private func publishFailure(_ message: String, listenerID: UUID) {
        DispatchQueue.main.async {
            guard self.listenerID == listenerID else { return }
            self.state = .failed(message)
            self.lastMessage = message
        }
    }

    private func receive(on connection: NWConnection, listenerID: UUID) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self, let connection else { return }
            self.queue.async {
                guard self.listenerID == listenerID else { return }
                if let data, !data.isEmpty, let packet = WSJTXPacketParser.parse(data) {
                    DispatchQueue.main.async { self.apply(packet) }
                }
                if error == nil {
                    self.receive(on: connection, listenerID: listenerID)
                } else {
                    connection.cancel()
                    self.peers.removeAll { $0 === connection }
                }
            }
        }
    }

    private func apply(_ packet: WSJTXPacket) {
        packetCount += 1
        switch packet {
        case .heartbeat(let sourceID):
            lastMessage = sourceID.isEmpty ? "Heartbeat received" : "\(sourceID) is online"
        case .status(let status):
            lastStatus = status
            let activity = status.transmitting ? "Transmitting" : (status.decoding ? "Decoding" : "Monitoring")
            let target = status.dxCallsign.isEmpty ? "No DX selected" : status.dxCallsign
            lastMessage = "\(activity) · \(target) · \(status.frequencyMHz) MHz"
        case .loggedADIF(let event):
            guard !loggedEvents.contains(where: { $0.adif == event.adif }) else { return }
            loggedEvents.insert(event, at: 0)
            loggedEvents = Array(loggedEvents.prefix(50))
            lastMessage = "New logged QSO received from \(event.sourceID)"
        }
    }
}

nonisolated enum WSJTXPacketParser {
    private static let magic: UInt32 = 0xADBCCBDA

    static func parse(_ data: Data) -> WSJTXPacket? {
        var cursor = DataCursor(data: data)
        guard cursor.readUInt32() == magic,
              cursor.readUInt32() != nil,
              let type = cursor.readUInt32(),
              let sourceID = cursor.readString() else { return nil }

        switch type {
        case 0:
            return .heartbeat(sourceID: sourceID)
        case 1:
            guard let frequency = cursor.readUInt64(),
                  let mode = cursor.readString(),
                  let dxCall = cursor.readString(),
                  let report = cursor.readString(),
                  cursor.readString() != nil,
                  cursor.readBool() != nil,
                  let transmitting = cursor.readBool(),
                  let decoding = cursor.readBool(),
                  cursor.readUInt32() != nil,
                  cursor.readUInt32() != nil,
                  let ownCall = cursor.readString(),
                  let ownGrid = cursor.readString(),
                  let dxGrid = cursor.readString() else { return nil }
            return .status(WSJTXStatusSnapshot(
                sourceID: sourceID,
                dialFrequencyHz: frequency,
                mode: mode,
                dxCallsign: dxCall.uppercased(),
                report: report,
                transmitting: transmitting,
                decoding: decoding,
                ownCallsign: ownCall.uppercased(),
                ownGrid: ownGrid.uppercased(),
                dxGrid: dxGrid.uppercased(),
                receivedAt: Date()
            ))
        case 12:
            guard let adif = cursor.readString(), !adif.isEmpty else { return nil }
            return .loggedADIF(WSJTXLoggedEvent(sourceID: sourceID, adif: adif))
        default:
            return nil
        }
    }
}

nonisolated private struct DataCursor {
    let data: Data
    var offset = 0

    mutating func readUInt32() -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let result = (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
        offset += 4
        return result
    }

    mutating func readUInt64() -> UInt64? {
        guard offset + 8 <= data.count else { return nil }
        var result: UInt64 = 0
        for index in 0..<8 { result = (result << 8) | UInt64(data[offset + index]) }
        offset += 8
        return result
    }

    mutating func readBool() -> Bool? {
        guard offset < data.count else { return nil }
        let result = data[offset] != 0
        offset += 1
        return result
    }

    mutating func readString() -> String? {
        guard let length = readUInt32() else { return nil }
        if length == UInt32.max { return "" }
        guard length <= Int.max, offset + Int(length) <= data.count else { return nil }
        let range = offset..<(offset + Int(length))
        offset += Int(length)
        return String(data: data[range], encoding: .utf8) ?? ""
    }
}
