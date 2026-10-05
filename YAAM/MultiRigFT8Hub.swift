//
//  MultiRigFT8Hub.swift
//  YAAM
//
//  Multi-Transceiver FT8 Hub & Cluster Orchestrator (SO2R / SO3R / Multi-Rig FT8)
//  Coordinates multiple simultaneous transceivers (e.g. Icom LAN, Icom USB, Lab599 TX-500,
//  FX-4CR, Xiegu X6100, Hamlib rigctld, and Network-Attached Transceiver Emulator)
//  operating on independent amateur bands (e.g. 20m, 40m, 10m) with strict
//  cross-rig transmit interlock coordination and unified SQLite logbook integration.
//

import Combine
import CoreAudio
import Foundation
import SwiftUI
import FT8808Engine

// MARK: - Transceiver Driver Type

enum RadioDriverType: String, CaseIterable, Identifiable, Codable, Sendable {
    case icomLAN = "Direct Icom LAN (UDP)"
    case icomUSB = "Icom USB (CI-V + Audio)"
    case lab599TX500 = "Lab599 Discovery TX-500"
    case fx4cr = "FX-4CR (USB / Bluetooth)"
    case xiegu6100 = "Xiegu X6100 (USB-C)"
    case coreAudioRigctld = "Hamlib rigctld + CoreAudio"
    case transceiverEmulator = "Internal Transceiver Emulator"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .icomLAN: return "Icom LAN"
        case .icomUSB: return "Icom USB"
        case .lab599TX500: return "TX-500"
        case .fx4cr: return "FX-4CR"
        case .xiegu6100: return "X6100"
        case .coreAudioRigctld: return "rigctld"
        case .transceiverEmulator: return "Emulator"
        }
    }

    var icon: String {
        switch self {
        case .icomLAN: return "network"
        case .icomUSB: return "cable.connector"
        case .lab599TX500: return "antenna.radiowaves.left.and.right"
        case .fx4cr: return "bolt.shield"
        case .xiegu6100: return "radio"
        case .coreAudioRigctld: return "server.rack"
        case .transceiverEmulator: return "cpu"
        }
    }
}

// MARK: - Cross-Rig Transmit Interlock Policy

enum MultiRigInterlockPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case concurrent = "Concurrent TX (Unrestricted)"
    case strictLockout = "Strict Lockout (First-Come, First-Served)"
    case alternatingSlots = "Alternating Slots (Even/Odd SO2R)"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .concurrent: return "bolt.horizontal.fill"
        case .strictLockout: return "lock.shield.fill"
        case .alternatingSlots: return "clock.arrow.circlepath"
        }
    }

    var shortTitle: String {
        switch self {
        case .concurrent: return "TX Unrestricted"
        case .strictLockout: return "Strict Lockout"
        case .alternatingSlots: return "Alternating Slots"
        }
    }

    var summary: String {
        switch self {
        case .concurrent: return "All rigs can transmit at any time. Requires band-pass filters."
        case .strictLockout: return "Only one rig transmits at a time. Other transmitters defer."
        case .alternatingSlots: return "Rig 1 keys on Even slots (:00/:30), Rig 2 on Odd (:15/:45)."
        }
    }
}

// MARK: - Multi-Rig Console Layout Mode

enum MultiRigLayoutMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case tripleColumn = "3-Column Parallel"
    case heroAndSub = "Hero + 2 Sub-Rigs"
    case dualSplit = "Dual Split (50/50)"
    case quadGrid = "Quad Matrix (2x2)"
    case focusedSingle = "Focused Single Rig"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tripleColumn: return "rectangle.split.3x1"
        case .heroAndSub: return "rectangle.split.1x2"
        case .dualSplit: return "rectangle.split.2x1"
        case .quadGrid: return "square.grid.2x2"
        case .focusedSingle: return "rectangle"
        }
    }

    var shortTitle: String {
        switch self {
        case .tripleColumn: return "3-Column"
        case .heroAndSub: return "Hero + 2 Sub"
        case .dualSplit: return "Dual Split"
        case .quadGrid: return "Quad (2x2)"
        case .focusedSingle: return "Single Rig"
        }
    }
}

