//
//  IcomUSBRadioDriver.swift
//  YAAM
//
//  Dedicated Hardware Driver & CAT Controller for Icom Transceivers over USB
//  Engineered for macOS direct USB cable connection:
//  - IC-705 (Default CI-V: 0xA4, 115200 baud)
//  - IC-7300 (Default CI-V: 0x94, 19200/115200 baud)
//  - IC-7300MK2 (Default CI-V: 0x94, 115200 baud)
//  - IC-7610 (Default CI-V: 0x98, 115200 baud)
//
//  Provides:
//  1. High-speed bidirectional CI-V packet parser (transceive & polled)
//  2. FT8 digital mode optimization (USB-D mode lock + DATA MOD -> USB input command)
//  3. Transmit PTT with fail-safe watchdog timer
//  4. Morse Code (CW) keying over CAT (CI-V Command 0x17 & 0x17 0xFF abort)
//  5. Hardware RTS/DTR pin keying and PTT options
//  6. Real-time RF telemetry: S-Meter (S0..S9+60dB), Power (Watts), SWR, and ALC
//  7. Automatic USB Audio CODEC detection for zero-config FT8 audio streaming
//

import Combine
import Foundation
import SwiftUI
import CoreAudio
import FT8808Engine

// MARK: - Supported Icom Transceiver Models

public enum IcomUSBModel: String, CaseIterable, Identifiable, Sendable {
    case auto = "Auto-Detect"
    case ic705 = "IC-705"
    case ic7300 = "IC-7300"
    case ic7300MK2 = "IC-7300MK2"
    case ic7610 = "IC-7610"

    public var id: String { rawValue }

    public var defaultCivAddress: UInt8 {
        switch self {
        case .auto: return 0x00
        case .ic705: return 0xA4
        case .ic7300, .ic7300MK2: return 0x94
        case .ic7610: return 0x98
        }
    }

    public var defaultBaudRate: Int {
        switch self {
        case .auto, .ic705, .ic7300MK2, .ic7610: return 115200
        case .ic7300: return 19200
        }
    }

    public var iconName: String {
        switch self {
        case .auto: return "sparkles"
        case .ic705: return "backpack.fill"
        case .ic7300, .ic7300MK2: return "radio.fill"
        case .ic7610: return "antenna.radiowaves.left.and.right"
        }
    }

    public static func from(modelId: UInt8) -> IcomUSBModel? {
        switch modelId {
        case 0xA4: return .ic705
        case 0x94: return .ic7300
        case 0x98: return .ic7610
        default: return nil
        }
    }
}

// MARK: - Operating Mode Definitions

public enum IcomOperatingMode: UInt8, CaseIterable, Identifiable, Sendable {
    case lsb = 0x00
    case usb = 0x01
    case am  = 0x02
    case cw  = 0x03
    case rtty = 0x04
    case fm  = 0x05
    case cwR = 0x07
    case rttyR = 0x08

    public var id: UInt8 { rawValue }

    public var name: String {
        switch self {
        case .lsb: return "LSB"
        case .usb: return "USB"
        case .am: return "AM"
        case .cw: return "CW"
        case .rtty: return "RTTY"
        case .fm: return "FM"
        case .cwR: return "CW-R"
        case .rttyR: return "RTTY-R"
        }
    }
}

// MARK: - Icom USB Radio Driver

@MainActor
public final class IcomUSBRadioDriver: ObservableObject {
    public static let shared = IcomUSBRadioDriver()

    // MARK: - Published Configuration & State
    @Published public var isConnected: Bool = false
    @Published public var isConnecting: Bool = false
    @Published public var selectedPort: String = ""
    @Published public var baudRate: Int = 115200
    @Published public var model: IcomUSBModel = .ic7300
    @Published public var customCivAddressHex: String = "94"
    @Published public var autoConnect: Bool = false
    @Published public var enableHardwareRTSPTT: Bool = false
    @Published public var enableHardwareDTRCW: Bool = false

