//
//  WSJTXListener.swift
//  YAAM
//
//  Bi-directional Live WSJT-X / JTDX UDP Protocol Service.
//  Supports full 2-way communication: 1-click Reply (Type 4), Halt TX (Type 7),
//  Clear Activity (Type 3), Set Location (Type 9), and high-performance live decodes stream.
//

import Combine
import Foundation
import Network
import SwiftUI

// MARK: - Listener State

nonisolated public enum WSJTXListenerState: Equatable, Sendable {
    case stopped
    case starting
    case listening(UInt16)
    case failed(String)

    public var title: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .listening(let port): return "Listening on UDP \(port)"
        case .failed(let err): return "Listener failed: \(err)"
        }
    }

    public var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

// MARK: - Status Snapshot

nonisolated public struct WSJTXStatusSnapshot: Equatable, Sendable {
    public var sourceID: String
    public var dialFrequencyHz: UInt64
    public var mode: String
    public var dxCallsign: String
    public var report: String
    public var transmitting: Bool
    public var decoding: Bool
    public var ownCallsign: String
    public var ownGrid: String
    public var dxGrid: String
    public var receivedAt: Date

    public var frequencyMHz: String {
        AmateurBandPlan.formattedMHz(Double(dialFrequencyHz) / 1_000_000)
    }

    public var band: String {
        AmateurBandPlan.band(forMHz: Double(dialFrequencyHz) / 1_000_000) ?? ""
    }
}

// MARK: - Logged Event & Pending QSO

nonisolated public struct WSJTXLoggedEvent: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var sourceID: String
    public var adif: String
    public var receivedAt = Date()

    public init(id: UUID = UUID(), sourceID: String, adif: String, receivedAt: Date = Date()) {
        self.id = id
        self.sourceID = sourceID
        self.adif = adif
        self.receivedAt = receivedAt
    }
}

nonisolated public struct WSJTXPendingQSO: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var sourceID: String
    public var fields: [String: String]
    public var receivedAt: Date
    public var isDuplicate: Bool

    public var callsign: String { fields["CALL"] ?? "" }
    public var band: String { fields["BAND"] ?? "" }
    public var mode: String { fields["SUBMODE"] ?? fields["MODE"] ?? "" }

    public init(id: UUID, sourceID: String, fields: [String: String], receivedAt: Date, isDuplicate: Bool) {
        self.id = id
        self.sourceID = sourceID
        self.fields = fields
        self.receivedAt = receivedAt
        self.isDuplicate = isDuplicate
    }
}

// MARK: - Live Decode Model

