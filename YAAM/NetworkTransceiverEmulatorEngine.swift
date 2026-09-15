//
//  NetworkTransceiverEmulatorEngine.swift
//  YAAM
//
//  Created by factoreal on 9/13/26.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Activity Log Entry
nonisolated struct EmulatorActivityLog: Identifiable, Sendable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let category: LogCategory

    enum LogCategory: String, Sendable {
        case info = "INFO"
        case civ = "CI-V"
        case rigctld = "RIGCTLD"
        case audio = "AUDIO"
        case warning = "WARN"
        case error = "ERROR"

        var color: Color {
            switch self {
            case .info: return .blue
            case .civ: return .purple
            case .rigctld: return .teal
            case .audio: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
    }
}

// MARK: - Thread-Safe Transceiver State Cache
nonisolated final class TransceiverStateCache: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var _frequencyHz: UInt64 = 14_074_000
    private var _mode: String = "USB-D"
    private var _filterWidth: Int = 3000
    private var _isTransmitting: Bool = false
    private var _sMeterUnits: Double = 7.0
    private var _rfPowerWatts: Double = 0.0
    private var _swr: Double = 1.05
    private var _alcLevel: Double = 0.0
    private var _vfoSelected: String = "VFO A"

    var vfoSelected: String {
        get { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _vfoSelected }
        set { os_unfair_lock_lock(&lock); _vfoSelected = newValue; os_unfair_lock_unlock(&lock) }
    }

    var frequencyHz: UInt64 {
        get { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _frequencyHz }
        set { os_unfair_lock_lock(&lock); _frequencyHz = newValue; os_unfair_lock_unlock(&lock) }
    }

    var mode: String {
        get { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _mode }
        set { os_unfair_lock_lock(&lock); _mode = newValue; os_unfair_lock_unlock(&lock) }
    }

    var filterWidth: Int {
        get { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _filterWidth }
        set { os_unfair_lock_lock(&lock); _filterWidth = newValue; os_unfair_lock_unlock(&lock) }
    }

    var isTransmitting: Bool {
        get { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _isTransmitting }
        set { os_unfair_lock_lock(&lock); _isTransmitting = newValue; os_unfair_lock_unlock(&lock) }
    }

    var sMeterUnits: Double {
        get { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _sMeterUnits }
        set { os_unfair_lock_lock(&lock); _sMeterUnits = newValue; os_unfair_lock_unlock(&lock) }
    }

    var rfPowerWatts: Double {
        get { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _rfPowerWatts }
        set { os_unfair_lock_lock(&lock); _rfPowerWatts = newValue; os_unfair_lock_unlock(&lock) }
    }

    var swr: Double {
        get { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _swr }
        set { os_unfair_lock_lock(&lock); _swr = newValue; os_unfair_lock_unlock(&lock) }
    }

    var alcLevel: Double {
        get { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _alcLevel }
        set { os_unfair_lock_lock(&lock); _alcLevel = newValue; os_unfair_lock_unlock(&lock) }
    }
}

// MARK: - Central Network Transceiver Emulator Engine
@MainActor
final class NetworkTransceiverEmulatorEngine: ObservableObject {
    // Thread-safe fast cache for network socket threads
    nonisolated let stateCache = TransceiverStateCache()

    // Hardware State
    @Published var isServerRunning = false
    @Published var model: IcomNetworkModel = .ic705 {
        didSet {
            icomServer.radioModel = model
            icomServer.radioName = "\(model.rawValue)-NTE"
        }
    }
    private var isClientOriginatingUpdate = false
    @Published var frequencyHz: UInt64 = 14_074_000 { // 20m FT8
        didSet {
            stateCache.frequencyHz = frequencyHz
            guard !isClientOriginatingUpdate else { return }
            icomServer.broadcastFrequency(frequencyHz)
        }
    }
    @Published var mode: String = "USB-D" {
        didSet {
            stateCache.mode = mode
            guard !isClientOriginatingUpdate else { return }
            icomServer.broadcastMode(mode)
        }
    }
    @Published var filterWidth: Int = 3000
    @Published var isTransmitting: Bool = false
    @Published var vfoSelected: String = "VFO A"

