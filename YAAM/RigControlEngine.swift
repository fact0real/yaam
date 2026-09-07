//
//  RigControlEngine.swift
//  YAAM
//
//  Universal Transceiver CAT Control Engine
//  Supports Flrig (XML-RPC on port 12345) and Hamlib (rigctld TCP on port 4532)
//  Provides bidirectional VFO frequency tuning, mode selection, power monitoring,
//  and real-time S-Meter streaming for any amateur radio on macOS.
//

import AppKit
import Combine
import Foundation
import Network
import SwiftUI

// MARK: - Rig Driver Enum

public enum RigDriverType: String, CaseIterable, Identifiable, Sendable {
    case flrig = "Flrig (XML-RPC)"
    case rigctld = "Hamlib (rigctld TCP)"
    case disabled = "Disabled"

    public var id: String { rawValue }

    public var defaultPort: Int {
        switch self {
        case .flrig: return 12345
        case .rigctld: return 4532
        case .disabled: return 0
        }
    }
}

// MARK: - Rig Control Engine

@MainActor
public final class RigControlEngine: ObservableObject {
    public static let shared = RigControlEngine()

    // Configuration
    @AppStorage("rigDriverType") public var driverType: RigDriverType = .flrig
    @AppStorage("rigHost") public var host: String = "127.0.0.1"
    @AppStorage("rigPort") public var port: Int = 12345
    @AppStorage("rigAutoConnect") public var autoConnect: Bool = true

    // Real-Time Transceiver Telemetry
    @Published public var isConnected: Bool = false
    @Published public var isConnecting: Bool = false
    @Published public var rigModel: String = "Transceiver"
    @Published public var frequencyHz: UInt64 = 14074000
    @Published public var mode: String = "USB-D"
    @Published public var powerWatts: Int = 50
    @Published public var sMeterValue: Double = 5.0 // S-units (0 to 15, where > 9 is +dB)
    @Published public var isPTT: Bool = false
    @Published public var lastError: String? = nil
    @Published public var lastResponseTime = Date()

    // Formatted Telemetry
    public var frequencyMHz: Double {
        Double(frequencyHz) / 1_000_000.0
    }

    public var formattedFrequency: String {
        let mhz = frequencyMHz
        return String(format: "%.6f MHz", mhz)
    }

    public var currentBand: String {
        AmateurBandPlan.band(forMHz: frequencyMHz) ?? "HF"
    }

    public var sMeterDescription: String {
        if sMeterValue <= 9.0 {
            return "S\(Int(sMeterValue))"
        } else {
            let overDB = Int((sMeterValue - 9.0) * 10)
            return "S9+\(overDB)dB"
        }
    }

    private var pollingTask: Task<Void, Never>?
    private var tcpConnection: NWConnection?

    private init() {
        if autoConnect && driverType != .disabled {
            connect()
        }
    }

    deinit {
        pollingTask?.cancel()
        tcpConnection?.cancel()
    }

    // MARK: - Connect & Disconnect
    public func connect() {
        guard driverType != .disabled else {
            disconnect()
            return
        }

        isConnecting = true
        lastError = nil

        switch driverType {
        case .flrig:
            startFlrigPolling()
        case .rigctld:
            startRigctldTCP()
        case .disabled:
            disconnect()
        }
    }