nonisolated public struct WSJTXLiveDecode: Identifiable, Equatable, Sendable {
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
    public var port: Int
    public var sliceLabel: String

    public init(
        id: UUID = UUID(),
        sourceID: String,
        isNew: Bool,
        timeMillis: UInt32,
        snr: Int32,
        deltaTimeSec: Double,
        deltaFrequencyHz: UInt32,
        mode: String,
        message: String,
        lowConfidence: Bool,
        offAir: Bool,
        receivedAt: Date = Date(),
        callerCallsign: String,
        targetCallsign: String,
        grid: String,
        report: String,
        port: Int = 2237,
        sliceLabel: String = "VFO A"
    ) {
        self.id = id
        self.sourceID = sourceID
        self.isNew = isNew
        self.timeMillis = timeMillis
        self.snr = snr
        self.deltaTimeSec = deltaTimeSec
        self.deltaFrequencyHz = deltaFrequencyHz
        self.mode = mode
        self.message = message
        self.lowConfidence = lowConfidence
        self.offAir = offAir
        self.receivedAt = receivedAt
        self.callerCallsign = callerCallsign
        self.targetCallsign = targetCallsign
        self.grid = grid
        self.report = report
        self.port = port
        self.sliceLabel = sliceLabel
    }

    // Computed Properties
    public var isCQ: Bool {
        let u = message.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return u.hasPrefix("CQ ") || u.contains(" CQ ") || u == "CQ"
    }

    public func isDirectedToMe(myCall: String) -> Bool {
        guard !myCall.isEmpty else { return false }
        let cleanMy = myCall.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTarget = targetCallsign.uppercased()
        if cleanTarget == cleanMy { return true }
        let tokens = message.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if tokens.count >= 2 && tokens[0].uppercased() == cleanMy { return true }
        return false
    }

    public var timeUTCString: String {
        let totalSeconds = timeMillis / 1000
        let hours = (totalSeconds / 3600) % 24
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    public var snrFormatted: String {
        snr >= 0 ? "+\(snr) dB" : "\(snr) dB"
    }

    public var deltaFrequencyFormatted: String {
        "\(deltaFrequencyHz) Hz"
    }

    public var deltaTimeFormatted: String {
        String(format: "%+.1fs", deltaTimeSec)
    }

    public var countryInfo: (flag: String, country: String) {
        let call = callerCallsign.isEmpty ? targetCallsign : callerCallsign
        guard !call.isEmpty else { return ("🌐", "Unknown") }
        let res = DXCCDatabase.resolve(callsign: call)
        return (res.flagEmoji, res.entityName)
    }

    public var snrColor: Color {
        switch snr {
        case 0...: return Color.green
        case -10 ..< 0: return Color.yellow
        case -18 ..< -10: return Color.orange
        default: return Color.red
        }
    }

    @MainActor
    public func contestStatus(engine: DigitalContestEngine, onBand band: String) -> DecodedContestStatus {
        let call = callerCallsign.isEmpty ? targetCallsign : callerCallsign
        return engine.analyzeDecodedStation(callsign: call, grid: grid, band: band)
    }
}

// MARK: - Inbound Packet Types

nonisolated public enum WSJTXPacket: Sendable {
    case heartbeat(sourceID: String)
    case status(WSJTXStatusSnapshot)
    case decode(WSJTXLiveDecode)
    case clear(sourceID: String, window: UInt8)
    case loggedADIF(WSJTXLoggedEvent)
}

// MARK: - Outbound Qt Packet Writer

public struct WSJTXPacketWriter {
    public private(set) var data = Data()

    public init() {}

    public mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
    }

    public mutating func writeUInt16(_ value: UInt16) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    public mutating func writeUInt32(_ value: UInt32) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    public mutating func writeInt32(_ value: Int32) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    public mutating func writeUInt64(_ value: UInt64) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    public mutating func writeDouble(_ value: Double) {
        var bitPattern = value.bitPattern.bigEndian
        withUnsafeBytes(of: &bitPattern) { data.append(contentsOf: $0) }
    }

    public mutating func writeBool(_ value: Bool) {
        data.append(value ? 1 : 0)
    }

    public mutating func writeString(_ string: String) {
        let utf8 = Data(string.utf8)
        writeUInt32(UInt32(utf8.count))
        data.append(utf8)
    }

    public mutating func writeQColor(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        // Qt QColor serialization
        writeUInt8(1) // RGB spec
        writeUInt16((UInt16(alpha) << 8) | UInt16(alpha))
        writeUInt16((UInt16(red) << 8) | UInt16(red))
        writeUInt16((UInt16(green) << 8) | UInt16(green))
        writeUInt16((UInt16(blue) << 8) | UInt16(blue))
        writeUInt16(0) // Pad
    }

    public func build() -> Data {
        data
    }
}

// MARK: - Outbound WSJT-X Packet Encoder

public enum WSJTXPacketEncoder {
    public static let magic: UInt32 = 0xADBCCBDA
    public static let schemaVersion: UInt32 = 2