    // Metering & Telemetry
    @Published var rfPowerWatts: Double = 0.0
    @Published var sMeterUnits: Double = 7.0
    @Published var swr: Double = 1.05
    @Published var alcLevel: Double = 0.0
    @Published var preamp: Int = 1 // P.AMP 1
    @Published var agcSpeed: String = "FAST"
    @Published var tunerActive: Bool = true

    // Server Port Settings
    @Published var controlPort: Int = 50001
    @Published var civPort: Int = 50002
    @Published var audioPort: Int = 50003
    @Published var rigctldPort: Int = 4532
    @Published var username: String = "yaam"
    @Published var password: String = "yaam"

    // Client Sessions
    @Published var connectedClients: [IcomClientSession] = []
    @Published var rigctldClientCount: Int = 0

    // Visual Spectrum
    @Published var liveSpectrumMagnitudes: [Float] = []
    var isSpectrumVisualizerActive: Bool = false {
        didSet {
            rfEngine.isSpectrumActive = isSpectrumVisualizerActive
            if !isSpectrumVisualizerActive && !liveSpectrumMagnitudes.isEmpty {
                liveSpectrumMagnitudes.removeAll()
            }
        }
    }

    // Activity Log Console
    @Published var activityLogs: [EmulatorActivityLog] = []

    // Active Synthetic Signals
    @Published var activeSignals: [SyntheticSignalProfile] = []

    // Subcomponents
    let icomServer = IcomNetworkServer()
    let rigctldServer = HamlibRigctldServer()
    let rfEngine = SyntheticRFSignalEngine()
    let tester = NetworkTransceiverAutomatedTester()

    // Meter Animation Timer
    private var telemetryTimer: AnyCancellable?

    nonisolated static func encodeBCD2Bytes(_ value: Int) -> [UInt8] {
        let clamped = max(0, min(9999, value))
        let thousands = (clamped / 1000) % 10
        let hundreds = (clamped / 100) % 10
        let tens = (clamped / 10) % 10
        let ones = clamped % 10
        let byte0 = UInt8((thousands << 4) | hundreds)
        let byte1 = UInt8((tens << 4) | ones)
        return [byte0, byte1]
    }

    init() {
        configureSubcomponents()
        rfEngine.setupDefaultSignals()
        if UserDefaults.standard.bool(forKey: "networkTransceiverEmulatorAutoStart") {
            DispatchQueue.main.async { [weak self] in
                self?.startServers()
            }
        }
    }

