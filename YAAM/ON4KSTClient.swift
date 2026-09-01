//
//  ON4KSTClient.swift
//  YAAM
//
//  ON4KST Real-Time VHF / UHF / Microwave Chat & DX Sked Client
//  Telnet socket client connecting to chat.on4kst.com for 50/70 MHz, 144/432 MHz,
//  Microwaves (1.2GHz-76GHz), and 160m Low-Band propagation coordination.
//

import Combine
import Foundation
import Network
import SwiftUI

public enum ON4KSTRoom: Int, CaseIterable, Identifiable, Sendable {
    case fiftyMHz = 23000
    case oneFortyFour = 23001
    case microwave = 23002
    case lowBand = 23003

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .fiftyMHz: return "50 / 70 MHz (6m & 4m)"
        case .oneFortyFour: return "144 / 432 MHz (2m & 70cm)"
        case .microwave: return "Microwaves (1.2G - 76G)"
        case .lowBand: return "160m & 80m Low-Band"
        }
    }

    public var shortName: String {
        switch self {
        case .fiftyMHz: return "50MHz"
        case .oneFortyFour: return "144MHz"
        case .microwave: return "uWave"
        case .lowBand: return "160m"
        }
    }
}

public struct ON4KSTMessage: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let sender: String
    public let recipient: String?
    public let text: String
    public let isSpot: Bool
    public let detectedFrequencyMHz: Double?
    public let isDirected: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sender: String,
        recipient: String? = nil,
        text: String,
        isSpot: Bool = false,
        detectedFrequencyMHz: Double? = nil,
        isDirected: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sender = sender
        self.recipient = recipient
        self.text = text
        self.isSpot = isSpot
        self.detectedFrequencyMHz = detectedFrequencyMHz
        self.isDirected = isDirected
    }
}

public struct ON4KSTUser: Identifiable, Sendable {
    public var id: String { callsign }
    public let callsign: String
    public let locator: String
    public let distanceKm: Double?
    public let bearingDeg: Double?
    public let extraInfo: String

    public init(
        callsign: String,
        locator: String = "",
        distanceKm: Double? = nil,
        bearingDeg: Double? = nil,
        extraInfo: String = ""
    ) {
        self.callsign = callsign
        self.locator = locator
        self.distanceKm = distanceKm
        self.bearingDeg = bearingDeg
        self.extraInfo = extraInfo
    }
}

@MainActor
public final class ON4KSTClient: ObservableObject {
    public static let shared = ON4KSTClient()

    // MARK: - Published State
    @Published public var isConnected: Bool = false
    @Published public var isLoggingIn: Bool = false
    @Published public var selectedRoom: ON4KSTRoom = .fiftyMHz
    @Published public var messages: [ON4KSTMessage] = []
    @Published public var onlineUsers: [ON4KSTUser] = []
    @Published public var statusMessage: String = "Disconnected"
    @Published public var serverHost: String = "chat.on4kst.com"
    @Published public var myCallsign: String = "EP2AES"
    @Published public var myGrid: String = "LN35ir"

    private var connection: NWConnection?
    private var receiveBuffer: String = ""
    private var pingTimer: Timer?

    public init() {
        populateInitialSampleMessages()
    }

    // MARK: - Connect & Login