    // Type 4: Reply
    public static func encodeReply(
        clientID: String,
        timeMillis: UInt32,
        snr: Int32,
        deltaTimeSec: Double,
        deltaFrequencyHz: UInt32,
        mode: String,
        message: String,
        lowConfidence: Bool = false,
        modifiers: UInt8 = 0
    ) -> Data {
        var writer = WSJTXPacketWriter()
        writer.writeUInt32(magic)
        writer.writeUInt32(schemaVersion)
        writer.writeUInt32(4) // Type 4: Reply
        writer.writeString(clientID)
        writer.writeUInt32(timeMillis)
        writer.writeInt32(snr)
        writer.writeDouble(deltaTimeSec)
        writer.writeUInt32(deltaFrequencyHz)
        writer.writeString(mode)
        writer.writeString(message)
        writer.writeBool(lowConfidence)
        writer.writeUInt8(modifiers)
        return writer.build()
    }

    // Type 7: Halt TX
    public static func encodeHaltTx(
        clientID: String,
        autoTxOnly: Bool = false
    ) -> Data {
        var writer = WSJTXPacketWriter()
        writer.writeUInt32(magic)
        writer.writeUInt32(schemaVersion)
        writer.writeUInt32(7) // Type 7: Halt TX
        writer.writeString(clientID)
        writer.writeBool(autoTxOnly)
        return writer.build()
    }

    // Type 8: Free Text
    public static func encodeFreeText(
        clientID: String,
        text: String,
        sendImmediately: Bool = true
    ) -> Data {
        var writer = WSJTXPacketWriter()
        writer.writeUInt32(magic)
        writer.writeUInt32(schemaVersion)
        writer.writeUInt32(8) // Type 8: Free Text
        writer.writeString(clientID)
        writer.writeString(text)
        writer.writeBool(sendImmediately)
        return writer.build()
    }

    // Type 9: Location
    public static func encodeSetLocation(
        clientID: String,
        location: String
    ) -> Data {
        var writer = WSJTXPacketWriter()
        writer.writeUInt32(magic)
        writer.writeUInt32(schemaVersion)
        writer.writeUInt32(9) // Type 9: Location
        writer.writeString(clientID)
        writer.writeString(location)
        return writer.build()
    }

    // Type 3: Clear
    public static func encodeClear(
        clientID: String,
        window: UInt8 = 2
    ) -> Data {
        var writer = WSJTXPacketWriter()
        writer.writeUInt32(magic)
        writer.writeUInt32(schemaVersion)
        writer.writeUInt32(3) // Type 3: Clear
        writer.writeString(clientID)
        writer.writeUInt8(window)
        return writer.build()
    }

    // Type 13: Highlight Callsign
    public static func encodeHighlightCallsign(
        clientID: String,
        callsign: String,
        bgRGB: (UInt8, UInt8, UInt8) = (255, 255, 0),
        fgRGB: (UInt8, UInt8, UInt8) = (0, 0, 0),
        highlightLast: Bool = false
    ) -> Data {
        var writer = WSJTXPacketWriter()
        writer.writeUInt32(magic)
        writer.writeUInt32(schemaVersion)
        writer.writeUInt32(13) // Type 13: Highlight Callsign
        writer.writeString(clientID)
        writer.writeString(callsign)
        writer.writeQColor(red: bgRGB.0, green: bgRGB.1, blue: bgRGB.2)
        writer.writeQColor(red: fgRGB.0, green: fgRGB.1, blue: fgRGB.2)
        writer.writeBool(highlightLast)
        return writer.build()
    }
}

// MARK: - WSJTX Listener & 2-Way Controller

final public class WSJTXListener: ObservableObject {
    @Published public private(set) var state: WSJTXListenerState = .stopped
    @Published public private(set) var lastStatus: WSJTXStatusSnapshot?
    @Published public private(set) var loggedEvents: [WSJTXLoggedEvent] = []
    @Published public private(set) var liveDecodes: [WSJTXLiveDecode] = []
    @Published public private(set) var packetCount = 0
    @Published public private(set) var lastMessage = "Ready to listen for WSJT-X or JTDX"
    @Published public private(set) var lastSentCommand = ""
    @Published public private(set) var activeReplyDecode: WSJTXLiveDecode? = nil
    @Published public private(set) var activeReplyToast: String? = nil