    // Real-Time Radio Telemetry
    @Published public var frequencyHz: UInt64 = 14074000
    @Published public var mode: String = "USB-D"
    @Published public var isDataMode: Bool = true
    @Published public var sMeterValue: Double = 0.0      // 0 to 15 S-units (S9 = 9, >9 is +dB)
    @Published public var rfPowerWatts: Double = 0.0     // 0 to 100 Watts
    @Published public var swr: Double = 1.0              // 1.0 to 3.0+
    private(set) var swrUpdatedAt: Date?
    @Published public var alcLevel: Double = 0.0         // 0 to 100%
    @Published public var isTransmitting: Bool = false
    @Published public var lastMessage: String = "Ready to connect to Icom radio via USB"
    @Published public var availablePorts: [String] = []

    // Built-in USB Audio CODEC Matching
    @Published public var detectedAudioInputName: String? = nil
    @Published public var detectedAudioInputUID: String? = nil
    @Published public var detectedAudioOutputName: String? = nil
    @Published public var detectedAudioOutputUID: String? = nil
    @Published public var isAudioCodecDetected: Bool = false

    // Computed Telemetry Helpers
    public var frequencyMHz: Double {
        Double(frequencyHz) / 1_000_000.0
    }

    public var formattedFrequency: String {
        String(format: "%.6f MHz", frequencyMHz)
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

    public var activeCivAddress: UInt8 {
        if let custom = UInt8(customCivAddressHex.replacingOccurrences(of: "0x", with: ""), radix: 16), custom > 0 {
            return custom
        }
        return model.defaultCivAddress
    }

    public var resolvedCIVAddress: UInt8 {
        return activeCivAddress
    }

    // MARK: - Internal Transport & Polling
    nonisolated private let serialPort = SerialPortService()
    private var rxBuffer = Data()
    private let rxBufferLock = NSLock()
    private var pollingTimer: DispatchSourceTimer?
    private var pttWatchdog: DispatchWorkItem?
    private var pollCycle: Int = 0
    private let serialQueue = DispatchQueue(label: "com.yaam.icom.usb.driver", qos: .userInitiated)

    private init() {
        self.selectedPort = UserDefaults.standard.string(forKey: "icomUSBSerialPort") ?? ""
        let storedBaud = UserDefaults.standard.integer(forKey: "icomUSBBaudRate")
        self.baudRate = storedBaud > 0 ? storedBaud : 115200
        if let storedModelRaw = UserDefaults.standard.string(forKey: "icomUSBModel"),
           let storedModel = IcomUSBModel(rawValue: storedModelRaw) {
            self.model = storedModel
        }
        self.customCivAddressHex = UserDefaults.standard.string(forKey: "icomUSBCivAddress") ?? String(format: "%02X", model.defaultCivAddress)
        self.autoConnect = UserDefaults.standard.bool(forKey: "icomUSBAutoConnect")
        self.enableHardwareRTSPTT = UserDefaults.standard.bool(forKey: "icomUSBHardwareRTSPTT")
        self.enableHardwareDTRCW = UserDefaults.standard.bool(forKey: "icomUSBHardwareDTRCW")

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
        let allPorts = SerialPortService.availablePorts()
        // Prioritize Silicon Labs CP210x (used by Icom IC-7300/7610/705) and FTDI / usbmodem
        self.availablePorts = allPorts.sorted { p1, p2 in
            let score1 = portPriorityScore(p1)
            let score2 = portPriorityScore(p2)
            if score1 != score2 { return score1 > score2 }
            return p1 < p2
        }

        if selectedPort.isEmpty || !availablePorts.contains(selectedPort) {
            if let best = availablePorts.first {
                selectedPort = best
            }
        }
    }

    private func portPriorityScore(_ path: String) -> Int {
        let p = path.lowercased()
        if p.contains("slab_usbtouart") { return 100 } // Silicon Labs standard IC-7300
        if p.contains("usbmodem") { return 90 }        // IC-705 standard CDC
        if p.contains("usbserial") { return 80 }       // FTDI or generic CP210x
        return 10
    }

    public func scanAudioDevices() {
        let inputDevices = AudioDevices.inputDevices()
        let outputDevices = AudioDevices.outputDevices()

        // Match Icom Built-In USB Audio Codec (usually named "USB Audio CODEC", "IC-705", or "Burr-Brown")
        let rigInput = inputDevices.first { dev in
            let n = dev.name.lowercased()
            return n.contains("usb audio") || n.contains("ic-705") || n.contains("burr-brown") || n.contains("ti usb")
        }
        let rigOutput = outputDevices.first { dev in
            let n = dev.name.lowercased()
            return n.contains("usb audio") || n.contains("ic-705") || n.contains("burr-brown") || n.contains("ti usb")
        }

        if let rigInput {
            self.detectedAudioInputName = rigInput.name
            self.detectedAudioInputUID = rigInput.uid
        } else {
            self.detectedAudioInputName = nil
            self.detectedAudioInputUID = nil
        }

        if let rigOutput {
            self.detectedAudioOutputName = rigOutput.name
            self.detectedAudioOutputUID = rigOutput.uid
        } else {
            self.detectedAudioOutputName = nil
            self.detectedAudioOutputUID = nil
        }

        self.isAudioCodecDetected = (detectedAudioInputName != nil && detectedAudioOutputName != nil)
    }

    // MARK: - Connect & Disconnect

    public func connect(port: String? = nil) {
        if let p = port { self.selectedPort = p }
        guard !selectedPort.isEmpty else {
            lastMessage = "No USB serial port selected for Icom radio"
            return
        }

        isConnecting = true
        lastMessage = "Connecting to Icom on \(selectedPort)..."

        UserDefaults.standard.set(selectedPort, forKey: "icomUSBSerialPort")
        UserDefaults.standard.set(baudRate, forKey: "icomUSBBaudRate")
        UserDefaults.standard.set(model.rawValue, forKey: "icomUSBModel")
        UserDefaults.standard.set(customCivAddressHex, forKey: "icomUSBCivAddress")
        UserDefaults.standard.set(enableHardwareRTSPTT, forKey: "icomUSBHardwareRTSPTT")
        UserDefaults.standard.set(enableHardwareDTRCW, forKey: "icomUSBHardwareDTRCW")

        rxBufferLock.lock()
        rxBuffer.removeAll(keepingCapacity: true)
        rxBufferLock.unlock()

        let ok = serialPort.openPort(
            path: selectedPort,
            baudRate: baudRate,
            stopBits: 1
        ) { [weak self] data in
            Task { @MainActor [weak self] in
                self?.handleIncomingSerialData(data)
            }
        }

        if ok {
            self.isConnected = true
            self.isConnecting = false
            let portName = selectedPort.components(separatedBy: "/").last ?? selectedPort
            self.lastMessage = "Connected to \(model.rawValue) (\(portName) @ \(baudRate) 8N1)"

            // Auto-detect or query initial transceiver state
            if model == .auto {
                sendAutoDetectQuery()
            } else {
                queryRadioStatus()
            }

            startPolling()
        } else {
            self.isConnected = false
            self.isConnecting = false
            self.lastMessage = "Failed to open \(selectedPort). Check USB cable and permissions."
        }
    }

    public func disconnect() {
        stopPolling()
        if isTransmitting {
            setPTT(false)
        }
        serialPort.closePort()
        isConnected = false
        isConnecting = false
        lastMessage = "Disconnected from Icom transceiver"
    }

    // MARK: - Polling & Periodic Telemetry

    private func startPolling() {
        stopPolling()
        let timer = DispatchSource.makeTimerSource(queue: serialQueue)
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.pollNextTelemetry()
            }
        }
        timer.resume()
        self.pollingTimer = timer
    }

    private func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    private func pollNextTelemetry() {
        guard isConnected else { return }
        pollCycle &+= 1

        // High priority: S-meter every 250ms (or RF power/SWR while transmitting)
        if isTransmitting {
            // RF Power Po (cmd 15 11), SWR (cmd 15 12), ALC (cmd 15 13)
            switch pollCycle % 3 {
            case 0: sendCIV(command: [0x15, 0x11]) // Po
            case 1: sendCIV(command: [0x15, 0x12]) // SWR
            default: sendCIV(command: [0x15, 0x13]) // ALC
            }
        } else {
            // S-meter query
            sendCIV(command: [0x15, 0x02])
        }

        // Low priority: Frequency and mode check every 1 second (4 cycles)
        if pollCycle % 4 == 0 {
            sendCIV(command: [0x03]) // Read Operating Frequency
            sendCIV(command: [0x04]) // Read Operating Mode
            sendCIV(command: [0x1A, 0x06]) // Read Data Mode
        }
    }

    public func queryRadioStatus() {
        sendCIV(command: [0x03]) // Read Frequency
        sendCIV(command: [0x04]) // Read Mode
        sendCIV(command: [0x1A, 0x06]) // Read Data Mode
        sendCIV(command: [0x15, 0x02]) // Read S-meter
    }

    private func sendAutoDetectQuery() {
        // Broadcast query: command 19 00 (Read transceiver ID)
        sendCIVTo(address: 0x00, command: [0x19, 0x00])
    }

    // MARK: - Transceiver Tuning & Mode Controls

    public func setFrequencyHz(_ hz: UInt64) {
        self.frequencyHz = hz
        let bcd = Self.frequencyToBCD(hz)
        var cmd: [UInt8] = [0x05]
        cmd.append(contentsOf: bcd)
        sendCIV(command: cmd)
    }

    public func setMode(_ modeName: String) {
        let clean = modeName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean == "USB-D" || clean == "DATA" || clean == "FT8" {
            // Select USB mode (01) then enable Data Mode 1 (1A 06 01 01)
            sendCIV(command: [0x06, 0x01, 0x01])
            sendCIV(command: [0x1A, 0x06, 0x01, 0x01])
            // Ensure DATA MOD is routed to USB (1A 05 00 85 03)
            sendCIV(command: [0x1A, 0x05, 0x00, 0x85, 0x03])
            self.mode = "USB-D"
            self.isDataMode = true
        } else if clean == "CW" {
            // CW mode, filter 1, disable Data Mode
            sendCIV(command: [0x06, 0x03, 0x01])
            sendCIV(command: [0x1A, 0x06, 0x00, 0x01])
            self.mode = "CW"
            self.isDataMode = false
        } else if clean == "CW-R" {
            sendCIV(command: [0x06, 0x07, 0x01])
            sendCIV(command: [0x1A, 0x06, 0x00, 0x01])
            self.mode = "CW-R"
            self.isDataMode = false
        } else if clean == "USB" {
            sendCIV(command: [0x06, 0x01, 0x01])
            sendCIV(command: [0x1A, 0x06, 0x00, 0x01])
            self.mode = "USB"
            self.isDataMode = false
        } else if clean == "LSB" {
            sendCIV(command: [0x06, 0x00, 0x01])
            sendCIV(command: [0x1A, 0x06, 0x00, 0x01])
            self.mode = "LSB"
            self.isDataMode = false
        } else if clean == "AM" {
            sendCIV(command: [0x06, 0x02, 0x01])
            self.mode = "AM"
            self.isDataMode = false
        } else if clean == "FM" {
            sendCIV(command: [0x06, 0x05, 0x01])
            self.mode = "FM"
            self.isDataMode = false
        }
    }

    /// Prepares transceiver specifically for digital FT8/FT4 operation:
    /// Sets frequency, selects USB-D mode, and enforces DATA MOD -> USB input routing.
    public func prepareForDigital(frequencyHz: UInt64) {
        setFrequencyHz(frequencyHz)
        setMode("USB-D")
    }

    // MARK: - Transmit PTT with Watchdog

    public func setPTT(_ active: Bool, maximumDuration: TimeInterval = 16.0) {
        pttWatchdog?.cancel()
        pttWatchdog = nil

        isTransmitting = active

        if active {
            // Hardware RTS PTT (if enabled)
            if enableHardwareRTSPTT {
                serialPort.setRTS(active: true)
            }

            // CI-V CAT PTT ON: 1C 00 01
            sendCIV(command: [0x1C, 0x00, 0x01])

            // Fail-safe watchdog: drop PTT if stalled
            let watchdog = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self, self.isTransmitting else { return }
                    self.setPTT(false)
                    self.lastMessage = "⚠️ PTT watchdog tripped after \(Int(maximumDuration))s"
                }
            }
            pttWatchdog = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + maximumDuration, execute: watchdog)
        } else {
            // CI-V CAT PTT OFF: 1C 00 00
            sendCIV(command: [0x1C, 0x00, 0x00])

            // Hardware RTS PTT release
            if enableHardwareRTSPTT {
                serialPort.setRTS(active: false)
            }

            self.rfPowerWatts = 0.0
            self.swr = 1.0
            self.alcLevel = 0.0
        }
    }

    // MARK: - Morse Code (CW) Transmission

    /// Transmits Morse text directly via Icom CI-V command 0x17
    public func sendMorse(_ text: String) {
        let clean = text.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        // Icom CI-V Command 17: Send CW message
        // Format: [17, char1, char2, ...]
        var cmd: [UInt8] = [0x17]
        for byte in clean.utf8 {
            cmd.append(byte)
        }
        sendCIV(command: cmd)
    }

    /// Aborts active CW transmission on the Icom transceiver (CI-V Command 17 FF)
    public func stopMorse() {
        sendCIV(command: [0x17, 0xFF])
        if enableHardwareDTRCW {
            serialPort.setDTR(active: false)
        }
    }

    /// Sets the keyer speed on the transceiver (CI-V Command 14 0C)
    public func setKeyerSpeed(_ wpm: Int) {
        let clamped = max(6, min(45, wpm))
        let bcdHigh = UInt8(clamped / 10)
        let bcdLow = UInt8(clamped % 10)
        let bcdByte = (bcdHigh << 4) | bcdLow
        sendCIV(command: [0x14, 0x0C, bcdByte])
    }

    // MARK: - Low-Level CI-V Framing & I/O

    public func sendCIV(command: [UInt8]) {
        sendCIVTo(address: activeCivAddress, command: command)
    }

    public func sendCIVTo(address: UInt8, command: [UInt8]) {
        guard isConnected else { return }
        var frame = Data([0xFE, 0xFE, address, 0xE0])
        frame.append(contentsOf: command)
        frame.append(0xFD)
        _ = serialPort.writeData(frame)
    }

    private func handleIncomingSerialData(_ data: Data) {
        rxBufferLock.lock()
        rxBuffer.append(data)

        // Parse framing: look for 0xFE, 0xFE ... 0xFD
        while let startIdx = rxBuffer.range(of: Data([0xFE, 0xFE]))?.lowerBound {
            if startIdx > 0 {
                rxBuffer.removeSubrange(0..<startIdx)
            }
            guard let endIdx = rxBuffer.firstIndex(of: 0xFD) else {
                break
            }
            let packet = rxBuffer.subdata(in: 0..<(endIdx + 1))
            rxBuffer.removeSubrange(0..<(endIdx + 1))
            rxBufferLock.unlock()

            parseCIVPacket(packet)

            rxBufferLock.lock()
        }
        rxBufferLock.unlock()
    }

    private func parseCIVPacket(_ packet: Data) {
        // Minimum valid CI-V packet: FE FE TO FROM CMD FD (6 bytes)
        guard packet.count >= 6,
              packet[0] == 0xFE, packet[1] == 0xFE,
              packet[packet.count - 1] == 0xFD else { return }

        let toAddr = packet[2]
        let fromAddr = packet[3]

        // Only process packets addressed to controller (0xE0) or broadcast
        guard toAddr == 0xE0 || toAddr == 0x00 else { return }

        // If Auto-Detect is active or model address differs, learn address
        if fromAddr != 0xFE && fromAddr != 0xE0 {
            if model == .auto || activeCivAddress == 0x00 {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.customCivAddressHex = String(format: "%02X", fromAddr)
                    if let detected = IcomUSBModel.from(modelId: fromAddr) {
                        self.model = detected
                        self.lastMessage = "Auto-detected \(detected.rawValue) (Address 0x\(String(format: "%02X", fromAddr)))"
                    }
                }
            }
        }

        let cmd = packet[4]
        let payload = packet.count > 6 ? Array(packet[5..<(packet.count - 1)]) : []

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.processCIVCommand(cmd: cmd, payload: payload, fromAddr: fromAddr)
        }
    }

    private func processCIVCommand(cmd: UInt8, payload: [UInt8], fromAddr: UInt8) {
        switch cmd {
        case 0x00, 0x03: // Frequency response or transceive broadcast
            if payload.count >= 5 {
                let hz = Self.frequencyFromBCD(Array(payload.prefix(5)))
                if hz > 0 {
                    self.frequencyHz = hz
                }
            }

        case 0x04: // Operating Mode response
            if let modeByte = payload.first {
                let baseMode = Self.modeName(modeByte)
                self.mode = self.isDataMode && baseMode == "USB" ? "USB-D" : baseMode
            }

        case 0x1A: // Extended Subcommand
            if payload.count >= 2, payload[0] == 0x06 {
                // Data Mode response (1A 06 <dataMode> <filter>)
                let isData = payload[1] == 0x01
                self.isDataMode = isData
                if isData && self.mode == "USB" {
                    self.mode = "USB-D"
                } else if !isData && self.mode == "USB-D" {
                    self.mode = "USB"
                }
            }

        case 0x15: // Meter readings
            guard payload.count >= 2 else { return }
            let subCmd = payload[0]
            let meterBytes = Array(payload.dropFirst())
            let rawVal = Self.decodeMeterBCD(meterBytes)

            switch subCmd {
            case 0x02: // S-meter
                if rawVal <= 120 {
                    self.sMeterValue = (Double(rawVal) / 120.0) * 9.0
                } else {
                    self.sMeterValue = 9.0 + (Double(rawVal - 120) / 121.0) * 60.0
                }
            case 0x11: // RF Power Po
                let watts = min(100.0, max(0.0, (Double(rawVal) / 143.0) * 100.0))
                self.rfPowerWatts = round(watts * 10) / 10.0
            case 0x12: // SWR
                let swrCalc: Double
                if rawVal <= 0 {
                    swrCalc = 1.0
                } else if rawVal <= 48 {
                    swrCalc = 1.0 + (Double(rawVal) / 48.0) * 0.5
                } else if rawVal <= 80 {
                    swrCalc = 1.5 + (Double(rawVal - 48) / 32.0) * 0.5
                } else if rawVal <= 120 {
                    swrCalc = 2.0 + (Double(rawVal - 80) / 40.0) * 1.0
                } else {
                    swrCalc = 3.0 + Double(rawVal - 120) * 0.05
                }
                self.swr = round(swrCalc * 10) / 10.0
                self.swrUpdatedAt = Date()
            case 0x13: // ALC
                let alc = min(100.0, max(0.0, (Double(rawVal) / 120.0) * 100.0))
                self.alcLevel = round(alc)
            default:
                break
            }

        case 0x1C: // Transmit PTT status
            if let pttByte = payload.first {
                self.isTransmitting = (pttByte == 0x01)
            }

        case 0x19: // Model ID response (cmd 19 00)
            if payload.count >= 2, payload[0] == 0x00 {
                let modelId = payload[1]
                if let detected = IcomUSBModel.from(modelId: modelId) {
                    self.model = detected
                    self.customCivAddressHex = String(format: "%02X", fromAddr)
                    self.lastMessage = "Auto-detected \(detected.rawValue) (Address 0x\(String(format: "%02X", fromAddr)))"
                }
            }

        case 0xFB: // ACK
            break

        case 0xFA: // NAK
            break

        default:
            break
        }
    }

    // MARK: - BCD Helpers

    public static func frequencyToBCD(_ hz: UInt64) -> [UInt8] {
        var str = String(format: "%010llu", hz)
        if str.count > 10 { str = String(str.suffix(10)) }
        var bcd = [UInt8](repeating: 0, count: 5)
        let chars = Array(str)
        for i in 0..<5 {
            let highIdx = 8 - (i * 2)
            let lowIdx  = 9 - (i * 2)
            let high = UInt8(String(chars[highIdx])) ?? 0
            let low  = UInt8(String(chars[lowIdx])) ?? 0
            bcd[i] = (high << 4) | low
        }
        return bcd
    }

    public static func frequencyFromBCD(_ bytes: [UInt8]) -> UInt64 {
        guard bytes.count >= 5 else { return 0 }
        var result: UInt64 = 0
        var multiplier: UInt64 = 1
        for b in bytes.prefix(5) {
            let low = UInt64(b & 0x0F)
            let high = UInt64(b >> 4)
            result += low * multiplier
            multiplier *= 10
            result += high * multiplier
            multiplier *= 10
        }
        return result
    }

    public static func decodeMeterBCD(_ bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty else { return 0 }
        var result = 0
        for b in bytes {
            let high = Int(b >> 4)
            let low = Int(b & 0x0F)
            if high < 10 && low < 10 {
                result = result * 100 + high * 10 + low
            }
        }
        return result
    }

    public static func modeName(_ code: UInt8) -> String {
        switch code {
        case 0x00: return "LSB"
        case 0x01: return "USB"
        case 0x02: return "AM"
        case 0x03: return "CW"
        case 0x04: return "RTTY"
        case 0x05: return "FM"
        case 0x07: return "CW-R"
        case 0x08: return "RTTY-R"
        default: return "USB"
        }
    }
}