// MARK: - Cross-Rig Transmit Interlock Coordinator

@MainActor
final class MultiRigInterlockCoordinator: ObservableObject {
    @Published private(set) var activeTransmittingSlotID: UUID?
    @Published private(set) var activeTransmittingSlotName: String?
    @Published private(set) var lastInterlockConflict: String?

    var policy: MultiRigInterlockPolicy = .strictLockout

    func requestTransmit(slotID: UUID, slotName: String, slotIndex: Int) -> Bool {
        switch policy {
        case .concurrent:
            activeTransmittingSlotID = slotID
            activeTransmittingSlotName = slotName
            return true

        case .strictLockout:
            if let active = activeTransmittingSlotID, active != slotID {
                lastInterlockConflict = "Interlock held by \(activeTransmittingSlotName ?? "another rig"); Slot \(slotIndex) deferred"
                return false
            }
            activeTransmittingSlotID = slotID
            activeTransmittingSlotName = slotName
            return true

        case .alternatingSlots:
            let parity = DigitalSlotClock.parity(at: Date())
            if slotIndex == 1 {
                if parity != .even {
                    lastInterlockConflict = "Slot 1 reserved for Even slots (:00/:30)"
                    return false
                }
            } else if slotIndex == 2 {
                if parity != .odd {
                    lastInterlockConflict = "Slot 2 reserved for Odd slots (:15/:45)"
                    return false
                }
            }
            if let active = activeTransmittingSlotID, active != slotID {
                lastInterlockConflict = "Interlock held by \(activeTransmittingSlotName ?? "another rig")"
                return false
            }
            activeTransmittingSlotID = slotID
            activeTransmittingSlotName = slotName
            return true
        }
    }

    func releaseTransmit(slotID: UUID) {
        if activeTransmittingSlotID == slotID {
            activeTransmittingSlotID = nil
            activeTransmittingSlotName = nil
        }
    }

    func reset() {
        activeTransmittingSlotID = nil
        activeTransmittingSlotName = nil
        lastInterlockConflict = nil
    }
}

// MARK: - Multi-Rig Slot Configuration Model

struct MultiRigSlotConfig: Codable, Identifiable, Sendable {
    var id: UUID
    var slotIndex: Int
    var name: String
    var driverType: RadioDriverType
    var dialFrequencyHz: UInt64
    var audioInputDeviceUID: String
    var audioOutputDeviceUID: String
    var icomHost: String
    var icomPort: Int
    var icomUsername: String
    var icomModelName: String
    var rigctldHost: String
    var rigctldPort: Int
    var serialPort: String
    var baudRate: Int
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        slotIndex: Int,
        name: String,
        driverType: RadioDriverType,
        dialFrequencyHz: UInt64,
        audioInputDeviceUID: String = "",
        audioOutputDeviceUID: String = "",
        icomHost: String = "127.0.0.1",
        icomPort: Int = 50001,
        icomUsername: String = "admin",
        icomModelName: String = "IC-7300MK2",
        rigctldHost: String = "127.0.0.1",
        rigctldPort: Int = 4532,
        serialPort: String = "",
        baudRate: Int = 115200,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.slotIndex = slotIndex
        self.name = name
        self.driverType = driverType
        self.dialFrequencyHz = dialFrequencyHz
        self.audioInputDeviceUID = audioInputDeviceUID
        self.audioOutputDeviceUID = audioOutputDeviceUID
        self.icomHost = icomHost
        self.icomPort = icomPort
        self.icomUsername = icomUsername
        self.icomModelName = icomModelName
        self.rigctldHost = rigctldHost
        self.rigctldPort = rigctldPort
        self.serialPort = serialPort
        self.baudRate = baudRate
        self.isEnabled = isEnabled
    }
}

// MARK: - Multi-Rig Slot (Live Operational Entity)

@MainActor
final class MultiRigSlot: ObservableObject, Identifiable {
    let id: UUID
    let slotIndex: Int
    @Published var name: String
    @Published var driverType: RadioDriverType
    @Published var dialFrequencyHz: UInt64
    @Published var audioInputDeviceUID: String
    @Published var audioOutputDeviceUID: String