    private func configureSubcomponents() {
        // --- Connect Icom Server Callbacks (Non-blocking via thread-safe stateCache) ---
        icomServer.getFrequency = { [weak self] in
            self?.stateCache.frequencyHz ?? 14_074_000
        }

        icomServer.setFrequency = { [weak self] newFreq in
            guard let self else { return }
            self.stateCache.frequencyHz = newFreq
            DispatchQueue.main.async {
                self.isClientOriginatingUpdate = true
                self.frequencyHz = newFreq
                self.isClientOriginatingUpdate = false
                self.appendLog("CI-V frequency tuned to \(AmateurBandPlan.formattedMHz(Double(newFreq) / 1_000_000))", category: .civ)
            }
        }

        icomServer.getMode = { [weak self] in
            self?.stateCache.mode ?? "USB-D"
        }

        icomServer.setMode = { [weak self] newMode in
            guard let self else { return }
            self.stateCache.mode = newMode
            DispatchQueue.main.async {
                self.isClientOriginatingUpdate = true
                self.mode = newMode
                self.isClientOriginatingUpdate = false
                self.appendLog("CI-V operating mode changed to \(newMode)", category: .civ)
            }
        }

        icomServer.getVFO = { [weak self] in
            self?.stateCache.vfoSelected ?? "VFO A"
        }

        icomServer.setVFO = { [weak self] vfo in
            guard let self else { return }
            self.stateCache.vfoSelected = vfo
            DispatchQueue.main.async {
                self.vfoSelected = vfo
                self.appendLog("CI-V selected \(vfo)", category: .civ)
            }
        }

        icomServer.getPTT = { [weak self] in
            self?.stateCache.isTransmitting ?? false
        }

        icomServer.setPTT = { [weak self] isTX in
            guard let self else { return }
            self.stateCache.isTransmitting = isTX
            if !isTX {
                self.stateCache.rfPowerWatts = 0.0
                self.stateCache.alcLevel = 0.0
            }
            DispatchQueue.main.async {
                self.isTransmitting = isTX
                self.appendLog("CI-V PTT \(isTX ? "KEYED [TX ACTIVE]" : "RELEASED [RX]")", category: .civ)
                if !isTX {
                    self.rfPowerWatts = 0.0
                    self.alcLevel = 0.0
                }
            }
        }

        icomServer.getSMeterBCD = { [weak self] in
            guard let self else { return [0x00, 0x80] }
            let units = self.stateCache.sMeterUnits
            let raw: Int
            if units <= 9.0 {
                raw = Int(round((max(0.0, units) / 9.0) * 120.0))
            } else {
                raw = Int(round(120.0 + ((min(15.0, units) - 9.0) / 6.0) * 121.0))
            }
            return Self.encodeBCD2Bytes(raw)
        }

        icomServer.getPowerMeterBCD = { [weak self] in
            guard let self else { return [0x00, 0x00] }
            guard self.stateCache.isTransmitting else { return [0x00, 0x00] }
            let raw = Int(round((min(100.0, max(0.0, self.stateCache.rfPowerWatts)) / 100.0) * 143.0))
            return Self.encodeBCD2Bytes(raw)
        }

        icomServer.getSWRMeterBCD = { [weak self] in
            guard let self else { return [0x00, 0x00] }
            guard self.stateCache.isTransmitting else { return [0x00, 0x00] }
            let swr = self.stateCache.swr
            let raw: Int
            if swr <= 1.0 {
                raw = 0
            } else if swr <= 1.5 {
                raw = Int(round((swr - 1.0) / 0.5 * 48.0))
            } else if swr <= 2.0 {
                raw = Int(round(48.0 + (swr - 1.5) / 0.5 * 32.0))
            } else {
                raw = Int(round(80.0 + min(2.0, swr - 2.0) * 40.0))
            }
            return Self.encodeBCD2Bytes(raw)
        }

        icomServer.getALCMeterBCD = { [weak self] in
            guard let self else { return [0x00, 0x00] }
            guard self.stateCache.isTransmitting else { return [0x00, 0x00] }
            let raw = Int(round((min(100.0, max(0.0, self.stateCache.alcLevel)) / 100.0) * 120.0))
            return Self.encodeBCD2Bytes(raw)
        }

        icomServer.onClientTXAudioReceived = { [weak self] samples in
            guard let self, !samples.isEmpty else { return }
            var sum: Float = 0.0
            for s in samples { sum += s * s }
            let rms = sqrt(sum / Float(samples.count))
            let watts = Double(min(100.0, max(0.0, rms * 150.0)))
            let power = round(watts * 10) / 10.0
            let alc = round(Double(min(100.0, rms * 100.0)))

            self.stateCache.rfPowerWatts = power
            self.stateCache.alcLevel = alc

            DispatchQueue.main.async {
                self.rfPowerWatts = power
                self.alcLevel = alc
            }
        }

        icomServer.onClientSessionChanged = { [weak self] sessions in
            DispatchQueue.main.async {
                self?.connectedClients = sessions
            }
        }

        icomServer.onLogMessage = { [weak self] msg in
            DispatchQueue.main.async {
                self?.appendLog(msg, category: .civ)
            }
        }

        icomServer.setRFPowerWatts = { [weak self] watts in
            guard let self else { return }
            self.stateCache.rfPowerWatts = watts
            DispatchQueue.main.async {
                self.rfPowerWatts = watts
                self.appendLog("CI-V RF Power set to \(Int(watts))W", category: .civ)
            }
        }

        // --- Connect Hamlib Rigctld Callbacks ---
        rigctldServer.getFrequency = { [weak self] in
            self?.stateCache.frequencyHz ?? 14_074_000
        }

        rigctldServer.setFrequency = { [weak self] newFreq in
            guard let self else { return }
            self.stateCache.frequencyHz = newFreq
            DispatchQueue.main.async {
                self.frequencyHz = newFreq
                self.appendLog("rigctld tuned to \(AmateurBandPlan.formattedMHz(Double(newFreq) / 1_000_000))", category: .rigctld)
            }
        }

        rigctldServer.getMode = { [weak self] in
            guard let self else { return ("PKTUSB", 3000) }
            let m = self.stateCache.mode == "USB-D" ? "PKTUSB" : self.stateCache.mode
            return (m, self.stateCache.filterWidth)
        }

        rigctldServer.setMode = { [weak self] newMode, width in
            guard let self else { return }
            let canonicalMode = newMode == "PKTUSB" ? "USB-D" : newMode
            self.stateCache.mode = canonicalMode
            self.stateCache.filterWidth = width
            DispatchQueue.main.async {
                self.mode = canonicalMode
                self.filterWidth = width
                self.appendLog("rigctld set mode to \(newMode) (BW: \(width) Hz)", category: .rigctld)
            }
        }

        rigctldServer.getPTT = { [weak self] in
            self?.stateCache.isTransmitting ?? false
        }

        rigctldServer.setPTT = { [weak self] isTX in
            guard let self else { return }
            self.stateCache.isTransmitting = isTX
            DispatchQueue.main.async {
                self.isTransmitting = isTX
                self.appendLog("rigctld PTT \(isTX ? "ON" : "OFF")", category: .rigctld)
            }
        }

        rigctldServer.getSMeterDB = { [weak self] in
            guard let self else { return -10.0 }
            return (self.stateCache.sMeterUnits - 9.0) * 6.0
        }

        rigctldServer.onClientCountChanged = { [weak self] count in
            DispatchQueue.main.async {
                self?.rigctldClientCount = count
            }
        }

        rigctldServer.onLogMessage = { [weak self] msg in
            DispatchQueue.main.async {
                self?.appendLog(msg, category: .rigctld)
            }
        }

        // --- Connect Synthetic RF Signal Engine to Icom Audio Stream ---
        rfEngine.onFrameGenerated = { [weak self] audioFrame in
            self?.icomServer.sendAudioFrame(audioFrame)
        }

        rfEngine.onSpectrumCalculated = { [weak self] spectrum in
            DispatchQueue.main.async {
                guard let self, self.isSpectrumVisualizerActive else { return }
                self.liveSpectrumMagnitudes = spectrum
            }
        }

        rfEngine.onSignalsChanged = { [weak self] signals in
            DispatchQueue.main.async {
                self?.activeSignals = signals
            }
        }
    }