    public func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
        tcpConnection?.cancel()
        tcpConnection = nil
        isConnected = false
        isConnecting = false
    }

    public func toggleConnection() {
        if isConnected || isConnecting {
            disconnect()
        } else {
            connect()
        }
    }

    // MARK: - VFO Tuning & Commands
    public func tune(frequencyHz: UInt64, mode: String? = nil) {
        self.frequencyHz = frequencyHz
        if let mode = mode, !mode.isEmpty {
            self.mode = mode
        }

        Task {
            switch driverType {
            case .flrig:
                _ = await flrigCall(method: "rig.set_vfo", param: String(frequencyHz))
                if let mode = mode, !mode.isEmpty {
                    _ = await flrigCall(method: "rig.set_mode", param: mode)
                }
            case .rigctld:
                sendRigctldCommand("F \(frequencyHz)\n")
                if let mode = mode, !mode.isEmpty {
                    sendRigctldCommand("M \(mode) 2400\n")
                }
            case .disabled:
                break
            }
        }
    }

    public func tune(frequencyMHz: Double, mode: String? = nil) {
        let hz = UInt64(frequencyMHz * 1_000_000.0)
        tune(frequencyHz: hz, mode: mode)
    }

    public func setMode(_ newMode: String) {
        self.mode = newMode
        Task {
            switch driverType {
            case .flrig:
                _ = await flrigCall(method: "rig.set_mode", param: newMode)
            case .rigctld:
                sendRigctldCommand("M \(newMode) 2400\n")
            case .disabled:
                break
            }
        }
    }

    public func setPower(_ watts: Int) {
        self.powerWatts = watts
        Task {
            switch driverType {
            case .flrig:
                _ = await flrigCall(method: "rig.set_power", param: String(watts))
            case .rigctld:
                let fraction = Double(watts) / 100.0
                sendRigctldCommand("l RFPOWER \(fraction)\n")
            case .disabled:
                break
            }
        }
    }

    // MARK: - Flrig XML-RPC Engine
    private func startFlrigPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }

                await self.pollFlrigTelemetry()
                try? await Task.sleep(nanoseconds: 600_000_000) // Poll every 600ms
            }
        }
    }

    private func pollFlrigTelemetry() async {
        let xcvr = await flrigCall(method: "rig.get_xcvr")
        if let model = xcvr, !model.isEmpty {
            self.rigModel = model
            self.isConnected = true
            self.isConnecting = false
        } else {
            // Check if get_vfo succeeds even if get_xcvr is empty
            let testVFO = await flrigCall(method: "rig.get_vfo")
            if testVFO != nil {
                self.isConnected = true
                self.isConnecting = false
            } else {
                self.isConnected = false
                return
            }
        }

        // 1. Frequency
        if let vfoStr = await flrigCall(method: "rig.get_vfo") {
            if let hz = UInt64(vfoStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                self.frequencyHz = hz
            } else if let dbl = Double(vfoStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                self.frequencyHz = UInt64(dbl)
            }
        }

        // 2. Mode
        if let modeStr = await flrigCall(method: "rig.get_mode") {
            let clean = modeStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { self.mode = clean }
        }

        // 3. Power
        if let pwrStr = await flrigCall(method: "rig.get_power") {
            if let p = Int(pwrStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                self.powerWatts = p
            }
        }

        // 4. S-Meter
        if let sStr = await flrigCall(method: "rig.get_smeter") {
            if let val = Double(sStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                self.sMeterValue = min(15.0, max(0.0, val))
            }
        }

        self.lastResponseTime = Date()
    }

    private func flrigCall(method: String, param: String? = nil) async -> String? {
        guard let url = URL(string: "http://\(host):\(port)") else { return nil }

        var paramXML = ""
        if let param = param {
            paramXML = "<param><value><string>\(param)</string></value></param>"
        }

        let xml = """
        <?xml version="1.0"?>
        <methodCall>
            <methodName>\(method)</methodName>
            <params>\(paramXML)</params>
        </methodCall>
        """

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 1.5)
        request.httpMethod = "POST"
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.httpBody = xml.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return parseXMLRPCResponse(data)
        } catch {
            return nil
        }
    }

    private func parseXMLRPCResponse(_ data: Data) -> String? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }

        // Extract value between <value>...</value> or <string>...</string>
        if let start = str.range(of: "<string>"), let end = str.range(of: "</string>") {
            return String(str[start.upperBound..<end.lowerBound])
        }
        if let start = str.range(of: "<double>"), let end = str.range(of: "</double>") {
            return String(str[start.upperBound..<end.lowerBound])
        }
        if let start = str.range(of: "<i4>"), let end = str.range(of: "</i4>") {
            return String(str[start.upperBound..<end.lowerBound])
        }
        if let start = str.range(of: "<value>"), let end = str.range(of: "</value>") {
            let inner = String(str[start.upperBound..<end.lowerBound])
            return inner.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        return nil
    }

    // MARK: - Hamlib rigctld TCP Engine
    private func startRigctldTCP() {
        tcpConnection?.cancel()

        let endpointHost = NWEndpoint.Host(host)
        let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? 4532

        let conn = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
        self.tcpConnection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.isConnecting = false
                    self.rigModel = "Hamlib Radio"
                    self.startRigctldPolling()
                case .failed(let err):
                    self.isConnected = false
                    self.isConnecting = false
                    self.lastError = err.localizedDescription
                case .cancelled:
                    self.isConnected = false
                    self.isConnecting = false
                default:
                    break
                }
            }
        }

        conn.start(queue: .global())
    }

    private func startRigctldPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, self.isConnected else { return }

                self.sendRigctldCommand("f\n") // Get frequency
                self.sendRigctldCommand("m\n") // Get mode
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
    }

    private func sendRigctldCommand(_ command: String) {
        guard let conn = tcpConnection, isConnected else { return }
        let data = command.data(using: .utf8) ?? Data()
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            if error == nil {
                Task { @MainActor [weak self] in
                    self?.readRigctldResponse()
                }
            }
        })
    }

    private func readRigctldResponse() {
        tcpConnection?.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, let text = String(data: data, encoding: .utf8) else { return }

            Task { @MainActor in
                let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                for line in lines {
                    if let hz = UInt64(line), hz > 100000 {
                        self.frequencyHz = hz
                    } else if ["USB", "LSB", "CW", "CWR", "AM", "FM", "PKTUSB", "PKTLSB"].contains(line.uppercased()) {
                        self.mode = line
                    }
                }
                self.lastResponseTime = Date()
            }
        }
    }
}