    private let queue = DispatchQueue(label: "app.yaam.wsjtx-udp", qos: .userInitiated)
    private var listener: NWListener?
    private var peers: [NWConnection] = []
    private var listenerID = UUID()
    public var currentPort: Int = 2237

    public init() {}

    deinit {
        listener?.cancel()
        peers.forEach { $0.cancel() }
    }

    @AppStorage("multiSliceEnabled") public var multiSliceEnabled: Bool = true
    @AppStorage("secondaryPort") public var secondaryPort: Int = 2238
    private var secondaryListener: NWListener?

    // MARK: - Lifecycle

    public func start(port rawPort: Int) {
        guard (1...65_535).contains(rawPort), let port = NWEndpoint.Port(rawValue: UInt16(rawPort)) else {
            state = .failed("Enter a valid UDP port.")
            lastMessage = "WSJT-X UDP port is invalid"
            return
        }

        currentPort = rawPort
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
                        let portDesc = self.multiSliceEnabled ? "\(port.rawValue) & \(self.secondaryPort)" : "\(port.rawValue)"
                        self.state = .listening(port.rawValue)
                        self.lastMessage = "Listening for WSJT-X on UDP \(portDesc)"
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
                self?.handle(connection, listenerID: id, port: rawPort)
            }

            listener.start(queue: queue)

            // Multi-slice secondary listener (e.g. port 2238 for VFO B)
            if multiSliceEnabled && secondaryPort != rawPort {
                if let secEndpointPort = NWEndpoint.Port(rawValue: UInt16(secondaryPort)) {
                    do {
                        let secListener = try NWListener(using: .udp, on: secEndpointPort)
                        self.secondaryListener = secListener
                        secListener.newConnectionHandler = { [weak self] connection in
                            self?.handle(connection, listenerID: id, port: self?.secondaryPort ?? 2238)
                        }
                        secListener.start(queue: queue)
                    } catch {
                        // Secondary listener optional
                    }
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
            lastMessage = "Could not start UDP listener: \(error.localizedDescription)"
        }
    }

    public func stop() {
        listenerID = UUID()
        listener?.cancel()
        listener = nil
        secondaryListener?.cancel()
        secondaryListener = nil
        peers.forEach { $0.cancel() }
        peers.removeAll()
        state = .stopped
        lastMessage = "WSJT-X listener stopped"
    }

    public func clearLiveDecodes() {
        liveDecodes.removeAll(keepingCapacity: true)
    }

    public func removeLoggedEvent(id: UUID) {
        loggedEvents.removeAll { $0.id == id }
    }

    public func clearLoggedEvents() {
        loggedEvents.removeAll(keepingCapacity: true)
    }

    // MARK: - 2-Way Command Dispatching to WSJT-X

