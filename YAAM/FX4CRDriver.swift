//
//  FX4CRDriver.swift
//  YAAM
//
//  Dedicated Hardware Driver & CAT Controller for FX-4CR QRP HF Transceiver
//  Engineered specifically for macOS over USB-C and Bluetooth.
//  Implements Kenwood TS-590S / TS-480 CAT command set (115200 baud, 8N1).
//  Includes full mitigation for Hamlib Protocol Error (-8), internal Bluetooth
//  UART routing conflict, USB-C negotiation quirk, and audio gain calibration.
//  Provides direct Morse keying (Kenwood KY / DTR-RTS) and digital mode (FT8/FT4/RTTY/PSK31) integration.
//

import Combine
import CoreAudio
import Foundation
import FT8808Engine
import SwiftUI

// MARK: - FX-4CR Connection Type Enum

public enum FX4CRConnectionType: String, CaseIterable, Identifiable, Codable, Sendable {
    case usb = "USB-C (Wired)"
    case bluetooth = "Bluetooth (Wireless)"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .usb: return "cable.connector"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        }
    }
}

public typealias FX4CRTransport = FX4CRConnectionType

// MARK: - FX-4CR Operating Mode Enum

public enum FX4CRMode: Int, CaseIterable, Identifiable, Sendable {
    case lsb = 1
    case usb = 2
    case cw = 3
    case fm = 4
    case am = 5
    case fsk = 6
    case cwR = 7
    case fskR = 9

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .lsb: return "LSB"
        case .usb: return "USB"
        case .cw: return "CW"
        case .fm: return "FM"
        case .am: return "AM"
        case .fsk: return "FSK/DIG"
        case .cwR: return "CW-R"
        case .fskR: return "FSK-R"
        }
    }

    public static func from(kenwoodCode: Int) -> FX4CRMode {
        return FX4CRMode(rawValue: kenwoodCode) ?? .usb
    }
}

// MARK: - FX-4CR Safe Mode Strategy

public enum FX4CRSafeModeStrategy: String, CaseIterable, Identifiable, Sendable {
    case safeUSB = "Safe USB/CW (Recommended)"
    case nonePassThrough = "Mode: None (Retain on Radio)"

    public var id: String { rawValue }
}

// MARK: - FX-4CR Transceiver Driver

@MainActor
public final class FX4CRDriver: ObservableObject {
    public static let shared = FX4CRDriver()

    // MARK: - Published Configuration & State
    @Published public var isConnected: Bool = false
    @Published public var isConnecting: Bool = false
    @Published public var connectionType: FX4CRConnectionType {
        didSet {
            UserDefaults.standard.set(connectionType.rawValue, forKey: "fx4crConnectionType")
            refreshPorts()
        }
    }
    @Published public var selectedPort: String = "" {
        didSet { UserDefaults.standard.set(selectedPort, forKey: "fx4crSerialPort") }
    }
    @Published public var baudRate: Int = 115200 {
        didSet { UserDefaults.standard.set(baudRate, forKey: "fx4crBaudRate") }
    }
    @Published public var stopBits: Int = 1
    @Published public var safeModeStrategy: FX4CRSafeModeStrategy {
        didSet { UserDefaults.standard.set(safeModeStrategy.rawValue, forKey: "fx4crSafeModeStrategy") }
    }
    @Published public var autoConnect: Bool {
        didSet { UserDefaults.standard.set(autoConnect, forKey: "fx4crAutoConnect") }
    }

    // Real-Time Radio Telemetry
    @Published public var frequencyHz: UInt64 = 14074000
    @Published public var mode: String = "USB"
    @Published public var sMeterValue: Double = 0.0 // 0 to 15 S-units (S9 = 9, >9 is +dB)
    @Published public var powerWatts: Int = 10       // 1W to 10W (QRP) / up to 20W
    @Published public var alcLevel: Double = 0.0     // 0 to 100 scale (reported reference ~35)
    @Published public var isTransmitting: Bool = false
    @Published public var lastMessage: String = "Ready to connect to FX-4CR"
    @Published public var availablePorts: [String] = []

    // Hardware Audio Codec Match (C-Media CM108AH USB / Bluetooth Audio)
    @Published public var detectedAudioDeviceName: String? = nil
    @Published public var detectedAudioInputUID: String? = nil
    @Published public var detectedAudioOutputUID: String? = nil
    @Published public var isAudioDeviceDetected: Bool = false