    // Icom LAN Dedicated Config
    @Published var icomHost: String
    @Published var icomPort: Int
    @Published var icomUsername: String
    @Published var icomPassword: String = ""
    @Published var icomModel: IcomNetworkModel = .ic7300MK2

    // rigctld Dedicated Config
    @Published var rigctldHost: String
    @Published var rigctldPort: Int

    // Serial CAT Config
    @Published var serialPort: String
    @Published var baudRate: Int

    @Published var isEnabled: Bool = true
    @Published var isMonitoring: Bool = false
    @Published var isConnected: Bool = false
    @Published var slotStatusMessage: String = "Ready"

    // Dedicated Independent Engines & Hardware Clients
    var engine: FT8EngineService
    var dedicatedIcomRadio: IcomNetworkRadio?
    var dedicatedRigClient: RigControlClient?

    private var cancellables: Set<AnyCancellable> = []

    init(config: MultiRigSlotConfig) {
        self.id = config.id
        self.slotIndex = config.slotIndex
        self.name = config.name
        self.driverType = config.driverType
        self.dialFrequencyHz = config.dialFrequencyHz
        self.audioInputDeviceUID = config.audioInputDeviceUID
        self.audioOutputDeviceUID = config.audioOutputDeviceUID
        self.icomHost = config.icomHost
        self.icomPort = config.icomPort
        self.icomUsername = config.icomUsername
        self.icomModel = IcomNetworkModel(rawValue: config.icomModelName) ?? .ic7300MK2
        self.rigctldHost = config.rigctldHost
        self.rigctldPort = config.rigctldPort
        self.serialPort = config.serialPort
        self.baudRate = config.baudRate
        self.isEnabled = config.isEnabled

        // Create independent FT8 DSP modem engine for this slot
        let newEngine = FT8EngineService()
        newEngine.radioInstanceName = config.name
        newEngine.dialFrequencyHz = config.dialFrequencyHz
        self.engine = newEngine

        bindEngine()
    }

