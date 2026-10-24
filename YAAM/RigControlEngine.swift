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
    /// Flrig only: what flrig says (no radio selected / radio not answering / reports NAME). See FlrigLink.
    @Published public private(set) var flrigLink: FlrigLink = .idle
    /// Flrig only: set when a release of PTT could not be confirmed (flrig still reports PTT on, or YAAM could not read
    /// it). Also part of lastError. Shown next to the connection pill. See FlrigPTTRelease.
    @Published public private(set) var flrigPTTWarning: String? = nil

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

    /// Text for the connection pill. For flrig it says what flrig reports, never "radio connected".
    public var statusLabel: String {
        guard driverType == .flrig else { return isConnected ? rigModel : "CAT Offline" }
        switch flrigLink {
        case .reporting, .noRadio, .radioNotAnswering, .unexpected: return flrigLink.summary
        case .idle, .unreachable: return "CAT Offline"
        }
    }

    public var sMeterDescription: String {
        if driverType == .flrig { return "\(Int((sMeterValue / 15 * 100).rounded()))% (flrig)" }
        if sMeterValue <= 9.0 {
            return "S\(Int(sMeterValue))"
        } else {
            // Round, do not truncate: 10.2 - 9.0 is 1.1999999999999993 in binary floating point, which would show 11 dB, not 12.
            let overDB = Int(((sMeterValue - 9.0) * 10).rounded())
            return "S9+\(overDB)dB"
        }
    }

    private var pollingTask: Task<Void, Never>?
    private var tcpConnection: NWConnection?
    private let flrigChain = FlrigCommandChain()
    private var flrigErrors = FlrigErrorState()
    private var rigctldKeyed = false
    private var rigctldPTTWatchdog: Task<Void, Never>?
    private let noticeSource = TransmitNotices.Source(name: "Radio Control")
    private let releaseNoticeSource = TransmitNotices.Source(name: "Radio Control rigctld release")
    private var rigctldReplies: RigctldReplyStream?
    private var rigctldRetryTask: Task<Void, Never>?
    private var rigctldRetryAttempt = 0
    private var rigctldDesiredEndpoint: String?
    private var rigctldUncertainEndpoints = Set<String>()
    private var rigctldRecoveryReplies = Set<String>()
    private var flrigPTTWatchdog: Task<Void, Never>?

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
        // Registered so that quitting YAAM can release this path (TransmitShutdown).
        TransmitShutdown.register("Radio Control", isTransmitting: { [weak self] in
                                      // isPTT lags behind the drivers and flrig polling clears it; a key-down still counts.
                                      guard let self else { return false }
                                      return self.isPTT || self.rigctldKeyed || self.flrigPTTWatchdog != nil
                                  },
                                  owner: self, release: { [weak self] in self?.setPTT(false) })
    }

    deinit {
        pollingTask?.cancel()
        flrigPTTWatchdog?.cancel()
        tcpConnection?.cancel()
    }

    private var tx500Cancellables = Set<AnyCancellable>()
    private var icomUSBCancellables = Set<AnyCancellable>()
    private var fx4crCancellables = Set<AnyCancellable>()
    private var xiegu6100Cancellables = Set<AnyCancellable>()

    // MARK: - Connect & Disconnect
    public func connect() {
        rigctldRetryTask?.cancel()
        rigctldRetryTask = nil
        rigctldRetryAttempt = 0
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
        rigctldRetryTask?.cancel()
        rigctldRetryTask = nil
        if let endpoint = rigctldDesiredEndpoint, rigctldReplies?.hasTransmitRisk == true { rigctldUncertainEndpoints.insert(endpoint) }
        rigctldDesiredEndpoint = nil
        rigctldRecoveryReplies.removeAll()
        // A queued key-down must be followed by a release even if the operator disconnects immediately.
        if driverType == .flrig && isPTT { flrigEnqueue(.setPTT(false)) }
        flrigPTTWatchdog?.cancel()
        flrigPTTWatchdog = nil
        pollingTask?.cancel()
        pollingTask = nil
        if driverType == .rigctld, rigctldKeyed, let connection = tcpConnection {
            releaseRigctld(connection, endpoint: "\(host):\(port)", close: true)
        } else {
            tcpConnection?.cancel()
        }
        rigctldKeyed = false
        rigctldPTTWatchdog?.cancel()
        rigctldPTTWatchdog = nil
        tcpConnection = nil
        rigctldReplies = nil
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
        if driverType == .flrig {
            flrigLink = .idle
            flrigErrors = FlrigErrorState()
            lastError = nil
            flrigPTTWarning = nil
        }
    }

    public func toggleConnection() {
        if isConnected || isConnecting {
            disconnect()
        } else {
            connect()
        }
    }

    // MARK: - VFO Tuning & Commands
    @discardableResult
    public func tune(frequencyHz: UInt64, mode: String? = nil) -> String? {
        guard FrequencyBounds.isUsable(kHz: Double(frequencyHz) / 1000) else {
            lastError = "Radio was not tuned: invalid frequency."
            return lastError
        }
        guard driverType != .disabled, isConnected else {
            lastError = driverType == .disabled ? "Radio control is disabled; no tuning command was sent." : "CAT is offline; no tuning command was sent."
            return lastError
        }
        lastError = nil
        // Displayed frequency/mode come from telemetry, not an optimistic local assignment.

        if driverType == .flrig {
            // Queued here, not inside the Task below: flrig gets the commands in the order they were issued.
            flrigEnqueue(.setVFO(hz: Double(frequencyHz)))
            if let mode = mode, !mode.isEmpty { flrigEnqueue(.setMode(mode)) }
            return nil
        }

        switch driverType {
        case .flrig:
            break   // queued above
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
        return nil
    }

    public func tune(frequencyMHz: Double, mode: String? = nil) {
        guard let hz = FrequencyBounds.hertz(kHz: frequencyMHz * 1000) else {
            lastError = "Radio was not tuned: invalid frequency."
            return
        }
        tune(frequencyHz: hz, mode: mode)
    }

    public func setMode(_ newMode: String) {
        self.mode = newMode
        if driverType == .flrig {
            flrigEnqueue(.setMode(newMode))
            return
        }
        Task {
            switch driverType {
            case .flrig:
                break   // queued above
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
        if driverType == .flrig {
            flrigEnqueue(.setPower(watts: watts))
            return
        }
        Task {
            switch driverType {
            case .flrig:
                break   // queued above
            case .rigctld:
                let fraction = Double(watts) / 100.0
                sendRigctldCommand("L RFPOWER \(fraction)\n")
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
        if transmit {
            guard !TransmitShutdown.isShuttingDown else { return }
            guard isConnected else {
                lastError = TXLimits.notConnectedMessage(radio: driverType.rawValue)
                return
            }
            if driverType == .flrig, flrigPTTWatchdog != nil { return }
            if driverType == .rigctld, rigctldKeyed { return }
        }
        self.isPTT = transmit
        switch driverType {
        case .flrig:
            flrigEnqueue(.setPTT(transmit))
            flrigPTTWatchdog?.cancel()
            flrigPTTWatchdog = nil
            if transmit {
                let keyedAt = Date(), started = ProcessInfo.processInfo.systemUptime
                let release = capturePTTRelease()
                let radio = "flrig (\(host):\(port))"
                flrigPTTWatchdog = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(TXLimits.flrigPTT))
                    guard !Task.isCancelled, let self else { return }
                    release()
                    self.flrigPTTWatchdog = nil
                    if self.driverType == .disabled { self.isPTT = false }
                    let text = TXLimits.safetyTimerMessage(radio: radio, keyedAt: keyedAt, limit: TXLimits.flrigPTT,
                        elapsed: ProcessInfo.processInfo.systemUptime - started)
                    TransmitNotices.shared.post(self.noticeSource, text: text)
                }
            }
        case .rigctld:
            if transmit { sendRigctldCommand("T 1\n") }
            else { releaseRigctld(tcpConnection, endpoint: "\(host):\(port)") }
            rigctldKeyed = transmit
            rigctldPTTWatchdog?.cancel()
            rigctldPTTWatchdog = nil
            if transmit {
                let keyedAt = Date(), started = ProcessInfo.processInfo.systemUptime
                let release = capturePTTRelease()
                let radio = "Radio Control rigctld (\(host):\(port))"
                rigctldPTTWatchdog = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(TXLimits.rigctldPTT))
                    guard !Task.isCancelled, let self else { return }
                    release()
                    self.rigctldPTTWatchdog = nil
                    self.rigctldKeyed = false
                    if self.driverType == .disabled { self.isPTT = false }
                    let text = TXLimits.safetyTimerMessage(radio: radio, keyedAt: keyedAt, limit: TXLimits.rigctldPTT,
                        elapsed: ProcessInfo.processInfo.systemUptime - started)
                    TransmitNotices.shared.post(self.noticeSource, text: text)
                }
            }
        case .tx500: Lab599TX500Driver.shared.setPTT(transmit)
        case .icomUSB: IcomUSBRadioDriver.shared.setPTT(transmit)
        case .fx4cr: FX4CRDriver.shared.setPTT(transmit)
        case .xiegu6100: Xiegu6100Driver.shared.setPTT(transmit)
        case .disabled: break
        }
    }

    /// Snapshot the acquired destination: a later settings change must not send this transmission's release to a new radio.
    func capturePTTRelease() -> () -> Void {
        switch driverType {
        case .tx500: return { Lab599TX500Driver.shared.setPTT(false) }
        case .icomUSB: return { IcomUSBRadioDriver.shared.setPTT(false) }
        case .fx4cr: return { FX4CRDriver.shared.setPTT(false) }
        case .xiegu6100: return { Xiegu6100Driver.shared.setPTT(false) }
        case .flrig:
            let keyedHost = host, keyedPort = port
            return { [weak self] in
                guard let self else { return }
                self.flrigEnqueue(.setPTT(false), targetHost: keyedHost, targetPort: keyedPort)
                if self.driverType == .flrig, self.host == keyedHost, self.port == keyedPort {
                    self.flrigPTTWatchdog?.cancel()
                    self.flrigPTTWatchdog = nil
                    self.isPTT = false
                }
            }
        case .rigctld:
            let keyedConnection = tcpConnection
            let keyedReplies = rigctldReplies
            let endpoint = "\(host):\(port)"
            return { [weak self] in
                self?.releaseRigctld(keyedConnection, endpoint: endpoint, replies: keyedReplies)
                if let self, self.driverType == .rigctld, self.tcpConnection === keyedConnection {
                    self.rigctldPTTWatchdog?.cancel()
                    self.rigctldPTTWatchdog = nil
                    self.rigctldKeyed = false
                    self.isPTT = false
                }
            }
        case .disabled: return {}
        }
    }

    private func rigctldUncertain(_ reason: String, endpoint: String) {
        let text = "Radio Control rigctld (\(endpoint)): \(reason) at \(TXLimits.utc()). Receive is unconfirmed. Other YAAM tools remain available. Release PTT locally and check the radio is on receive before sending again."
        lastError = text
        TransmitNotices.shared.post(releaseNoticeSource, text: text)
    }

    private func releaseRigctld(_ connection: NWConnection?, endpoint: String, close: Bool = false, replies: RigctldReplyStream? = nil) {
        guard let connection, let reader = replies ?? rigctldReplies, reader.connection === connection else {
            rigctldUncertain("T 0 could not be sent because the connection is missing", endpoint: endpoint)
            return
        }
        reader.send("T 0\n", closeAfterRelease: close)
    }

    private func startTX500Integration() {
        let driver = Lab599TX500Driver.shared
        self.rigModel = "Lab599 TX-500"
        tx500Cancellables.removeAll()
        driver.$catError
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                if let error { self?.lastError = error }
            }
            .store(in: &tx500Cancellables)

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
        driver.$catError
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                if let error { self?.lastError = error }
            }
            .store(in: &icomUSBCancellables)

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
        let driver = FX4CRDriver.shared
        fx4crCancellables.removeAll()
        driver.$catError
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                if let error { self?.lastError = error }
            }
            .store(in: &fx4crCancellables)

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
        flrigLink = .idle
        flrigErrors = FlrigErrorState()
        flrigPTTWarning = nil
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }

                // A poll that is cancelled (Disconnect) throws and leaves without changing anything.
                do { try await self.pollFlrigTelemetry() } catch { return }
                try? await Task.sleep(nanoseconds: 600_000_000) // Poll every 600ms
            }
        }
    }

    private func pollFlrigTelemetry() async throws {
        // rig.get_xcvr does not touch the radio. "NONE" (no radio selected in flrig) and "" (a radio that never
        // answered) mean that flrig's other answers are made up (14070000, USB): they are not read, and YAAM is not
        // "connected". Nothing here can tell that a radio was switched off later; flrig keeps reporting its name and frequency.
        // After every await the task may have been cancelled (the user pressed Disconnect): then nothing is applied.
        let link = FlrigXMLRPC.link(forXcvr: try await flrigQuery(.getXcvr))
        if link != flrigLink {
            flrigLink = link
            flrigErrors.linkChanged()
            flrigLogOnce(link.problem)
            flrigPublishError()
        }
        guard let model = link.radioName else {
            self.isConnected = false
            return
        }
        self.rigModel = model
        self.isConnected = true
        self.isConnecting = false

        // 1. Frequency
        if let vfoStr = try await flrigText(.getVFO) {
            if let value = Double(vfoStr), let hz = FrequencyBounds.hertz(kHz: value / 1000) {
                self.frequencyHz = hz
            } else {
                flrigRefused(.getVFO, "Invalid VFO frequency from flrig")
            }
        }

        // 2. Mode
        if let clean = try await flrigText(.getMode), !clean.isEmpty { self.mode = clean }

        // 3. Power
        if let pwrStr = try await flrigText(.getPower), let p = Int(pwrStr) { self.powerWatts = p }

        // 4. S-Meter
        if let sStr = try await flrigText(.getSmeter), let val = Double(sStr) {
            self.sMeterValue = val.isFinite ? min(100.0, max(0.0, val)) * 15 / 100 : self.sMeterValue
        }

        // 5. PTT, only while a warning that the radio may be keyed is shown: flrig reporting PTT off ends it.
        if flrigErrors.pttWarning != nil, let ptt = try await flrigText(.getPTT).flatMap({ Int($0) }),
           flrigErrors.pttObserved(keyed: ptt == 1) {
            isPTT = false   // flrig reports PTT off: the warning ends
            flrigPublishError()
        }

        self.lastResponseTime = Date()
    }

    /// A query. nil = no usable HTTP answer. A fault comes back as .fault, never as a value, and is kept as the error.
    /// Throws only when the polling task was cancelled.
    private func flrigQuery(_ command: FlrigCommand) async throws -> FlrigReply? {
        let reply = try await FlrigTransport.send(command, host: host, port: port, timeout: 1.5)
        try Task.checkCancellation()
        if case .fault(_, let message)? = reply { flrigRefused(command, message) }
        return reply
    }

    private func flrigText(_ command: FlrigCommand) async throws -> String? {
        try await flrigQuery(command)?.text
    }

    /// A command for flrig, behind every command queued before it. Returns at once; the answer is handled when it comes.
    /// rig.set_ptt 0 is read back and repeated inside the same job (FlrigPTTRelease): the release stays the last
    /// command, and nothing else is sent between it, the read-back and the repeats.
    private func flrigEnqueue(_ command: FlrigCommand, targetHost: String? = nil, targetPort: Int? = nil) {
        let host = targetHost ?? self.host, port = targetPort ?? self.port
        flrigChain.enqueue {
            let send: FlrigSequences.Send = { await FlrigTransport.sendUncancelled($0, host: host, port: port, timeout: 1.5) }
            let outcome: FlrigOutcome
            if command.isPTTRelease {
                outcome = await FlrigPTTRelease.release(send: send, pause: { try? await Task.sleep(nanoseconds: $0) })
            } else {
                outcome = FlrigOutcome(method: command.method, reply: await send(command))
            }
            if await self.isCurrentFlrigEndpoint(host: host, port: port) { await self.flrigReport(outcome) }
        }
    }

    private func isCurrentFlrigEndpoint(host: String, port: Int) -> Bool {
        driverType == .flrig && self.host == host && self.port == port
    }

    /// A fault is kept as the error until flrig accepts a command or the link changes; it is not thrown away.
    /// A release that flrig did not confirm is kept as a warning and written to the system log.
    private func flrigReport(_ outcome: FlrigOutcome) {
        flrigErrors.record(outcome)
        flrigLogOnce(flrigErrors.commandFault)
        if let line = outcome.releaseCheck?.logLine { NSLog("[flrig] %@", line) }
        switch outcome.releaseCheck {
        case .stillKeyed?: isPTT = true    // flrig reports PTT on
        case .released?: isPTT = false     // flrig reports PTT off
        default: break
        }
        flrigPublishError()
    }

    private func flrigRefused(_ command: FlrigCommand, _ message: String) {
        flrigErrors.refused(command.method, message)
        flrigLogOnce(flrigErrors.commandFault)
        flrigPublishError()
    }

    /// lastError changes only when its text changes, so a problem that persists is not published at every poll.
    private func flrigPublishError() {
        let text = flrigErrors.text(for: flrigLink)
        if text != lastError { lastError = text }
        if flrigErrors.pttWarning != flrigPTTWarning { flrigPTTWarning = flrigErrors.pttWarning }
    }

    /// Writes a problem to the system log once, not at every poll.
    private func flrigLogOnce(_ problem: String?) {
        if let line = flrigErrors.newProblemToLog(problem) { NSLog("[flrig] %@", line) }
    }

    // MARK: - Hamlib rigctld TCP Engine
    private func startRigctldTCP() {
        rigctldRecoveryReplies.removeAll()
        if let old = rigctldReplies, old.hasTransmitRisk {
            if let endpoint = rigctldDesiredEndpoint { rigctldUncertainEndpoints.insert(endpoint) }
            old.send("\\stop_morse\nT 0\n", closeAfterRelease: true)
        } else { tcpConnection?.cancel() }

        let endpointHost = NWEndpoint.Host(host)
        guard (1...65_535).contains(port), let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)), !host.isEmpty else {
            isConnecting = false
            lastError = "Enter a valid rigctld host and port."
            return
        }

        let conn = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
        self.tcpConnection = conn
        let endpoint = "\(host):\(port)"
        rigctldDesiredEndpoint = endpoint
        let reader = RigctldReplyStream(conn)
        rigctldReplies = reader
        reader.onError = { [weak self, weak conn] reason, safety in
            if safety {
                self?.rigctldUncertainEndpoints.insert(endpoint)
                // A retired connection still owns its release warning.
                let text = "Radio Control rigctld (\(endpoint)): \(reason) at \(TXLimits.utc()). Receive is unconfirmed. Release PTT locally and check the original radio."
                TransmitNotices.shared.post(self?.releaseNoticeSource ?? TransmitNotices.Source(name: endpoint), text: text)
            }
            if let self, self.tcpConnection === conn { self.lastError = reason }
        }
        reader.onFailure = { [weak self, weak conn] reason, risk in
            guard let self, self.tcpConnection === conn else { return }
            if risk { self.rigctldUncertainEndpoints.insert(endpoint) }
            self.rigctldRecoveryReplies.removeAll()
            self.isConnected = false
            self.isConnecting = false
            self.lastError = reason
            self.pollingTask?.cancel()
            self.scheduleRigctldReconnect(endpoint: endpoint)
        }
        reader.onReply = { [weak self, weak conn] reply in
            guard let self, self.tcpConnection === conn else { return }
            if self.rigctldRecoveryReplies.contains(reply.command) {
                guard reply.result == 0 else { self.rigctldReplies?.fail("Recovery release refused; TX remains disabled."); return }
                self.rigctldRecoveryReplies.remove(reply.command)
                if self.rigctldRecoveryReplies.isEmpty {
                    self.rigctldUncertainEndpoints.remove(endpoint)
                    self.rigctldKeyed = false
                    self.isPTT = false
                    self.rigctldPTTWatchdog?.cancel()
                    self.rigctldPTTWatchdog = nil
                    self.isConnected = true
                    self.isConnecting = false
                    self.lastError = nil
                    self.startRigctldPolling()
                }
            }
            guard reply.result == 0 else { return }
            if reply.command == "get_freq" || reply.command == "get_mode" { self.rigctldRetryAttempt = 0 }
            if let value = reply.fields["Frequency"].flatMap(UInt64.init), value > 0 { self.frequencyHz = value }
            if let mode = reply.fields["Mode"] { self.mode = mode }
            self.lastResponseTime = Date()
        }

        conn.stateUpdateHandler = { [weak self, weak conn] state in
            Task { @MainActor [weak self, weak conn] in
                guard let self, let conn, self.tcpConnection === conn else { return }
                switch state {
                case .ready:
                    self.rigModel = "Hamlib Radio"
                    self.rigctldReplies?.start()
                    if self.rigctldUncertainEndpoints.contains(endpoint) {
                        self.rigctldRecoveryReplies = ["stop_morse", "set_ptt"]
                        self.isConnected = false
                        self.isConnecting = true
                        self.rigctldReplies?.send("\\stop_morse\nT 0\n")
                    } else {
                        self.isConnected = true
                        self.isConnecting = false
                        self.startRigctldPolling()
                    }
                case .failed(let err):
                    self.rigctldReplies?.fail("the connection failed during TX or release: \(err.localizedDescription)")
                    self.isConnected = false
                    self.isConnecting = false
                    self.lastError = err.localizedDescription
                    self.scheduleRigctldReconnect(endpoint: endpoint)
                case .waiting(let err):
                    self.rigctldReplies?.fail("rigctld is unavailable: \(err.localizedDescription)")
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

    private func scheduleRigctldReconnect(endpoint: String) {
        guard driverType == .rigctld, rigctldDesiredEndpoint == endpoint,
              "\(host):\(port)" == endpoint, rigctldRetryTask == nil,
              rigctldRetryAttempt < 5, !TransmitShutdown.isShuttingDown else { return }
        rigctldRetryAttempt += 1
        let delay = min(30, 1 << rigctldRetryAttempt)
        rigctldRetryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.rigctldDesiredEndpoint == endpoint,
                  self.driverType == .rigctld, "\(self.host):\(self.port)" == endpoint,
                  !Task.isCancelled else { return }
            self.rigctldRetryTask = nil
            self.startRigctldTCP()
        }
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
        guard isConnected, let reader = rigctldReplies else {
            lastError = "CAT command was not sent; no working rigctld connection."
            return
        }
        reader.send(command)
    }
}