    public func connect(
        room: ON4KSTRoom? = nil,
        callsign: String,
        password: String = ""
    ) {
        if let r = room { self.selectedRoom = r }
        disconnect()

        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCall.isEmpty else {
            self.statusMessage = "Please enter your station callsign"
            return
        }

        self.statusMessage = "Connecting to \(selectedRoom.title)..."
        self.isLoggingIn = true

        let host = NWEndpoint.Host(serverHost)
        guard let port = NWEndpoint.Port(rawValue: UInt16(selectedRoom.rawValue)) else { return }

        let conn = NWConnection(host: host, port: port, using: .tcp)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.statusMessage = "Connected to \(self.selectedRoom.title)"
                    self.startReceiveLoop(callsign: cleanCall, password: password)
                    self.startPingTimer()
                case .failed(let error):
                    self.handleDisconnect(reason: error.localizedDescription)
                case .cancelled:
                    self.handleDisconnect(reason: "Disconnected")
                default:
                    break
                }
            }
        }

        conn.start(queue: .global(qos: .userInitiated))
    }

    public func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        connection?.cancel()
        connection = nil
        isConnected = false
        isLoggingIn = false
        statusMessage = "Disconnected"
    }

    private func handleDisconnect(reason: String) {
        self.isConnected = false
        self.isLoggingIn = false
        self.statusMessage = "Disconnected: \(reason)"
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendRawLine("/n") // Keepalive ping
            }
        }
    }

    // MARK: - Receive Loop & Telnet Processing

    private func startReceiveLoop(callsign: String, password: String) {
        guard let conn = connection else { return }

        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data = data, let text = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8) {
                    self.processIncomingChunk(text, callsign: callsign, password: password)
                    self.startReceiveLoop(callsign: callsign, password: password)
                } else if error != nil {
                    self.handleDisconnect(reason: error?.localizedDescription ?? "Read error")
                }
            }
        }
    }

    private func processIncomingChunk(_ chunk: String, callsign: String, password: String) {
        receiveBuffer += chunk

        // Handle login prompts
        if isLoggingIn {
            let lower = receiveBuffer.lowercased()
            if lower.contains("login:") || lower.contains("call:") || lower.contains("calls:") {
                sendRawLine(callsign)
            }
            if lower.contains("password:") {
                let pwd = password.isEmpty ? "NONE" : password
                sendRawLine(pwd)
                self.isLoggingIn = false
                self.statusMessage = "Logged in as \(callsign) on \(selectedRoom.title)"
            }
        }

        // Process completed lines
        while let newlineRange = receiveBuffer.range(of: "\n") {
            let line = String(receiveBuffer[..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            receiveBuffer.removeSubrange(..<newlineRange.upperBound)
            if !line.isEmpty {
                parseTelnetLine(line)
            }
        }
    }

    private func parseTelnetLine(_ line: String) {
        // 1. Check for DX Spot line: DX de <call>: <freq> <dx> <comment> <time>
        if line.hasPrefix("DX de ") {
            let parts = line.components(separatedBy: ":")
            let sender = parts.first?.replacingOccurrences(of: "DX de ", with: "").trimmingCharacters(in: .whitespaces) ?? "DX"
            let rest = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)

            let freq = extractFrequency(from: rest)
            let msg = ON4KSTMessage(
                sender: sender,
                text: rest,
                isSpot: true,
                detectedFrequencyMHz: freq
            )
            appendMessage(msg)
            return
        }

        // 2. Chat message format: <Sender> says to <Target>: <Message> or <Sender>: <Message>
        if line.contains(" says to ") {
            let parts = line.components(separatedBy: " says to ")
            let sender = parts[0].trimmingCharacters(in: .whitespaces)
            let rest = parts[1].components(separatedBy: ":")
            let recipient = rest[0].trimmingCharacters(in: .whitespaces)
            let msgText = rest.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)

            let freq = extractFrequency(from: msgText)
            let msg = ON4KSTMessage(
                sender: sender,
                recipient: recipient,
                text: msgText,
                isSpot: false,
                detectedFrequencyMHz: freq,
                isDirected: true
            )
            appendMessage(msg)
            return
        }

        // 3. Simple message format: <Sender>: <Message>
        if let colonIdx = line.firstIndex(of: ":"), !line.hasPrefix("---") && !line.hasPrefix("***") {
            let sender = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let msgText = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            // Ignore system headers
            if sender.count <= 15 && !sender.contains(" ") {
                let freq = extractFrequency(from: msgText)
                let msg = ON4KSTMessage(
                    sender: sender,
                    text: msgText,
                    isSpot: false,
                    detectedFrequencyMHz: freq
                )
                appendMessage(msg)
                return
            }
        }

        // System broadcast message
        if !line.isEmpty {
            let msg = ON4KSTMessage(
                sender: "ON4KST",
                text: line,
                isSpot: false
            )
            appendMessage(msg)
        }
    }

    private func appendMessage(_ msg: ON4KSTMessage) {
        messages.append(msg)
        if messages.count > 300 {
            messages.removeFirst(messages.count - 300)
        }
    }

    private func extractFrequency(from text: String) -> Double? {
        let pattern = #"\b(50\.\d+|70\.\d+|144\.\d+|432\.\d+|1296\.\d+|2320\.\d+|10368\.\d+|24048\.\d+|1\.8\d+|3\.5\d+|7\.\d+|14\.\d+|28\.\d+)\b"#
        if let match = text.range(of: pattern, options: .regularExpression) {
            return Double(text[match])
        }
        return nil
    }

    // MARK: - Send Public / Private Message

    public func sendMessage(text: String, recipient: String? = nil) {
        guard isConnected else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        if let target = recipient, !target.isEmpty && target.uppercased() != "ALL" {
            // Private message format: /m <target> <text>
            sendRawLine("/m \(target.uppercased()) \(clean)")
        } else {
            // Public message
            sendRawLine(clean)
        }

        // Echo locally
        let myCall = self.myCallsign.isEmpty ? "EP2AES" : self.myCallsign
        let msg = ON4KSTMessage(
            sender: myCall,
            recipient: recipient,
            text: clean,
            detectedFrequencyMHz: extractFrequency(from: clean),
            isDirected: recipient != nil && recipient?.uppercased() != "ALL"
        )
        appendMessage(msg)
    }

    public func sendCQ(frequencyMHz: String, mode: String = "FT8", beamHeading: String = "") {
        let myCall = self.myCallsign.isEmpty ? "EP2AES" : self.myCallsign
        let grid = self.myGrid.isEmpty ? "LN35ir" : self.myGrid
        var text = "CQ \(frequencyMHz) \(mode) de \(myCall) in \(grid)"
        if !beamHeading.isEmpty {
            text += " beam \(beamHeading)°"
        }
        sendMessage(text: text)
    }

    private func sendRawLine(_ line: String) {
        guard let conn = connection, isConnected else { return }
        let full = "\(line)\r\n"
        if let data = full.data(using: .isoLatin1) ?? full.data(using: .utf8) {
            conn.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    // MARK: - Initial Seeded Sample Data for Offline Display

    private func populateInitialSampleMessages() {
        let sample = [
            ON4KSTMessage(sender: "ON4KST", text: "Welcome to the ON4KST Real-Time 50/70MHz & VHF/UHF Chat Network", isSpot: false),
            ON4KSTMessage(sender: "DL1VHF", text: "CQ 50.313 FT8 beam 120° into Middle East & Asia", detectedFrequencyMHz: 50.313),
            ON4KSTMessage(sender: "G4FOC", recipient: "EP2AES", text: "Hi Mehdi, any Sporadic-E opening on 6m towards Tehran?", isDirected: true),
            ON4KSTMessage(sender: "SV1DH", text: "DX de SV1DH: 144.174 EP2AES KM17ww -> LN35ir FT8 strong ES 12:45Z", isSpot: true, detectedFrequencyMHz: 144.174),
            ON4KSTMessage(sender: "IK0FTA", text: "QRV on 70.154 CW listening East", detectedFrequencyMHz: 70.154),
            ON4KSTMessage(sender: "OE3FVU", text: "CQ 432.200 SSB beaming 110° for tropo skeds", detectedFrequencyMHz: 432.200)
        ]
        self.messages = sample

        let users = [
            ON4KSTUser(callsign: "DL1VHF", locator: "JO50xe", distanceKm: 3820, bearingDeg: 312, extraInfo: "6el Yagi 100W"),
            ON4KSTUser(callsign: "G4FOC", locator: "IO91ws", distanceKm: 4410, bearingDeg: 318, extraInfo: "5el LFA 400W"),
            ON4KSTUser(callsign: "SV1DH", locator: "KM17ww", distanceKm: 2150, bearingDeg: 284, extraInfo: "7el Yagi"),
            ON4KSTUser(callsign: "IK0FTA", locator: "JN61fv", distanceKm: 3420, bearingDeg: 300, extraInfo: "4el SteppIR"),
            ON4KSTUser(callsign: "OE3FVU", locator: "JN78ve", distanceKm: 3590, bearingDeg: 308, extraInfo: "12el M2")
        ]
        self.onlineUsers = users
    }
}