    /// Sends a 1-click Reply (Type 4) packet to WSJT-X/JTDX
    public func sendReply(
        to decode: WSJTXLiveDecode,
        host: String = "127.0.0.1",
        port: Int = 2237
    ) {
        let clientID = decode.sourceID.isEmpty ? (lastStatus?.sourceID ?? "WSJT-X") : decode.sourceID
        let packetData = WSJTXPacketEncoder.encodeReply(
            clientID: clientID,
            timeMillis: decode.timeMillis,
            snr: decode.snr,
            deltaTimeSec: decode.deltaTimeSec,
            deltaFrequencyHz: decode.deltaFrequencyHz,
            mode: decode.mode,
            message: decode.message,
            lowConfidence: decode.lowConfidence,
            modifiers: 0
        )

        dispatchPacket(packetData, targetHost: host, targetPort: port)

        let targetCall = decode.callerCallsign.isEmpty ? decode.targetCallsign : decode.callerCallsign
        activeReplyDecode = decode
        let toast = "Replying to \(targetCall) on \(decode.deltaFrequencyHz) Hz in \(clientID)"
        activeReplyToast = toast
        lastSentCommand = "Reply: \(decode.message)"
        lastMessage = toast

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            if self?.activeReplyToast == toast {
                self?.activeReplyToast = nil
            }
        }
    }

    /// Sends a Halt TX (Type 7) packet to stop transmission immediately
    public func sendHaltTx(
        clientID: String? = nil,
        autoTxOnly: Bool = false,
        host: String = "127.0.0.1",
        port: Int = 2237
    ) {
        let targetID = clientID ?? lastStatus?.sourceID ?? "WSJT-X"
        let data = WSJTXPacketEncoder.encodeHaltTx(clientID: targetID, autoTxOnly: autoTxOnly)
        dispatchPacket(data, targetHost: host, targetPort: port)
        lastSentCommand = "Halt TX (\(targetID))"
        lastMessage = "Sent Halt TX to \(targetID)"
    }

    /// Sends a Clear (Type 3) packet to clear band activity window in WSJT-X
    public func sendClear(
        clientID: String? = nil,
        window: UInt8 = 2,
        host: String = "127.0.0.1",
        port: Int = 2237
    ) {
        let targetID = clientID ?? lastStatus?.sourceID ?? "WSJT-X"
        let data = WSJTXPacketEncoder.encodeClear(clientID: targetID, window: window)
        dispatchPacket(data, targetHost: host, targetPort: port)
        lastSentCommand = "Clear Window (\(targetID))"
        lastMessage = "Sent Clear Window to \(targetID)"
    }

    /// Sends a Location / Grid (Type 9) packet to synchronize operator grid in WSJT-X
    public func sendSetLocation(
        grid: String,
        clientID: String? = nil,
        host: String = "127.0.0.1",
        port: Int = 2237
    ) {
        let cleanGrid = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanGrid.isEmpty else { return }
        let targetID = clientID ?? lastStatus?.sourceID ?? "WSJT-X"
        let data = WSJTXPacketEncoder.encodeSetLocation(clientID: targetID, location: cleanGrid)
        dispatchPacket(data, targetHost: host, targetPort: port)
        lastSentCommand = "Set Location: \(cleanGrid) (\(targetID))"
        lastMessage = "Synchronized Grid \(cleanGrid) with \(targetID)"
    }

    /// Sends Free Text (Type 8) to WSJT-X
    public func sendFreeText(
        text: String,
        sendImmediately: Bool = true,
        clientID: String? = nil,
        host: String = "127.0.0.1",
        port: Int = 2237
    ) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        let targetID = clientID ?? lastStatus?.sourceID ?? "WSJT-X"
        let data = WSJTXPacketEncoder.encodeFreeText(clientID: targetID, text: cleanText, sendImmediately: sendImmediately)
        dispatchPacket(data, targetHost: host, targetPort: port)
        lastSentCommand = "Free Text: \(cleanText)"
        lastMessage = "Sent Free Text to \(targetID)"
    }

    // MARK: - Internal Packet Dispatcher

    private func dispatchPacket(_ data: Data, targetHost: String, targetPort: Int) {
        // 1. Send via all active peer connections
        for peer in peers {
            peer.send(content: data, completion: .contentProcessed { error in
                if let error {
                    print("WSJT-X peer send warning: \(error)")
                }
            })
        }

        // 2. Also send via outbound UDP connection to ensure reachability
        guard let port = NWEndpoint.Port(rawValue: UInt16(targetPort)) else { return }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(targetHost), port: port)
        let outbound = NWConnection(to: endpoint, using: .udp)
        outbound.stateUpdateHandler = { state in
            switch state {
            case .ready:
                outbound.send(content: data, completion: .contentProcessed { _ in
                    outbound.cancel()
                })
            case .failed, .cancelled:
                outbound.cancel()
            default:
                break
            }
        }
        outbound.start(queue: queue)
    }

    // MARK: - Inbound Message Handling

    private func handle(_ connection: NWConnection, listenerID: UUID, port: Int = 2237) {
        peers.append(connection)
        connection.start(queue: queue)
        receiveNextPacket(on: connection, listenerID: listenerID, port: port)
    }

    private func receiveNextPacket(on connection: NWConnection, listenerID: UUID, port: Int = 2237) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, self.listenerID == listenerID else {
                connection.cancel()
                return
            }

            if let data, !data.isEmpty, let packet = WSJTXPacketParser.parse(data, port: port) {
                DispatchQueue.main.async {
                    self.apply(packet)
                }
            }

            if error == nil {
                self.receiveNextPacket(on: connection, listenerID: listenerID, port: port)
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
            let cutoff = Date().addingTimeInterval(-600) // Keep last 10 minutes of decodes
            liveDecodes = Array(liveDecodes.filter { $0.receivedAt > cutoff }.prefix(500))

            // Ingest real-time decode into BandmapEngine
            let dialHz = lastStatus?.dialFrequencyHz ?? 0
            let targetCall = !decode.callerCallsign.isEmpty ? decode.callerCallsign : (!decode.targetCallsign.isEmpty ? decode.targetCallsign : "")
            if dialHz > 0 && !targetCall.isEmpty {
                let exactKHz = Double(dialHz + UInt64(decode.deltaFrequencyHz)) / 1000.0
                let resolvedBand = lastStatus?.band ?? AmateurBandPlan.band(forMHz: exactKHz / 1000.0) ?? "20M"
                BandmapEngine.shared.addSpot(
                    callsign: targetCall,
                    frequencyKHz: exactKHz,
                    band: resolvedBand,
                    mode: decode.mode.isEmpty ? "FT8" : decode.mode,
                    comment: decode.grid.isEmpty ? "" : "Grid: \(decode.grid)",
                    source: "WSJT-X (\(decode.sourceID))",
                    snr: Int(decode.snr)
                )
            }
        case .clear(let sourceID, _):
            lastMessage = "Clear command received from \(sourceID)"
        case .loggedADIF(let event):
            guard !loggedEvents.contains(where: { $0.adif == event.adif }) else { return }
            loggedEvents.insert(event, at: 0)
            loggedEvents = Array(loggedEvents.prefix(100))
            lastMessage = "New logged QSO received from \(event.sourceID)"
        }
    }
}

