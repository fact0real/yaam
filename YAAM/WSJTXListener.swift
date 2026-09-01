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

nonisolated struct WSJTXLiveDecode: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var sourceID: String
    public var isNew: Bool
    public var timeMillis: UInt32
    public var snr: Int32
    public var deltaTimeSec: Double
    public var deltaFrequencyHz: UInt32
    public var mode: String
    public var message: String
    public var lowConfidence: Bool
    public var offAir: Bool
    public var receivedAt: Date

    // Extracted amateur radio metadata
    public var callerCallsign: String
    public var targetCallsign: String
    public var grid: String
    public var report: String
}

nonisolated enum WSJTXPacket: Sendable {
    case heartbeat(sourceID: String)
    case status(WSJTXStatusSnapshot)
    case decode(WSJTXLiveDecode)
    case loggedADIF(WSJTXLoggedEvent)
}

final class WSJTXListener: ObservableObject {
    @Published private(set) var state: WSJTXListenerState = .stopped
    @Published private(set) var lastStatus: WSJTXStatusSnapshot?
    @Published private(set) var loggedEvents: [WSJTXLoggedEvent] = []
    @Published private(set) var liveDecodes: [WSJTXLiveDecode] = []
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

            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self, self.listenerID == id else { return }
                    switch state {
                    case .ready:
                        self.state = .listening(port.rawValue)
                        self.lastMessage = "Listening for WSJT-X on UDP \(port.rawValue)"
                    case .failed(let error):
                        self.state = .failed(error.localizedDescription)
                        self.lastMessage = "UDP listener failed: \(error.localizedDescription)"
                    case .cancelled:
                        if case .starting = self.state {
                            self.state = .stopped
                        }
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection, listenerID: id)
            }

            listener.start(queue: queue)
        } catch {
            state = .failed(error.localizedDescription)
            lastMessage = "Could not start UDP listener: \(error.localizedDescription)"
        }
    }

    func stop() {
        listenerID = UUID()
        listener?.cancel()
        listener = nil
        peers.forEach { $0.cancel() }
        peers.removeAll()
        state = .stopped
        lastMessage = "WSJT-X listener stopped"
    }

    func removeLoggedEvent(id: UUID) {
        loggedEvents.removeAll { $0.id == id }
    }

    func clearLoggedEvents() {
        loggedEvents.removeAll(keepingCapacity: true)
    }

    private func handle(_ connection: NWConnection, listenerID: UUID) {
        peers.append(connection)
        connection.start(queue: queue)
        receiveNextPacket(on: connection, listenerID: listenerID)
    }

    private func receiveNextPacket(on connection: NWConnection, listenerID: UUID) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, self.listenerID == listenerID else {
                connection.cancel()
                return
            }

            if let data, !data.isEmpty, let packet = WSJTXPacketParser.parse(data) {
                DispatchQueue.main.async {
                    self.apply(packet)
                }
            }

            if error == nil {
                self.receiveNextPacket(on: connection, listenerID: listenerID)
            } else {
                connection.cancel()
                self.peers.removeAll { $0 === connection }
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
        case .decode(let decode):
            liveDecodes.insert(decode, at: 0)
            let cutoff = Date().addingTimeInterval(-300) // Keep last 5 minutes of decodes
            liveDecodes = Array(liveDecodes.filter { $0.receivedAt > cutoff }.prefix(200))
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
        case 2:
            // Decode packet
            guard let isNew = cursor.readBool(),
                  let timeMillis = cursor.readUInt32(),
                  let snr = cursor.readInt32(),
                  let deltaTime = cursor.readDouble(),
                  let deltaFreq = cursor.readUInt32(),
                  let mode = cursor.readString(),
                  let message = cursor.readString(),
                  let lowConf = cursor.readBool(),
                  let offAir = cursor.readBool() else { return nil }

            let cleanMsg = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsed = parseMessageTokens(cleanMsg)

            return .decode(WSJTXLiveDecode(
                sourceID: sourceID,
                isNew: isNew,
                timeMillis: timeMillis,
                snr: snr,
                deltaTimeSec: deltaTime,
                deltaFrequencyHz: deltaFreq,
                mode: mode,
                message: cleanMsg,
                lowConfidence: lowConf,
                offAir: offAir,
                receivedAt: Date(),
                callerCallsign: parsed.caller,
                targetCallsign: parsed.target,
                grid: parsed.grid,
                report: parsed.report
            ))
        case 12:
            guard let adif = cursor.readString(), !adif.isEmpty else { return nil }
            return .loggedADIF(WSJTXLoggedEvent(sourceID: sourceID, adif: adif))
        default:
            return nil
        }
    }

    private static func parseMessageTokens(_ msg: String) -> (caller: String, target: String, grid: String, report: String) {
        let tokens = msg.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return ("", "", "", "") }

        // CQ [DX/POTA/NA] CALL GRID
        if tokens[0].uppercased() == "CQ" {
            if tokens.count >= 3 {
                let call = tokens[1].uppercased().count > 2 ? tokens[1].uppercased() : (tokens.count >= 3 ? tokens[2].uppercased() : "")
                let grid = tokens.last!.uppercased()
                let validGrid = isGrid4(grid) ? grid : ""
                return (call, "", validGrid, "")
            }
        }

        // CALL1 CALL2 [GRID / REPORT / RRR / 73]
        if tokens.count >= 2 {
            let target = tokens[0].uppercased()
            let caller = tokens[1].uppercased()
            var grid = ""
            var report = ""
            if tokens.count >= 3 {
                let third = tokens[2].uppercased()
                if isGrid4(third) {
                    grid = third
                } else {
                    report = third
                }
            }
            return (caller, target, grid, report)
        }

        return ("", "", "", "")
    }

    private static func isGrid4(_ text: String) -> Bool {
        guard text.count == 4 else { return false }
        let chars = Array(text.uppercased())
        return chars[0] >= "A" && chars[0] <= "R" &&
               chars[1] >= "A" && chars[1] <= "R" &&
               chars[2] >= "0" && chars[2] <= "9" &&
               chars[3] >= "0" && chars[3] <= "9"
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

    mutating func readInt32() -> Int32? {
        guard let u = readUInt32() else { return nil }
        return Int32(bitPattern: u)
    }

    mutating func readDouble() -> Double? {
        guard let u = readUInt64() else { return nil }
        return Double(bitPattern: u)
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
