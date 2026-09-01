//
//  RotatorService.swift
//  YAAM
//
//  Antenna Rotator Control Engine (Hamlib rotctld & PstRotator)
//  Supports 1-click rotation to Short Path (SP) and Long Path (LP) bearings,
//  manual azimuth dial, cardinal presets, and status polling.
//

import Combine
import Foundation
import Network

public enum RotatorProtocol: String, CaseIterable, Identifiable, Sendable {
    case rotctld = "Hamlib rotctld"
    case pstRotator = "PstRotator (IP/UDP)"

    public var id: String { rawValue }
}

public struct RotatorPreset: Identifiable, Sendable {
    public let id = UUID()
    public let label: String
    public let azimuth: Double
    public let icon: String

    public init(label: String, azimuth: Double, icon: String = "location.north.line.fill") {
        self.label = label
        self.azimuth = azimuth
        self.icon = icon
    }
}

@MainActor
public final class RotatorService: ObservableObject {
    public static let shared = RotatorService()

    // MARK: - Published State
    @Published public var isConnected: Bool = false
    @Published public var host: String = "127.0.0.1"
    @Published public var port: Int = 4533
    @Published public var protocolType: RotatorProtocol = .rotctld
    @Published public var currentAzimuth: Double = 0.0
    @Published public var targetAzimuth: Double = 0.0
    @Published public var currentElevation: Double = 0.0
    @Published public var isRotating: Bool = false
    @Published public var lastStatus: String = "Disconnected"
    @Published public var lastError: String? = nil

    public let defaultPresets: [RotatorPreset] = [
        RotatorPreset(label: "N (0°)", azimuth: 0.0, icon: "arrow.up"),
        RotatorPreset(label: "E (90°)", azimuth: 90.0, icon: "arrow.right"),
        RotatorPreset(label: "S (180°)", azimuth: 180.0, icon: "arrow.down"),
        RotatorPreset(label: "W (270°)", azimuth: 270.0, icon: "arrow.left"),
        RotatorPreset(label: "Europe (315°)", azimuth: 315.0, icon: "globe.europe.africa.fill"),
        RotatorPreset(label: "North America (340°)", azimuth: 340.0, icon: "globe.americas.fill"),
        RotatorPreset(label: "Japan/Asia (65°)", azimuth: 65.0, icon: "globe.asia.australia.fill"),
        RotatorPreset(label: "Australia (125°)", azimuth: 125.0, icon: "antenna.radiowaves.left.and.right")
    ]

    private var connection: NWConnection?
    private var pollTimer: Timer?

    public init() {}

    // MARK: - Connect & Disconnect

    public func connect(host: String = "127.0.0.1", port: Int = 4533, protocolType: RotatorProtocol = .rotctld) {
        self.host = host
        self.port = port
        self.protocolType = protocolType
        self.lastError = nil

        let endpointHost = NWEndpoint.Host(host)
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            self.lastError = "Invalid port"
            return
        }

        let nwConnection = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
        self.connection = nwConnection

        nwConnection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.lastStatus = "Connected to \(self.protocolType.rawValue)"
                    self.startPolling()
                case .failed(let error):
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                    self.lastStatus = "Connection Failed"
                    self.stopPolling()
                case .cancelled:
                    self.isConnected = false
                    self.lastStatus = "Disconnected"
                    self.stopPolling()
                default:
                    break
                }
            }
        }

        nwConnection.start(queue: .global(qos: .userInitiated))
    }

    public func disconnect() {
        stopPolling()
        connection?.cancel()
        connection = nil
        isConnected = false
        lastStatus = "Disconnected"
    }

    // MARK: - Polling

    public func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestPosition()
            }
        }
        requestPosition()
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    public func requestPosition() {
        guard isConnected, let connection else { return }
        let command = "p\n".data(using: .utf8)!
        connection.send(content: command, completion: .contentProcessed { [weak self] error in
            if error == nil {
                Task { @MainActor [weak self] in
                    self?.receivePositionResponse()
                }
            }
        })
    }

    private func receivePositionResponse() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128) { [weak self] data, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self, let data, let responseStr = String(data: data, encoding: .utf8) else { return }
                let lines = responseStr.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if let first = lines.first, let az = Double(first.trimmingCharacters(in: .whitespaces)) {
                    self.currentAzimuth = az
                    if abs(self.currentAzimuth - self.targetAzimuth) > 2.0 && self.targetAzimuth != 0 {
                        self.isRotating = true
                    } else {
                        self.isRotating = false
                    }
                }
            }
        }
    }

    // MARK: - Turn Commands

    public func turnTo(azimuth: Double) {
        let normalized = (azimuth.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        self.targetAzimuth = normalized
        self.isRotating = true

        if protocolType == .rotctld {
            let cmdStr = String(format: "P %.1f 0.0\n", normalized)
            if let data = cmdStr.data(using: .utf8), let connection {
                connection.send(content: data, completion: .contentProcessed { _ in })
            }
        } else {
            // PstRotator HTTP REST format
            guard let url = URL(string: "http://\(host):\(port)/set?az=\(Int(normalized))") else { return }
            var req = URLRequest(url: url)
            req.timeoutInterval = 2.0
            URLSession.shared.dataTask(with: req).resume()
        }
    }

    public func turnToShortPath(target: GeoCoordinate, home: GeoCoordinate) {
        let spBearing = GeodesicMath.initialBearing(from: home, to: target)
        turnTo(azimuth: spBearing)
    }

    public func turnToLongPath(target: GeoCoordinate, home: GeoCoordinate) {
        let lpBearing = GeodesicMath.longPathBearing(from: home, to: target)
        turnTo(azimuth: lpBearing)
    }

    public func stop() {
        self.isRotating = false
        if protocolType == .rotctld {
            let cmdStr = "S\n"
            if let data = cmdStr.data(using: .utf8), let connection {
                connection.send(content: data, completion: .contentProcessed { _ in })
            }
        } else {
            guard let url = URL(string: "http://\(host):\(port)/stop") else { return }
            var req = URLRequest(url: url)
            req.timeoutInterval = 2.0
            URLSession.shared.dataTask(with: req).resume()
        }
    }
}