    private func bindEngine() {
        engine.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.isMonitoring = state.isMonitoring
                switch state {
                case .idle:
                    self.slotStatusMessage = "Idle"
                case .monitoring:
                    self.slotStatusMessage = "Monitoring \(self.bandName)"
                case .waiting(let date):
                    let df = DateFormatter()
                    df.dateFormat = "HH:mm:ss"
                    df.timeZone = TimeZone(secondsFromGMT: 0)
                    self.slotStatusMessage = "Waiting for \(df.string(from: date)) UTC"
                case .transmitting:
                    self.slotStatusMessage = "Transmitting on \(self.bandName)!"
                case .failed(let err):
                    self.slotStatusMessage = "Error: \(err)"
                }
            }
            .store(in: &cancellables)
    }

    var bandName: String {
        if let preset = FT8BandPreset.common.first(where: { $0.frequencyHz == dialFrequencyHz }) {
            return preset.band
        }
        let mhz = Double(dialFrequencyHz) / 1_000_000.0
        return AmateurBandPlan.band(forMHz: mhz) ?? "\(String(format: "%.3f", mhz)) MHz"
    }

    var formattedDialMHz: String {
        AmateurBandPlan.formattedMHz(Double(dialFrequencyHz) / 1_000_000.0)
    }

    func setBandPreset(_ preset: FT8BandPreset) {
        dialFrequencyHz = preset.frequencyHz
        engine.dialFrequencyHz = preset.frequencyHz
        if isMonitoring {
            engine.applyDialAndMode()
        }
    }

    func connectAndStartMonitoring(appState: AppState?) {
        guard isEnabled else { return }

        // Configure callsign & grid identity
        if let call = appState?.currentStationCallsign, !call.isEmpty, call != "DEFAULT" {
            let grid = appState?.activeStationProfile?.normalizedGrid ?? ""
            engine.configureStation(callsign: call, grid: grid)
        }

        engine.dialFrequencyHz = dialFrequencyHz

        switch driverType {
        case .icomLAN:
            let radio = dedicatedIcomRadio ?? IcomNetworkRadio()
            dedicatedIcomRadio = radio
            engine.audioPath = .icomLAN
            let settings = IcomNetworkSettings(
                host: icomHost.isEmpty ? "127.0.0.1" : icomHost,
                controlPort: icomPort > 0 ? icomPort : 50001,
                username: icomUsername.isEmpty ? "admin" : icomUsername,
                clientName: "YAAM-Slot\(slotIndex)",
                model: icomModel
            )
            let vaultPwd = CredentialVault.valueIfAvailableWithoutPrompt(for: .icomNetworkPassword)
            let pwd = icomPassword.isEmpty ? (vaultPwd.isEmpty ? "admin" : vaultPwd) : icomPassword
            if !radio.state.isConnected {
                radio.connect(settings: settings, password: pwd)
            }
            isConnected = true
            engine.startIcomMonitoring(radio: radio)

        case .coreAudioRigctld:
            let rig = dedicatedRigClient ?? RigControlClient()
            dedicatedRigClient = rig
            engine.audioPath = .coreAudio
            if !rig.state.isConnected {
                rig.connect(host: rigctldHost.isEmpty ? "127.0.0.1" : rigctldHost, port: rigctldPort > 0 ? rigctldPort : 4532)
            }
            isConnected = true
            let inUID = audioInputDeviceUID.isEmpty ? nil : audioInputDeviceUID
            let outUID = audioOutputDeviceUID.isEmpty ? nil : audioOutputDeviceUID
            engine.startCoreAudioMonitoring(rig: rig, inputDevice: inUID, outputDevice: outUID)

        case .lab599TX500:
            engine.audioPath = .lab599TX500
            let tx500 = Lab599TX500Driver.shared
            if !serialPort.isEmpty { tx500.selectedPort = serialPort }
            if baudRate > 0 { tx500.baudRate = baudRate }
            if !tx500.isConnected { tx500.connect() }
            isConnected = tx500.isConnected
            let inUID = audioInputDeviceUID.isEmpty ? nil : audioInputDeviceUID
            let outUID = audioOutputDeviceUID.isEmpty ? nil : audioOutputDeviceUID
            engine.startTX500Monitoring(inputDevice: inUID, outputDevice: outUID)

        case .icomUSB:
            engine.audioPath = .icomUSB
            let icomUSB = IcomUSBRadioDriver.shared
            if !serialPort.isEmpty { icomUSB.selectedPort = serialPort }
            if baudRate > 0 { icomUSB.baudRate = baudRate }
            if !icomUSB.isConnected { icomUSB.connect() }
            isConnected = icomUSB.isConnected
            let inUID = audioInputDeviceUID.isEmpty ? nil : audioInputDeviceUID
            let outUID = audioOutputDeviceUID.isEmpty ? nil : audioOutputDeviceUID
            engine.startIcomUSBMonitoring(inputDevice: inUID, outputDevice: outUID)

        case .fx4cr:
            engine.audioPath = .fx4cr
            let fx = FX4CRDriver.shared
            if !serialPort.isEmpty { fx.selectedPort = serialPort }
            if baudRate > 0 { fx.baudRate = baudRate }
            if !fx.isConnected { fx.connect() }
            isConnected = fx.isConnected
            let inUID = audioInputDeviceUID.isEmpty ? nil : audioInputDeviceUID
            let outUID = audioOutputDeviceUID.isEmpty ? nil : audioOutputDeviceUID
            engine.startFX4CRMonitoring(inputDevice: inUID, outputDevice: outUID)

        case .xiegu6100:
            engine.audioPath = .xiegu6100
            let xiegu = Xiegu6100Driver.shared
            if !serialPort.isEmpty { xiegu.selectedPort = serialPort }
            if !xiegu.isConnected { xiegu.connect() }
            isConnected = xiegu.isConnected
            let inUID = audioInputDeviceUID.isEmpty ? nil : audioInputDeviceUID
            let outUID = audioOutputDeviceUID.isEmpty ? nil : audioOutputDeviceUID
            engine.startXiegu6100Monitoring(inputDevice: inUID, outputDevice: outUID)

        case .transceiverEmulator:
            let radio = dedicatedIcomRadio ?? IcomNetworkRadio()
            dedicatedIcomRadio = radio
            engine.audioPath = .icomLAN
            let settings = IcomNetworkSettings(
                host: "127.0.0.1",
                controlPort: 50001,
                username: "admin",
                clientName: "YAAM-NTE-Slot\(slotIndex)",
                model: .ic7300MK2
            )
            if !radio.state.isConnected {
                radio.connect(settings: settings, password: "admin")
            }
            isConnected = true
            engine.startIcomMonitoring(radio: radio)
        }
    }

    func stopMonitoring() {
        engine.stopMonitoring()
        dedicatedIcomRadio?.disconnect()
        dedicatedRigClient?.disconnect()
        isConnected = false
        isMonitoring = false
    }

    func toConfig() -> MultiRigSlotConfig {
        MultiRigSlotConfig(
            id: id,
            slotIndex: slotIndex,
            name: name,
            driverType: driverType,
            dialFrequencyHz: dialFrequencyHz,
            audioInputDeviceUID: audioInputDeviceUID,
            audioOutputDeviceUID: audioOutputDeviceUID,
            icomHost: icomHost,
            icomPort: icomPort,
            icomUsername: icomUsername,
            icomModelName: icomModel.rawValue,
            rigctldHost: rigctldHost,
            rigctldPort: rigctldPort,
            serialPort: serialPort,
            baudRate: baudRate,
            isEnabled: isEnabled
        )
    }
}