// MARK: - Inbound Packet Parser

nonisolated public enum WSJTXPacketParser {
    public static let magic: UInt32 = 0xADBCCBDA

    public static func parse(_ data: Data, port: Int = 2237) -> WSJTXPacket? {
        var cursor = DataCursor(data: data)
        guard cursor.readUInt32() == magic,
              cursor.readUInt32() != nil, // Schema
              let type = cursor.readUInt32(),
              let sourceID = cursor.readString() else { return nil }

        switch type {
        case 0:
            return .heartbeat(sourceID: sourceID)
        case 1:
            guard let dialFreq = cursor.readUInt64(),
                  let mode = cursor.readString(),
                  let dxCall = cursor.readString(),
                  let report = cursor.readString(),
                  let txMode = cursor.readString(),
                  let txEnabled = cursor.readBool(),
                  let transmitting = cursor.readBool(),
                  let decoding = cursor.readBool(),
                  let _ = cursor.readUInt32(), // rxDF
                  let _ = cursor.readUInt32(), // txDF
                  let _ = cursor.readString(), // deCall
                  let _ = cursor.readString(), // deGrid
                  let dxGrid = cursor.readString(),
                  let _ = cursor.readBool(), // watchdog
                  let _ = cursor.readString(), // subMode
                  let _ = cursor.readBool(), // fastMode
                  let _ = cursor.readUInt8(), // specialOp
                  let _ = cursor.readUInt32(), // freqTolerance
                  let _ = cursor.readUInt32(), // trPeriod
                  let _ = cursor.readString() // configName
            else { return nil }

            let ownCall = cursor.readString() ?? ""
            let ownGrid = cursor.readString() ?? ""

            return .status(WSJTXStatusSnapshot(
                sourceID: sourceID,
                dialFrequencyHz: dialFreq,
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
            let sliceLabel = (port == 2238 || sourceID.contains("VFO-B") || sourceID.contains("Slice 2")) ? "VFO B" : (port == 2237 ? "VFO A" : "Port \(port)")

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
                report: parsed.report,
                port: port,
                sliceLabel: sliceLabel
            ))
        case 3:
            let window = cursor.readUInt8() ?? 2
            return .clear(sourceID: sourceID, window: window)
        case 12:
            guard let adif = cursor.readString(), !adif.isEmpty else { return nil }
            return .loggedADIF(WSJTXLoggedEvent(sourceID: sourceID, adif: adif))
        default:
            return nil
        }
    }

    public static func parseMessageTokens(_ msg: String) -> (caller: String, target: String, grid: String, report: String) {
        let tokens = msg.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return ("", "", "", "") }

        // 1. CQ patterns
        if tokens[0].uppercased() == "CQ" {
            if tokens.count == 2 {
                // e.g. CQ EP2LMA
                return (tokens[1].uppercased(), "", "", "")
            } else if tokens.count == 3 {
                // e.g. CQ EP2LMA KM32
                let call = tokens[1].uppercased()
                let last = tokens[2].uppercased()
                let grid = isMaidenheadGrid(last) ? last : ""
                return (call, "", grid, "")
            } else if tokens.count >= 4 {
                // e.g. CQ DX EP2LMA KM32 or CQ TEST EP2LMA KM32
                let call = tokens[2].uppercased()
                let last = tokens.last!.uppercased()
                let grid = isMaidenheadGrid(last) ? last : ""
                return (call, "", grid, "")
            }
        }

        // 2. Direct QSO patterns: TARGET CALLSIGN [GRID / REPORT / 73]
        if tokens.count >= 2 {
            let target = tokens[0].uppercased()
            let caller = tokens[1].uppercased()
            var grid = ""
            var report = ""
            if tokens.count >= 3 {
                let third = tokens[2].uppercased()
                if isMaidenheadGrid(third) {
                    grid = third
                } else {
                    report = third
                }
            }
            return (caller, target, grid, report)
        }

        return ("", "", "", "")
    }

    public static func isMaidenheadGrid(_ text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count == 4 || clean.count == 6 else { return false }
        let chars = Array(clean)
        guard chars[0] >= "A" && chars[0] <= "R",
              chars[1] >= "A" && chars[1] <= "R",
              chars[2] >= "0" && chars[2] <= "9",
              chars[3] >= "0" && chars[3] <= "9" else { return false }
        if clean.count == 6 {
            guard chars[4] >= "A" && chars[4] <= "X",
                  chars[5] >= "A" && chars[5] <= "X" else { return false }
        }
        return true
    }
}