    // Computed Telemetry Helpers
    public var frequencyMHz: Double {
        Double(frequencyHz) / 1_000_000.0
    }

    public var formattedFrequency: String {
        String(format: "%.6f MHz", frequencyMHz)
    }

    public var transport: FX4CRConnectionType {
        get { connectionType }
        set { connectionType = newValue }
    }

    public var rfPowerWatts: Double {
        get { Double(powerWatts) }
        set { powerWatts = Int(newValue) }
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

    /// Hardware guidance warning based on active transport type and known quirks
    public var hardwareNotice: String {
        switch connectionType {
        case .usb:
            return "Wired USB: Radio Menu Bluetooth MUST be 0 (Off) to avoid internal serial conflict. Direct USB-C to USB-C cable will fail (USB-C negotiation quirk); use USB-C to USB-A cable + Mac adapter."
        case .bluetooth:
            return "Wireless Bluetooth: Radio Menu Bluetooth MUST be 1 (On). Ensure FX-4CR is paired in macOS System Settings → Bluetooth."
        }
    }

    /// Recommended audio gain calibration summary from test blueprint
    public var audioCalibrationGuide: String {
        "Audio Calibration: Set FX-4CR volume knob to 18–24 (optimal green 30–50 dB in WSJT-X/YAAM). Set macOS TX audio to ~0.45–0.65 normalized (e.g. 0.622 in Audio MIDI Setup) calibrated against measured RF output (~7–9W with ALC around 20–35)."
    }

    // MARK: - Internal Transport & Polling
    private let serialPort = SerialPortService()
    private var receiveBuffer = ""
    private var pollingTimer: DispatchSourceTimer?
    private var pttWatchdog: DispatchWorkItem?
    private let serialQueue = DispatchQueue(label: "com.yaam.fx4cr.driver", qos: .userInitiated)

    private init() {
        let savedType = UserDefaults.standard.string(forKey: "fx4crConnectionType") ?? FX4CRConnectionType.usb.rawValue
        self.connectionType = FX4CRConnectionType(rawValue: savedType) ?? .usb

        self.selectedPort = UserDefaults.standard.string(forKey: "fx4crSerialPort") ?? ""
        let storedBaud = UserDefaults.standard.integer(forKey: "fx4crBaudRate")
        self.baudRate = storedBaud > 0 ? storedBaud : 115200

        let savedStrategy = UserDefaults.standard.string(forKey: "fx4crSafeModeStrategy") ?? FX4CRSafeModeStrategy.safeUSB.rawValue
        self.safeModeStrategy = FX4CRSafeModeStrategy(rawValue: savedStrategy) ?? .safeUSB

        self.autoConnect = UserDefaults.standard.bool(forKey: "fx4crAutoConnect")

        refreshPorts()
        scanAudioDevices()

        if autoConnect && !selectedPort.isEmpty {
            connect()
        }
    }

    deinit {
        pollingTimer?.cancel()
        pttWatchdog?.cancel()
        serialPort.closePort()
    }

    // MARK: - Port Discovery & Audio Detection

    public func refreshPorts() {
        let allPorts = SerialPortService.availablePorts(includeBluetooth: true)

        switch connectionType {
        case .usb:
            // Prioritize USB CDC-ACM call-out nodes (/dev/cu.usbserial-*, /dev/cu.usbmodem*)
            self.availablePorts = allPorts.sorted { p1, p2 in
                let p1IsUSB = SerialPortService.isUSBPort(p1)
                let p2IsUSB = SerialPortService.isUSBPort(p2)
                if p1IsUSB && !p2IsUSB { return true }
                if !p1IsUSB && p2IsUSB { return false }
                return p1 < p2
            }
            if selectedPort.isEmpty || !availablePorts.contains(selectedPort) || SerialPortService.isBluetoothPort(selectedPort) {
                if let usbPort = availablePorts.first(where: { SerialPortService.isUSBPort($0) }) {
                    selectedPort = usbPort
                } else if let first = availablePorts.first {
                    selectedPort = first
                }
            }

        case .bluetooth:
            // Prioritize Bluetooth serial callout nodes (/dev/cu.*Bluetooth*, /dev/cu.FX-4CR*)
            self.availablePorts = allPorts.sorted { p1, p2 in
                let p1IsBT = SerialPortService.isBluetoothPort(p1) || p1.lowercased().contains("fx")
                let p2IsBT = SerialPortService.isBluetoothPort(p2) || p2.lowercased().contains("fx")
                if p1IsBT && !p2IsBT { return true }
                if !p1IsBT && p2IsBT { return false }
                return p1 < p2
            }
            if selectedPort.isEmpty || !availablePorts.contains(selectedPort) || SerialPortService.isUSBPort(selectedPort) {
                if let btPort = availablePorts.first(where: { SerialPortService.isBluetoothPort($0) || $0.lowercased().contains("fx") }) {
                    selectedPort = btPort
                } else if let first = availablePorts.first {
                    selectedPort = first
                }
            }
        }
    }

    public func scanAudioDevices() {
        // Scans for C-Media CM108AH USB Audio Codec or Bluetooth audio matching FX-4CR
        let inDevs = AudioDevices.inputDevices()
        let outDevs = AudioDevices.outputDevices()
        if let rigAudio = inDevs.first(where: {
            let name = $0.name.lowercased()
            return name.contains("fx-4cr") || name.contains("fx4cr") ||
                   name.contains("usb audio") || name.contains("cm108") ||
                   name.contains("c-media") ||
                   (self.connectionType == .bluetooth && name.contains("bluetooth"))
        }) {
            self.detectedAudioDeviceName = rigAudio.name
            self.isAudioDeviceDetected = true
            self.detectedAudioInputUID = rigAudio.uid
            self.detectedAudioOutputUID = outDevs.first(where: { $0.name == rigAudio.name })?.uid
        } else {
            self.detectedAudioDeviceName = nil
            self.detectedAudioInputUID = nil
            self.detectedAudioOutputUID = nil
            self.isAudioDeviceDetected = false
        }
    }

    // MARK: - Connect & Disconnect

    public func connect(port: String? = nil, type: FX4CRConnectionType? = nil) {
        if let t = type { self.connectionType = t }
        if let p = port { self.selectedPort = p }

        guard !selectedPort.isEmpty else {
            lastMessage = "No serial port selected for FX-4CR (\(connectionType.rawValue))"
            return
        }

        isConnecting = true
        let transportLabel = connectionType == .usb ? "USB-C" : "Bluetooth"
        lastMessage = "Connecting to FX-4CR on \(selectedPort) via \(transportLabel)..."

        UserDefaults.standard.set(selectedPort, forKey: "fx4crSerialPort")
        UserDefaults.standard.set(baudRate, forKey: "fx4crBaudRate")
        UserDefaults.standard.set(connectionType.rawValue, forKey: "fx4crConnectionType")

        let ok = serialPort.openPort(
            path: selectedPort,
            baudRate: baudRate,
            stopBits: stopBits
        ) { [weak self] data in
            Task { @MainActor [weak self] in
                self?.handleIncomingSerialData(data)
            }
        }

        if ok {
            self.isConnected = true
            self.isConnecting = false
            let portName = selectedPort.components(separatedBy: "/").last ?? selectedPort
            self.lastMessage = "Connected to FX-4CR (\(portName) via \(transportLabel) @ \(baudRate) 8N\(stopBits))"

            // Start polling radio telemetry (VFO frequency, S-meter, power, mode)
            startPolling()

            // Initial status query
            queryRadioStatus()
            scanAudioDevices()
        } else {
            self.isConnected = false
            self.isConnecting = false
            self.lastMessage = "Failed to open \(selectedPort). Check \(transportLabel) connection & permissions."
        }
    }

    public func disconnect() {
        if isTransmitting {
            setPTT(false)
        }
        stopPolling()
        serialPort.closePort()
        isConnected = false
        isConnecting = false
        isTransmitting = false
        lastMessage = "FX-4CR Disconnected"
    }

    public func toggleConnection() {
        if isConnected || isConnecting {
            disconnect()
        } else {
            connect()
        }
    }

    // MARK: - Kenwood TS-590S Protocol Commands

    /// Polls current frequency, mode, S-meter, power, and meter reading
    public func queryRadioStatus() {
        guard isConnected else { return }
        sendRaw("FA;MD;SM;PC;RM;")
    }

    /// Tunes VFO-A to target frequency in Hz
    public func setFrequencyHz(_ hz: UInt64) {
        guard isConnected, hz > 0 else { return }
        self.frequencyHz = hz
        let cmd = String(format: "FA%011llu;", hz)
        sendRaw(cmd)
    }

    /// Sets VFO-B frequency in Hz (useful for Split / Fake It)
    public func setVfoBFrequencyHz(_ hz: UInt64) {
        guard isConnected, hz > 0 else { return }
        let cmd = String(format: "FB%011llu;", hz)
        sendRaw(cmd)
    }

    /// Sets operating mode.
    /// In accordance with Section 5.2 of the technical blueprint:
    /// Sending `PKTUSB` or `Data/Pkt` to the FX-4CR can trigger Hamlib Protocol Error (-8).
    /// Under `.safeUSB`, maps to clean Kenwood `MD2;` for USB, `MD3;` for CW, etc.
    /// Under `.nonePassThrough`, suppresses sending mode commands to let the operator set and retain the mode directly on the radio.
    public func setMode(_ targetMode: String) {
        guard isConnected else { return }

        if safeModeStrategy == .nonePassThrough {
            // Do not issue mode command over CAT; leave mode untouched on the transceiver
            return
        }

        let clean = targetMode.uppercased()
        if clean.contains("CW-R") || clean.contains("CWR") {
            self.mode = "CW-R"
            sendRaw("MD7;")
        } else if clean.contains("CW") {
            self.mode = "CW"
            sendRaw("MD3;")
        } else if clean.contains("USB") || clean.contains("DIG") || clean.contains("DATA") || clean.contains("PKT") {
            self.mode = "USB"
            sendRaw("MD2;") // Clean Kenwood USB mode
        } else if clean.contains("LSB") {
            self.mode = "LSB"
            sendRaw("MD1;")
        } else if clean.contains("FM") {
            self.mode = "FM"
            sendRaw("MD4;")
        } else if clean.contains("AM") {
            self.mode = "AM"
            sendRaw("MD5;")
        }
    }

    /// Sets RF power level in Watts (1 to 10W standard digital limit, up to 20W max)
    public func setPowerWatts(_ watts: Int) {
        guard isConnected else { return }
        let clamped = max(1, min(20, watts))
        self.powerWatts = clamped
        let cmd = String(format: "PC%03d;", clamped)
        sendRaw(cmd)
    }

    /// Asserts or releases CAT PTT with hardware safety watchdog timer
    public func setPTT(_ transmit: Bool, maximumDuration: TimeInterval = 14.0) {
        guard isConnected else {
            if !transmit { isTransmitting = false }
            return
        }

        pttWatchdog?.cancel()
        pttWatchdog = nil

        if transmit {
            self.isTransmitting = true
            let transportLabel = connectionType == .usb ? "USB" : "Bluetooth"
            self.lastMessage = "FX-4CR Transmitting (PTT Active via \(transportLabel))"
            sendRaw("TX;")

            // Safety watchdog timer: automatically release PTT if software stalls or times out
            let watchdog = DispatchWorkItem { [weak self] in
                guard let self = self, self.isTransmitting else { return }
                self.setPTT(false)
                self.lastMessage = "PTT released by FX-4CR safety watchdog"
            }
            self.pttWatchdog = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + max(1.0, maximumDuration), execute: watchdog)
        } else {
            self.isTransmitting = false
            let transportLabel = connectionType == .usb ? "USB" : "Bluetooth"
            self.lastMessage = "FX-4CR Receive (PTT Released via \(transportLabel))"
            sendRaw("RX;")
        }
    }