// MARK: - Multi-Rig Aggregated DX Opportunity

struct CrossBandOpportunity: Identifiable, Sendable {
    var id: UUID { row.id }
    let slotIndex: Int
    let slotName: String
    let band: String
    let row: FT8DecodedRow
}

// MARK: - Multi-Rig FT8 Central Orchestration Hub

@MainActor
final class MultiRigFT8Hub: ObservableObject {
    @Published var slots: [MultiRigSlot] = []
    @Published var activeLayout: MultiRigLayoutMode = .tripleColumn
    @Published var interlockPolicy: MultiRigInterlockPolicy = .strictLockout {
        didSet { interlockCoordinator.policy = interlockPolicy }
    }
    @Published var selectedFocusedSlotIndex: Int = 1
    @Published var masterStatusMessage: String = "Multi-Rig FT8 Cluster ready"
    @Published var isAllMonitoring: Bool = false
    @Published var showCrossBandRoster: Bool = true

    let interlockCoordinator = MultiRigInterlockCoordinator()
    private weak var appState: AppState?
    private var cancellables: Set<AnyCancellable> = []
    private static let persistenceKey = "multiRigFT8.slots.v2"
    private static let layoutKey = "multiRigFT8.layout.v2"
    private static let interlockKey = "multiRigFT8.interlock.v2"

    init() {
        loadConfiguration()
        if slots.isEmpty {
            createDefaultTripleRigSlots()
        }
        wireInterlock()
    }

    func configureBridges(with appState: AppState) {
        self.appState = appState
        for slot in slots {
            wireSlotToAppState(slot: slot, appState: appState)
        }
    }