// MARK: - Inbound Data Cursor

nonisolated public struct DataCursor {
    public let data: Data
    public var offset = 0

    public init(data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    public mutating func readUInt8() -> UInt8? {
        guard offset < data.count else { return nil }
        let r = data[offset]
        offset += 1
        return r
    }

    public mutating func readUInt32() -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let result = (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
        offset += 4
        return result
    }

    public mutating func readUInt64() -> UInt64? {
        guard offset + 8 <= data.count else { return nil }
        var result: UInt64 = 0
        for index in 0..<8 { result = (result << 8) | UInt64(data[offset + index]) }
        offset += 8
        return result
    }

    public mutating func readInt32() -> Int32? {
        guard let u = readUInt32() else { return nil }
        return Int32(bitPattern: u)
    }

    public mutating func readDouble() -> Double? {
        guard let u = readUInt64() else { return nil }
        return Double(bitPattern: u)
    }

    public mutating func readBool() -> Bool? {
        guard offset < data.count else { return nil }
        let result = data[offset] != 0
        offset += 1
        return result
    }

    public mutating func readString() -> String? {
        guard let length = readUInt32() else { return nil }
        if length == UInt32.max { return "" }
        guard length <= Int.max, offset + Int(length) <= data.count else { return nil }
        let range = offset..<(offset + Int(length))
        offset += Int(length)
        return String(data: data[range], encoding: .utf8) ?? ""
    }
}