    // MARK: - Morse Code (CW) Operations

    /// Transmits text directly via Kenwood CAT Morse `KY <text>;` to FX-4CR's internal keyer.
    /// Operates identically over both USB-C and Bluetooth!
    public func sendMorse(_ text: String, wpm: Int = 24) {
        guard isConnected else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }

        // Set keyer speed first: KS<wpm>;
        let clampedWPM = max(5, min(60, wpm))
        sendRaw(String(format: "KS%03d;", clampedWPM))

        // Kenwood KY command buffers up to 24 characters at a time.
        // Chunk long strings into safe 24-character pieces with micro-delays.
        let chunks = stride(from: 0, to: clean.count, by: 24).map { idx -> String in
            let start = clean.index(clean.startIndex, offsetBy: idx)
            let end = clean.index(start, offsetBy: min(24, clean.count - idx))
            return String(clean[start..<end])
        }

        for (i, chunk) in chunks.enumerated() {
            let cmd = "KY \(chunk);"
            if i == 0 {
                sendRaw(cmd)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.5) { [weak self] in
                    guard self?.isConnected == true else { return }
                    self?.sendRaw(cmd)
                }
            }
        }

        let transportLabel = connectionType == .usb ? "USB-C" : "Bluetooth"
        self.lastMessage = "Transmitting CW via \(transportLabel): \(clean)"
    }

    /// Aborts active CW transmission
    public func stopMorse() {
        guard isConnected else { return }
        sendRaw("KY ;RX;")
        self.lastMessage = "FX-4CR CW Transmission Aborted"
    }

    /// Pulse hardware DTR/RTS lines for Morse keying (if keying via USB-C serial pin)
    public func setKeyPin(active: Bool, pin: SerialControlPin) {
        guard isConnected else { return }
        if pin == .dtr {
            serialPort.setDTR(active: active)
        } else if pin == .rts {
            serialPort.setRTS(active: active)
        }
    }

    // MARK: - Low-Level Serial Communication

    @discardableResult
    public func sendRaw(_ command: String) -> Bool {
        guard isConnected else { return false }
        guard let data = command.data(using: .ascii) else { return false }
        return serialPort.writeData(data)
    }

    private func handleIncomingSerialData(_ data: Data) {
        guard let chunk = String(data: data, encoding: .ascii) else { return }
        receiveBuffer.append(chunk)

        // Kenwood protocol frames are terminated by semicolon ';'
        while let semicolonIndex = receiveBuffer.firstIndex(of: ";") {
            let command = String(receiveBuffer[..<semicolonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            receiveBuffer.removeSubrange(...semicolonIndex)
            if !command.isEmpty {
                parseKenwoodResponse(command)
            }
        }
    }

    public func parseKenwoodResponse(_ response: String) {
        // VFO-A Frequency: FA00014074000
        if response.hasPrefix("FA") {
            let numStr = response.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if let freq = UInt64(numStr), freq > 0 {
                self.frequencyHz = freq
            }
        // VFO-B Frequency: FB00014074000
        } else if response.hasPrefix("FB") {
            // Can be observed if VFO-B tracking is needed
        // Operating Mode: MD1 ... MD9
        } else if response.hasPrefix("MD") {
            let modeCodeStr = response.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if let code = Int(modeCodeStr) {
                let fxMode = FX4CRMode.from(kenwoodCode: code)
                self.mode = fxMode.name
            }
        // S-Meter: SM0005 (0 to 15)
        } else if response.hasPrefix("SM") {
            let sStr = response.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if let rawVal = Double(sStr) {
                self.sMeterValue = min(15.0, rawVal)
            }
        // Power Control: PC010 (Watts)
        } else if response.hasPrefix("PC") {
            let pwrStr = response.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if let watts = Int(pwrStr), watts > 0 {
                self.powerWatts = min(20, watts)
            }
        // Meter query: RM (ALC meter / SWR / Power)
        } else if response.hasPrefix("RM") {
            let meterStr = response.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if let val = Double(meterStr) {
                self.alcLevel = val
            }
        // Transceiver Status Query: IF
        } else if response.hasPrefix("IF") {
            if response.count >= 13 {
                let freqPart = String(response.dropFirst(2).prefix(11)).trimmingCharacters(in: .whitespaces)
                if let freq = UInt64(freqPart), freq > 0 {
                    self.frequencyHz = freq
                }
            }
        }
    }

    // MARK: - Background Polling Loop

    private func startPolling() {
        stopPolling()
        let timer = DispatchSource.makeTimerSource(queue: serialQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isConnected, !self.isTransmitting else { return }
                // Poll frequency, S-meter, and meter readings
                self.sendRaw("FA;SM;RM;")
            }
        }
        timer.resume()
        self.pollingTimer = timer
    }

    private func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }
}