    private func wireSlotToAppState(slot: MultiRigSlot, appState: AppState) {
        let engine = slot.engine

        // Connect logging handler to centralized SQLite logbook with Radio Tag
        engine.logQSOHandler = { [weak self, weak appState] call, grid, sent, rcvd, band, freq in
            guard let appState else { return }
            let radioName = slot.name
            if Thread.isMainThread {
                self?.logMultiRigQSO(
                    appState: appState,
                    radioName: radioName,
                    call: call,
                    grid: grid,
                    sentRST: sent,
                    rcvdRST: rcvd,
                    band: band,
                    freqMHz: freq
                )
            } else {
                Task { @MainActor in
                    self?.logMultiRigQSO(
                        appState: appState,
                        radioName: radioName,
                        call: call,
                        grid: grid,
                        sentRST: sent,
                        rcvdRST: rcvd,
                        band: band,
                        freqMHz: freq
                    )
                }
            }
        }

        // Shared logbook lookup handlers
        engine.isCountryWorkedOnBand = { [weak appState] country, band in
            guard let appState else { return true }
            let targetBand = band.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let targetCountry = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return appState.qsoRecords.contains { rec in
                let b = (rec.fields["BAND"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let c = (rec.fields["COUNTRY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return b == targetBand && c == targetCountry
            }
        }

        engine.isCallWorkedToday = { [weak appState] call, band in
            guard let appState else { return false }
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            dateFormatter.dateFormat = "yyyyMMdd"
            let todayStr = dateFormatter.string(from: Date())

            let targetBand = band.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let targetCall = call.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return appState.qsoRecords.contains { rec in
                let b = (rec.fields["BAND"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let c = (rec.fields["CALL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let d = rec.fields["QSO_DATE"] ?? ""
                return b == targetBand && c == targetCall && d == todayStr
            }
        }

        engine.isCallWorked = { [weak appState] call in
            guard let appState else { return false }
            let targetCall = call.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return appState.qsoRecords.contains { rec in
                (rec.fields["CALL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == targetCall
            }
        }

        engine.isGridWorked = { [weak appState] grid in
            guard let appState else { return false }
            let targetGrid = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(4)
            return appState.qsoRecords.contains { rec in
                (rec.fields["GRIDSQUARE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix(targetGrid)
            }
        }
    }

    private func logMultiRigQSO(
        appState: AppState,
        radioName: String,
        call: String,
        grid: String,
        sentRST: String,
        rcvdRST: String,
        band: String,
        freqMHz: Double
    ) {
        let cleanCall = call.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCall.isEmpty else { return }

        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        dateFormatter.dateFormat = "yyyyMMdd"
        let qsoDate = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "HHmmss"
        let timeOn = dateFormatter.string(from: now)

        let entity = DXCCDatabase.resolve(callsign: cleanCall)

        var fields: [String: String] = [
            "CALL": cleanCall,
            "BAND": band,
            "MODE": "FT8",
            "FREQ": String(format: "%.6f", freqMHz),
            "QSO_DATE": qsoDate,
            "TIME_ON": timeOn,
            "TIME_OFF": timeOn,
            "RST_SENT": sentRST.isEmpty ? "-10" : sentRST,
            "RST_RCVD": rcvdRST.isEmpty ? "-10" : rcvdRST,
            "COUNTRY": entity.entityName,
            "CONT": entity.continent,
            "CQZ": "\(entity.cqZone)",
            "ITUZ": "\(entity.ituZone)",
            "COMMENT": "Logged via YAAM Multi-Rig FT8 Cluster (\(radioName))",
            "APP_YAAM_SOURCE": "Multi-Rig FT8",
            "RADIO": radioName
        ]
        if !grid.isEmpty { fields["GRIDSQUARE"] = grid.uppercased() }

        fields = appState.stationTaggedFields(fields)
        guard !appState.isSelfContact(fields) else { return }
        let newRecord = QSORecordModel(index: appState.qsoRecords.count + 1, fields: fields)

        guard !appState.qsoRecords.contains(where: { $0.uniqueKey == newRecord.uniqueKey }) else {
            return
        }

        appState.qsoRecords.append(newRecord)
        appState.persistQuickLog(newRecord)
        appState.playActivitySound(.success)
        masterStatusMessage = "⭐️ QSO with \(cleanCall) on \(band) logged by \(radioName)!"
    }

    private func wireInterlock() {
        for slot in slots {
            let slotID = slot.id
            let slotName = slot.name
            let slotIndex = slot.slotIndex
            slot.engine.interlockWillTransmit = { [weak self] _ in
                guard let self else { return true }
                return self.interlockCoordinator.requestTransmit(
                    slotID: slotID,
                    slotName: slotName,
                    slotIndex: slotIndex
                )
            }
            slot.engine.interlockDidFinishTransmit = { [weak self] _ in
                self?.interlockCoordinator.releaseTransmit(slotID: slotID)
            }
        }
    }

    func createDefaultTripleRigSlots() {
        let configs: [MultiRigSlotConfig] = [
            .init(
                slotIndex: 1,
                name: "Rig 1 (20m FT8)",
                driverType: .icomLAN,
                dialFrequencyHz: 14_074_000,
                icomHost: "127.0.0.1",
                icomPort: 50001,
                icomModelName: "IC-705"
            ),
            .init(
                slotIndex: 2,
                name: "Rig 2 (40m FT8)",
                driverType: .lab599TX500,
                dialFrequencyHz: 7_074_000,
                serialPort: "/dev/cu.usbserial-TX500",
                baudRate: 9600
            ),
            .init(
                slotIndex: 3,
                name: "Rig 3 (10m FT8)",
                driverType: .transceiverEmulator,
                dialFrequencyHz: 28_074_000,
                rigctldHost: "127.0.0.1",
                rigctldPort: 4532
            )
        ]
        slots = configs.map { MultiRigSlot(config: $0) }
        saveConfiguration()
    }

    func startAllMonitoring() {
        guard let appState else { return }
        for slot in slots where slot.isEnabled {
            slot.connectAndStartMonitoring(appState: appState)
        }
        isAllMonitoring = true
        masterStatusMessage = "Multi-Rig Cluster: All \(slots.filter(\.isEnabled).count) active transceivers monitoring"
    }

    func stopAllMonitoring() {
        for slot in slots {
            slot.stopMonitoring()
        }
        isAllMonitoring = false
        masterStatusMessage = "Multi-Rig Cluster: All monitoring halted"
    }

    func disarmAllTransmitters() {
        for slot in slots {
            slot.engine.transmitArmed = false
            slot.engine.cancelTransmission(reason: "Emergency Disarm triggered from Multi-Rig Console")
        }
        interlockCoordinator.reset()
        masterStatusMessage = "🛑 Emergency: All transmitters disarmed"
    }

    func addSlot() {
        guard slots.count < 4 else { return }
        let newIndex = slots.count + 1
        let defaultBands: [UInt64] = [14_074_000, 7_074_000, 28_074_000, 21_074_000]
        let freq = defaultBands[min(newIndex - 1, defaultBands.count - 1)]

        let config = MultiRigSlotConfig(
            slotIndex: newIndex,
            name: "Rig \(newIndex)",
            driverType: .coreAudioRigctld,
            dialFrequencyHz: freq
        )
        let slot = MultiRigSlot(config: config)
        if let appState { wireSlotToAppState(slot: slot, appState: appState) }
        slots.append(slot)
        wireInterlock()
        saveConfiguration()
    }

    func removeSlot(at index: Int) {
        guard slots.indices.contains(index), slots.count > 1 else { return }
        slots[index].stopMonitoring()
        slots.remove(at: index)
        wireInterlock()
        saveConfiguration()
    }

    func aggregatedCrossBandOpportunities() -> [CrossBandOpportunity] {
        var results: [CrossBandOpportunity] = []
        for slot in slots where slot.isEnabled {
            let topDecodes = slot.engine.decodedRows.prefix(15)
            for row in topDecodes {
                results.append(CrossBandOpportunity(
                    slotIndex: slot.slotIndex,
                    slotName: slot.name,
                    band: slot.bandName,
                    row: row
                ))
            }
        }
        return results.sorted { a, b in
            if a.row.isCQ != b.row.isCQ { return a.row.isCQ && !b.row.isCQ }
            if a.row.isNewDXCC != b.row.isNewDXCC { return a.row.isNewDXCC && !b.row.isNewDXCC }
            return a.row.estimatedSNR > b.row.estimatedSNR
        }
    }

    func saveConfiguration() {
        let configs = slots.map { $0.toConfig() }
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
        UserDefaults.standard.set(activeLayout.rawValue, forKey: Self.layoutKey)
        UserDefaults.standard.set(interlockPolicy.rawValue, forKey: Self.interlockKey)
    }

    func loadConfiguration() {
        if let layoutRaw = UserDefaults.standard.string(forKey: Self.layoutKey),
           let layout = MultiRigLayoutMode(rawValue: layoutRaw) {
            activeLayout = layout
        }
        if let interlockRaw = UserDefaults.standard.string(forKey: Self.interlockKey),
           let interlock = MultiRigInterlockPolicy(rawValue: interlockRaw) {
            interlockPolicy = interlock
            interlockCoordinator.policy = interlock
        }
        if let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
           let configs = try? JSONDecoder().decode([MultiRigSlotConfig].self, from: data),
           !configs.isEmpty {
            slots = configs.map { MultiRigSlot(config: $0) }
        }
    }
}