    private func startTelemetryLoop() {
        telemetryTimer?.cancel()
        telemetryTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isServerRunning else { return }
                if !self.isTransmitting {
                    let noise = Double.random(in: -0.3...0.3)
                    let base = 5.0 + (self.rfEngine.targetSNR * 0.15)
                    let sUnits = max(1.0, min(15.0, base + noise))
                    self.sMeterUnits = sUnits
                    self.stateCache.sMeterUnits = sUnits
                } else {
                    self.sMeterUnits = 15.0
                    self.stateCache.sMeterUnits = 15.0
                    let swrVal = 1.05 + Double.random(in: 0.0...0.06)
                    self.swr = swrVal
                    self.stateCache.swr = swrVal
                }
            }
    }

    // MARK: - Lifecycle Controls
    func startServers() {
        guard !isServerRunning else { return }
        do {
            stateCache.frequencyHz = frequencyHz
            stateCache.mode = mode
            stateCache.filterWidth = filterWidth
            stateCache.isTransmitting = isTransmitting
            stateCache.sMeterUnits = sMeterUnits
            stateCache.rfPowerWatts = rfPowerWatts
            stateCache.swr = swr

            icomServer.controlPort = UInt16(controlPort)
            icomServer.civPort = UInt16(civPort)
            icomServer.audioPort = UInt16(audioPort)
            icomServer.username = username
            icomServer.password = password
            icomServer.radioModel = model
            icomServer.radioName = "\(model.rawValue)-NTE"

            try icomServer.start()
            try rigctldServer.start(port: UInt16(rigctldPort))
            rfEngine.start()
            startTelemetryLoop()

            isServerRunning = true
            UserDefaults.standard.set(true, forKey: "networkTransceiverEmulatorAutoStart")
            appendLog("Network Transceiver Emulator online: Icom CI-V/Audio and Hamlib rigctld ready", category: .info)
        } catch {
            appendLog("Failed to start emulator: \(error.localizedDescription)", category: .error)
        }
    }

    func stopServers() {
        guard isServerRunning else { return }
        UserDefaults.standard.set(false, forKey: "networkTransceiverEmulatorAutoStart")
        telemetryTimer?.cancel()
        telemetryTimer = nil
        icomServer.stop()
        rigctldServer.stop()
        rfEngine.stop()
        isServerRunning = false
        connectedClients.removeAll()
        rigctldClientCount = 0
        isTransmitting = false
        rfPowerWatts = 0.0
        stateCache.isTransmitting = false
        stateCache.rfPowerWatts = 0.0
        appendLog("Network Transceiver Emulator offline", category: .info)
    }

    func togglePTT() {
        isTransmitting.toggle()
        stateCache.isTransmitting = isTransmitting
        appendLog("Front panel PTT toggled to \(isTransmitting ? "TX" : "RX")", category: .info)
        if !isTransmitting {
            rfPowerWatts = 0.0
            alcLevel = 0.0
            stateCache.rfPowerWatts = 0.0
            stateCache.alcLevel = 0.0
        } else {
            rfPowerWatts = 100.0
            alcLevel = 45.0
            stateCache.rfPowerWatts = 100.0
            stateCache.alcLevel = 45.0
        }
        icomServer.broadcastPTT(isTransmitting)
    }

    func setFrequencyHz(_ freq: UInt64) {
        guard freq > 0 else { return }
        frequencyHz = freq
        stateCache.frequencyHz = freq
        appendLog("Front panel frequency set to \(AmateurBandPlan.formattedMHz(Double(freq) / 1_000_000))", category: .info)
    }

    func stepFrequency(hz: Int64) {
        let current = Int64(frequencyHz)
        let updated = max(100_000, current + hz)
        setFrequencyHz(UInt64(updated))
    }

    func selectBand(_ band: AmateurBandDefinition) {
        // Quick default FT8 frequencies per band
        let bandFreqs: [String: UInt64] = [
            "160m": 1_840_000,
            "80m": 3_573_000,
            "60m": 5_357_000,
            "40m": 7_074_000,
            "30m": 10_136_000,
            "20m": 14_074_000,
            "17m": 18_100_000,
            "15m": 21_074_000,
            "12m": 24_915_000,
            "10m": 28_074_000,
            "6m": 50_313_000,
            "2m": 144_174_000,
            "70cm": 432_174_000
        ]

        let canonical = band.id.lowercased()
        if let defaultHz = bandFreqs[canonical] {
            setFrequencyHz(defaultHz)
        } else {
            for (range, name) in AmateurBandPlan.ranges {
                if name.lowercased() == canonical {
                    setFrequencyHz(UInt64(range.lowerBound * 1_000_000))
                    return
                }
            }
        }
    }

    private var pendingLogs: [EmulatorActivityLog] = []
    private var logFlushScheduled = false

    func appendLog(_ message: String, category: EmulatorActivityLog.LogCategory = .info) {
        let entry = EmulatorActivityLog(message: message, category: category)
        pendingLogs.append(entry)
        if pendingLogs.count > 100 {
            pendingLogs.removeFirst(pendingLogs.count - 100)
        }
        guard !logFlushScheduled else { return }
        logFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.logFlushScheduled = false
            guard !self.pendingLogs.isEmpty else { return }
            self.activityLogs.append(contentsOf: self.pendingLogs)
            self.pendingLogs.removeAll()
            if self.activityLogs.count > 200 {
                self.activityLogs.removeFirst(self.activityLogs.count - 200)
            }
        }
    }

    func clearLogs() {
        activityLogs.removeAll()
    }

    // MARK: - Synthetic Signal Management
    func addSyntheticSignal(_ sig: SyntheticSignalProfile) {
        rfEngine.addSignal(sig)
        appendLog("Injected synthetic signal: \(sig.message) (\(Int(sig.baseAudioFrequencyHz)) Hz, \(Int(sig.snrDB)) dB)", category: .info)
    }

    func removeSyntheticSignal(id: UUID) {
        rfEngine.removeSignal(id: id)
    }

    func toggleSyntheticSignal(id: UUID) {
        rfEngine.toggleSignal(id: id)
    }

    func clearSyntheticSignals() {
        rfEngine.clearSignals()
        appendLog("Cleared all synthetic signals", category: .info)
    }

    func resetDefaultSignals() {
        rfEngine.setupDefaultSignals()
        appendLog("Reset synthetic signals to default DX & FT8 test set", category: .info)
    }

    func setSyntheticSignals(_ signals: [SyntheticSignalProfile]) {
        rfEngine.setSignals(signals)
    }
}
