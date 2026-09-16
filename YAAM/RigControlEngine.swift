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
    case icomUSB = "Icom Transceiver (USB CI-V)"
    case flrig = "Flrig (XML-RPC)"
    case rigctld = "Hamlib (rigctld TCP)"
    case tx500 = "Lab599 TX-500 (USB-C Serial)"
    case fx4cr = "FX-4CR (USB / Bluetooth)"
    case xiegu6100 = "Xiegu X6100 (USB-C)"
    case disabled = "Disabled"

    public var id: String { rawValue }

    public var defaultPort: Int {
        switch self {
        case .flrig: return 12345
        case .rigctld: return 4532
        case .icomUSB, .tx500, .fx4cr, .xiegu6100, .disabled: return 0
        }
    }
}

// MARK: - Rig Control Engine

@MainActor
public final class RigControlEngine: ObservableObject {
    public static let shared = RigControlEngine()

    // Configuration
    @Published public var driverType: RigDriverType {
        didSet { UserDefaults.standard.set(driverType.rawValue, forKey: "rigDriverType") }
    }
    @Published public var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "rigHost") }
    }
    @Published public var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "rigPort") }
    }
    @Published public var autoConnect: Bool {
        didSet { UserDefaults.standard.set(autoConnect, forKey: "rigAutoConnect") }
    }

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
        let savedDriver = UserDefaults.standard.string(forKey: "rigDriverType") ?? RigDriverType.flrig.rawValue
        self.driverType = RigDriverType(rawValue: savedDriver) ?? .flrig
        self.host = UserDefaults.standard.string(forKey: "rigHost") ?? "127.0.0.1"
        let savedPort = UserDefaults.standard.integer(forKey: "rigPort")
        self.port = savedPort > 0 ? savedPort : 12345
        self.autoConnect = UserDefaults.standard.object(forKey: "rigAutoConnect") as? Bool ?? true

        if autoConnect && driverType != .disabled {
            connect()
        }
    }

    deinit {
        pollingTask?.cancel()
        tcpConnection?.cancel()
    }

    private var tx500Cancellables = Set<AnyCancellable>()
    private var icomUSBCancellables = Set<AnyCancellable>()
    private var fx4crCancellables = Set<AnyCancellable>()
    private var xiegu6100Cancellables = Set<AnyCancellable>()

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
        case .tx500:
            startTX500Integration()
        case .icomUSB:
            startIcomUSBIntegration()
        case .fx4cr:
            startFX4CRIntegration()
        case .xiegu6100:
            startXiegu6100Integration()
        case .disabled:
            disconnect()
        }
    }

    public func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
        tcpConnection?.cancel()
        tcpConnection = nil
        tx500Cancellables.removeAll()
        icomUSBCancellables.removeAll()
        fx4crCancellables.removeAll()
        xiegu6100Cancellables.removeAll()
        if driverType == .tx500 {
            Lab599TX500Driver.shared.disconnect()
        } else if driverType == .icomUSB {
            IcomUSBRadioDriver.shared.disconnect()
        } else if driverType == .fx4cr {
            FX4CRDriver.shared.disconnect()
        } else if driverType == .xiegu6100 {
            Xiegu6100Driver.shared.disconnect()
        }
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
            case .tx500:
                Lab599TX500Driver.shared.setFrequencyHz(frequencyHz)
                if let mode = mode, !mode.isEmpty {
                    Lab599TX500Driver.shared.setMode(mode)
                }
            case .icomUSB:
                IcomUSBRadioDriver.shared.setFrequencyHz(frequencyHz)
                if let mode = mode, !mode.isEmpty {
                    IcomUSBRadioDriver.shared.setMode(mode)
                }
            case .fx4cr:
                FX4CRDriver.shared.setFrequencyHz(frequencyHz)
                if let mode = mode, !mode.isEmpty {
                    FX4CRDriver.shared.setMode(mode)
                }
            case .xiegu6100:
                Xiegu6100Driver.shared.setFrequencyHz(frequencyHz)
                if let mode = mode, !mode.isEmpty {
                    Xiegu6100Driver.shared.setMode(mode)
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
            case .tx500:
                Lab599TX500Driver.shared.setMode(newMode)
            case .icomUSB:
                IcomUSBRadioDriver.shared.setMode(newMode)
            case .fx4cr:
                FX4CRDriver.shared.setMode(newMode)
            case .xiegu6100:
                Xiegu6100Driver.shared.setMode(newMode)
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
            case .tx500:
                Lab599TX500Driver.shared.setPowerWatts(watts)
            case .icomUSB:
                // Icom USB sets power via RF power level or telemetry
                break
            case .fx4cr:
                FX4CRDriver.shared.setPowerWatts(watts)
            case .xiegu6100:
                Xiegu6100Driver.shared.setPowerWatts(watts)
            case .disabled:
                break
            }
        }
    }

    public func setPTT(_ transmit: Bool) {
        self.isPTT = transmit
        switch driverType {
        case .flrig:
            Task { _ = await flrigCall(method: "rig.set_ptt", param: transmit ? "1" : "0") }
        case .rigctld:
            sendRigctldCommand(transmit ? "T 1\n" : "T 0\n")
        case .tx500:
            Lab599TX500Driver.shared.setPTT(transmit)
        case .icomUSB:
            IcomUSBRadioDriver.shared.setPTT(transmit)
        case .fx4cr:
            FX4CRDriver.shared.setPTT(transmit)
        case .xiegu6100:
            Xiegu6100Driver.shared.setPTT(transmit)
        case .disabled:
            break
        }
    }

    private func startTX500Integration() {
        let driver = Lab599TX500Driver.shared
        self.rigModel = "Lab599 TX-500"
        tx500Cancellables.removeAll()

        driver.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] conn in
                self?.isConnected = conn
                self?.isConnecting = driver.isConnecting
            }
            .store(in: &tx500Cancellables)

        driver.$frequencyHz
            .receive(on: RunLoop.main)
            .sink { [weak self] freq in
                self?.frequencyHz = freq
                self?.lastResponseTime = Date()
            }
            .store(in: &tx500Cancellables)

        driver.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] m in self?.mode = m }
            .store(in: &tx500Cancellables)

        driver.$sMeterValue
            .receive(on: RunLoop.main)
            .sink { [weak self] sm in self?.sMeterValue = sm }
            .store(in: &tx500Cancellables)

        driver.$powerWatts
            .receive(on: RunLoop.main)
            .sink { [weak self] pwr in self?.powerWatts = pwr }
            .store(in: &tx500Cancellables)

        driver.$isTransmitting
            .receive(on: RunLoop.main)
            .sink { [weak self] tx in self?.isPTT = tx }
            .store(in: &tx500Cancellables)

        if !driver.isConnected && !driver.selectedPort.isEmpty {
            driver.connect()
        } else if driver.isConnected {
            self.isConnected = true
            self.frequencyHz = driver.frequencyHz
            self.mode = driver.mode
            self.sMeterValue = driver.sMeterValue
            self.powerWatts = driver.powerWatts
        }
    }

    private func startIcomUSBIntegration() {
        let driver = IcomUSBRadioDriver.shared
        self.rigModel = driver.model == .auto ? "Icom (Auto CI-V)" : driver.model.rawValue
        icomUSBCancellables.removeAll()

        driver.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] conn in
                self?.isConnected = conn
                self?.isConnecting = driver.isConnecting
            }
            .store(in: &icomUSBCancellables)

        driver.$frequencyHz
            .receive(on: RunLoop.main)
            .sink { [weak self] freq in
                self?.frequencyHz = freq
                self?.lastResponseTime = Date()
            }
            .store(in: &icomUSBCancellables)

        driver.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] m in self?.mode = m }
            .store(in: &icomUSBCancellables)

        driver.$sMeterValue
            .receive(on: RunLoop.main)
            .sink { [weak self] sm in self?.sMeterValue = sm }
            .store(in: &icomUSBCancellables)

        driver.$rfPowerWatts
            .receive(on: RunLoop.main)
            .sink { [weak self] pwr in self?.powerWatts = Int(pwr) }
            .store(in: &icomUSBCancellables)

        driver.$isTransmitting
            .receive(on: RunLoop.main)
            .sink { [weak self] tx in self?.isPTT = tx }
            .store(in: &icomUSBCancellables)

        driver.$model
            .receive(on: RunLoop.main)
            .sink { [weak self] mdl in
                self?.rigModel = mdl == .auto ? "Icom (Auto CI-V)" : mdl.rawValue
            }
            .store(in: &icomUSBCancellables)

        if !driver.isConnected && !driver.selectedPort.isEmpty {
            driver.connect()
        } else if driver.isConnected {
            self.isConnected = true
            self.frequencyHz = driver.frequencyHz
            self.mode = driver.mode
            self.sMeterValue = driver.sMeterValue
            self.powerWatts = Int(driver.rfPowerWatts)
            self.rigModel = driver.model == .auto ? "Icom (Auto CI-V)" : driver.model.rawValue
        }
    }

    private func startFX4CRIntegration() {
        fx4crCancellables.removeAll()
        let driver = FX4CRDriver.shared
        self.rigModel = "FX-4CR (\(driver.connectionType.rawValue))"

        driver.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] conn in
                self?.isConnected = conn
                self?.isConnecting = driver.isConnecting
                if conn {
                    self?.rigModel = "FX-4CR (\(driver.connectionType.rawValue))"
                }
            }
            .store(in: &fx4crCancellables)

        driver.$isConnecting
            .receive(on: RunLoop.main)
            .sink { [weak self] connecting in
                self?.isConnecting = connecting
            }
            .store(in: &fx4crCancellables)

        driver.$frequencyHz
            .receive(on: RunLoop.main)
            .sink { [weak self] freq in
                if freq > 0 {
                    self?.frequencyHz = freq
                }
            }
            .store(in: &fx4crCancellables)

        driver.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] m in
                self?.mode = m
            }
            .store(in: &fx4crCancellables)

        driver.$sMeterValue
            .receive(on: RunLoop.main)
            .sink { [weak self] sm in
                self?.sMeterValue = sm
            }
            .store(in: &fx4crCancellables)

        driver.$powerWatts
            .receive(on: RunLoop.main)
            .sink { [weak self] pwr in
                self?.powerWatts = pwr
            }
            .store(in: &fx4crCancellables)

        driver.$isTransmitting
            .receive(on: RunLoop.main)
            .sink { [weak self] tx in
                self?.isPTT = tx
            }
            .store(in: &fx4crCancellables)

        driver.$connectionType
            .receive(on: RunLoop.main)
            .sink { [weak self] trans in
                if driver.isConnected {
                    self?.rigModel = "FX-4CR (\(trans.rawValue))"
                }
            }
            .store(in: &fx4crCancellables)

        if !driver.isConnected && !driver.selectedPort.isEmpty {
            driver.connect()
        } else if driver.isConnected {
            self.isConnected = true
            self.frequencyHz = driver.frequencyHz
            self.mode = driver.mode
            self.sMeterValue = driver.sMeterValue
            self.powerWatts = driver.powerWatts
            self.rigModel = "FX-4CR (\(driver.connectionType.rawValue))"
        }
    }

    private func startXiegu6100Integration() {
        xiegu6100Cancellables.removeAll()
        let driver = Xiegu6100Driver.shared
        self.rigModel = "Xiegu X6100"

        driver.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] conn in
                self?.isConnected = conn
                self?.isConnecting = driver.isConnecting
                if conn {
                    self?.lastError = nil
                    self?.lastResponseTime = Date()
                    self?.rigModel = "Xiegu X6100"
                }
            }
            .store(in: &xiegu6100Cancellables)

        driver.$isConnecting
            .receive(on: RunLoop.main)
            .sink { [weak self] connecting in
                self?.isConnecting = connecting
            }
            .store(in: &xiegu6100Cancellables)

        driver.$frequencyHz
            .receive(on: RunLoop.main)
            .sink { [weak self] freq in
                if freq > 0 {
                    self?.frequencyHz = freq
                    self?.lastResponseTime = Date()
                }
            }
            .store(in: &xiegu6100Cancellables)

        driver.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] m in
                self?.mode = m
            }
            .store(in: &xiegu6100Cancellables)

        driver.$sMeterValue
            .receive(on: RunLoop.main)
            .sink { [weak self] sm in
                self?.sMeterValue = sm
            }
            .store(in: &xiegu6100Cancellables)

        driver.$powerWatts
            .receive(on: RunLoop.main)
            .sink { [weak self] pwr in
                self?.powerWatts = pwr
            }
            .store(in: &xiegu6100Cancellables)

        driver.$isTransmitting
            .receive(on: RunLoop.main)
            .sink { [weak self] tx in
                self?.isPTT = tx
            }
            .store(in: &xiegu6100Cancellables)

        if !driver.isConnected && !driver.selectedPort.isEmpty {
            driver.connect()
        } else if driver.isConnected {
            self.isConnected = true
            self.frequencyHz = driver.frequencyHz
            self.mode = driver.mode
            self.sMeterValue = driver.sMeterValue
            self.powerWatts = driver.powerWatts
            self.rigModel = "Xiegu X6100"
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
