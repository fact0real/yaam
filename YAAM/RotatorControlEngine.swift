//
//  RotatorControlEngine.swift
//  YAAM
//
//  Universal Antenna Rotator Control Engine for macOS
//  Supports Hamlib rotctld TCP protocol (default port 4533)
//  Provides real-time azimuth/elevation tracking, 1-click bearing positioning,
//  and emergency stop controls.
//

import AppKit
import Combine
import Foundation
import Network
import SwiftUI

// MARK: - Rotator Status Model

public struct RotatorStatus: Equatable, Sendable {
    public var azimuth: Double = 0.0
    public var elevation: Double = 0.0
    public var isMoving: Bool = false
    public var targetAzimuth: Double? = nil
    public var lastUpdated: Date = Date()
    
    public var cardinalDirection: String {
        let normalized = (azimuth.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        switch normalized {
        case 348.75...360, 0..<11.25: return "N"
        case 11.25..<33.75: return "NNE"
        case 33.75..<56.25: return "NE"
        case 56.25..<78.75: return "ENE"
        case 78.75..<101.25: return "E"
        case 101.25..<123.75: return "ESE"
        case 123.75..<146.25: return "SE"
        case 146.25..<168.75: return "SSE"
        case 168.75..<191.25: return "S"
        case 191.25..<213.75: return "SSW"
        case 213.75..<236.25: return "SW"
        case 236.25..<258.75: return "WSW"
        case 258.75..<281.25: return "W"
        case 281.25..<303.75: return "WNW"
        case 303.75..<326.25: return "NW"
        case 326.25..<348.75: return "NNW"
        default: return "N"
        }
    }
}

// MARK: - Rotator Control Engine

@MainActor
public final class RotatorControlEngine: ObservableObject {
    public static let shared = RotatorControlEngine()
    
    // User Configurations
    @AppStorage("rotatorEnabled") public var isEnabled: Bool = true
    @AppStorage("rotatorHost") public var host: String = "127.0.0.1"
    @AppStorage("rotatorPort") public var port: Int = 4533
    @AppStorage("rotatorModel") public var rotatorModel: String = "Hamlib rotctld"
    @AppStorage("rotatorToleranceDegrees") public var toleranceDegrees: Double = 1.5
    
    // Live Published State
    @Published public var isConnected: Bool = false
    @Published public var isConnecting: Bool = false
    @Published public var status: RotatorStatus = RotatorStatus()
    @Published public var lastError: String? = nil
    @Published public var showConfigPopover: Bool = false
    
    // Network & Polling
    private var connection: NWConnection?
    private var pollingTimer: AnyCancellable?
    private let queue = DispatchQueue(label: "app.yaam.rotator-engine", qos: .userInitiated)
    private var receiveBuffer = Data()
    
    private init() {
        if isEnabled {
            connect()
        }
    }
    
    deinit {
        connection?.cancel()
    }
    
    // MARK: - Connection Management
    
    public func connect() {
        guard !isConnected && !isConnecting else { return }
        
        isConnecting = true
        lastError = nil
        
        let endpointHost = NWEndpoint.Host(host)
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            lastError = "Invalid port \(port)"
            isConnecting = false
            return
        }
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 3
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        
        let conn = NWConnection(host: endpointHost, port: endpointPort, using: params)
        self.connection = conn
        
        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.isConnecting = false
                    self.lastError = nil
                    self.startPolling()
                    self.startReceiving()
                case .failed(let err):
                    self.isConnected = false
                    self.isConnecting = false
                    self.lastError = err.localizedDescription
                    self.stopPolling()
                case .cancelled:
                    self.isConnected = false
                    self.isConnecting = false
                    self.stopPolling()
                default:
                    break
                }
            }
        }
        
        conn.start(queue: queue)
    }
    
    public func disconnect() {
        stopPolling()
        connection?.cancel()
        connection = nil
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
    
    // MARK: - Polling Loop
    
    private func startPolling() {
        stopPolling()
        pollingTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.queryPosition()
            }
    }
    
    private func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }
    
    // MARK: - Command Execution
    
    public func queryPosition() {
        sendCommand("p\n")
    }
    
    public func setAzimuth(_ targetAz: Double, elevation: Double = 0.0) {
        let normalizedAz = min(360.0, max(0.0, targetAz))
        status.targetAzimuth = normalizedAz
        status.isMoving = true
        
        let cmd = String(format: "P %.1f %.1f\n", normalizedAz, elevation)
        sendCommand(cmd)
        
        // Immediate follow-up query after 300ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.queryPosition()
        }
    }
    
    public func stop() {
        status.targetAzimuth = nil
        status.isMoving = false
        sendCommand("S\n")
        queryPosition()
    }
    
    private func sendCommand(_ command: String) {
        guard isConnected, let connection = connection else { return }
        guard let data = command.data(using: .utf8) else { return }
        
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.lastError = "Send error: \(error.localizedDescription)"
                }
            }
        })
    }
    
    // MARK: - Data Ingestion
    
    private func startReceiving() {
        guard let connection = connection else { return }
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, context, isComplete, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let data = data, !data.isEmpty {
                    self.receiveBuffer.append(data)
                    self.processBuffer()
                }
                
                if let error = error {
                    self.lastError = "Receive error: \(error.localizedDescription)"
                } else if !isComplete {
                    self.startReceiving()
                }
            }
        }
    }
    
    private func processBuffer() {
        guard let text = String(data: receiveBuffer, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: .newlines)
        
        // If we have at least one complete line
        if lines.count > 1 {
            for i in 0..<(lines.count - 1) {
                let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                parseResponseLine(line)
            }
            // Keep remainder in buffer
            if let last = lines.last?.data(using: .utf8) {
                receiveBuffer = last
            } else {
                receiveBuffer.removeAll()
            }
        }
    }
    
    private func parseResponseLine(_ line: String) {
        guard !line.isEmpty else { return }
        
        // Handle "RPRT 0" acknowledgment
        if line.contains("RPRT") {
            return
        }
        
        // In rotctld, "p" returns Azimuth on line 1, Elevation on line 2 (or space separated in some versions)
        let parts = line.split(whereSeparator: { $0.isWhitespace })
        if let first = parts.first, let az = Double(first) {
            DispatchQueue.main.async {
                self.status.azimuth = az
                if parts.count > 1, let el = Double(parts[1]) {
                    self.status.elevation = el
                }
                
                // Check if reached target
                if let target = self.status.targetAzimuth {
                    let diff = abs(az - target)
                    if diff <= self.toleranceDegrees || abs(diff - 360.0) <= self.toleranceDegrees {
                        self.status.isMoving = false
                        self.status.targetAzimuth = nil
                    } else {
                        self.status.isMoving = true
                    }
                }
                self.status.lastUpdated = Date()
            }
        }
    }
}
