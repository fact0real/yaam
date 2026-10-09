//
//  Xiegu6100Driver.swift
//  YAAM
//
//  Dedicated Hardware Driver & CAT Controller for Xiegu X6100 Transceiver
//  Engineered specifically for macOS direct USB-C connection (DEV Port)
//  Implements standard Icom CI-V protocol (emulating IC-705 command set):
//  - Default CI-V Address: 0xA4, standard baud: 19200 bps (8N1)
//  - Dual-channel topology: Serial CAT / Pin Keying & Bidirectional USB Audio CODEC
//  - High-precision VFO tuning, operating mode (USB-D, CW, CW-R, etc.)
//  - Transmit PTT assertion with fail-safe watchdog timer
//  - Direct Morse (CW) keying via CI-V 0x17 text buffer and serial DTR/RTS hardware pins
//  - Real-time RF telemetry: S-Meter (S0..S9+60dB), Power (1-10W), SWR, and ALC
//

import Combine
import CoreAudio
import Foundation
import SwiftUI
import FT8808Engine

// MARK: - Xiegu X6100 Operating Modes

public enum Xiegu6100Mode: UInt8, CaseIterable, Identifiable, Sendable {
    case lsb  = 0x00
    case usb  = 0x01
    case am   = 0x02
    case cw   = 0x03
    case rtty = 0x04
    case fm   = 0x05
    case cwR  = 0x07

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
        }
    }
}

// MARK: - Xiegu X6100 Hardware Driver

@MainActor
public final class Xiegu6100Driver: ObservableObject {
    public static let shared = Xiegu6100Driver()

    // MARK: - Published Configuration & State
    @Published public var isConnected: Bool = false
    @Published public var isConnecting: Bool = false
    @Published public var selectedPort: String = "" {
        didSet { UserDefaults.standard.set(selectedPort, forKey: "xiegu6100SerialPort") }
    }
    @Published public var baudRate: Int = 19200 {
        didSet { UserDefaults.standard.set(baudRate, forKey: "xiegu6100BaudRate") }
    }
    @Published public var civAddressHex: String = "A4" {
        didSet { UserDefaults.standard.set(civAddressHex, forKey: "xiegu6100CivAddress") }
    }
    @Published public var autoConnect: Bool = false {
        didSet { UserDefaults.standard.set(autoConnect, forKey: "xiegu6100AutoConnect") }
    }
    @Published public var enableHardwareRTSPTT: Bool = false {
        didSet { UserDefaults.standard.set(enableHardwareRTSPTT, forKey: "xiegu6100RTSPTT") }
    }
    @Published public var enableHardwareDTRCW: Bool = false {
        didSet { UserDefaults.standard.set(enableHardwareDTRCW, forKey: "xiegu6100DTRCW") }
    }

    // Real-Time Radio Telemetry
    @Published public var frequencyHz: UInt64 = 14074000
    @Published public var mode: String = "USB-D"
    @Published public var sMeterValue: Double = 0.0 // 0 to 15 S-units (S9 = 9, >9 is +dB)
    @Published public var powerWatts: Int = 5        // 1W to 10W (QRP scale)
    @Published public var swr: Double = 1.0
    private(set) var swrUpdatedAt: Date?
    @Published public var alcLevel: Double = 0.0
    @Published public var isTransmitting: Bool = false
    @Published public var lastMessage: String = "Ready to connect to Xiegu X6100"
    @Published public var availablePorts: [String] = []

    // Hardware Audio Codec Match (USB-C UAC Audio: "USB Audio CODEC", "X6100 Audio")
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
        UInt8(civAddressHex, radix: 16) ?? 0xA4
    }

    // MARK: - Internal Transport & Polling
    nonisolated private let serialPort = SerialPortService()
    private var rxBuffer = Data()
    private let rxBufferLock = NSLock()
    private var pollingTimer: DispatchSourceTimer?
    private var pttWatchdog: DispatchWorkItem?
    private let serialQueue = DispatchQueue(label: "com.yaam.xiegu6100.driver", qos: .userInitiated)
    private var pollCycle: UInt64 = 0

    private init() {
        self.selectedPort = UserDefaults.standard.string(forKey: "xiegu6100SerialPort") ?? ""
        let storedBaud = UserDefaults.standard.integer(forKey: "xiegu6100BaudRate")
        self.baudRate = storedBaud > 0 ? storedBaud : 19200
        self.civAddressHex = UserDefaults.standard.string(forKey: "xiegu6100CivAddress") ?? "A4"
        self.autoConnect = UserDefaults.standard.bool(forKey: "xiegu6100AutoConnect")
        self.enableHardwareRTSPTT = UserDefaults.standard.bool(forKey: "xiegu6100RTSPTT")
        self.enableHardwareDTRCW = UserDefaults.standard.bool(forKey: "xiegu6100DTRCW")

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
        // Prioritize Xiegu X6100 dual virtual COM ports:
        // When connected via USB-C DEV port, X6100 mounts with CH340, CP2105, or CDC-ACM drivers.
        // Port B (higher port index or 'B') is typically the CI-V CAT interface.
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
        // Prefer Port B / secondary port for Xiegu dual-serial interfaces
        if p.contains("wchusbserial") && (p.hasSuffix("b") || p.contains("1")) { return 100 }
        if p.contains("usbserial") && (p.hasSuffix("b") || p.contains("1")) { return 95 }
        if p.contains("usbmodem") && (p.hasSuffix("3") || p.hasSuffix("2")) { return 90 }
        if p.contains("wchusbserial") { return 85 }
        if p.contains("usbserial") { return 80 }
        if p.contains("usbmodem") { return 75 }
        return 10
    }

    public func scanAudioDevices() {
        let inputDevices = AudioDevices.inputDevices()
        let outputDevices = AudioDevices.outputDevices()

        // Match X6100 built-in USB Audio CODEC
        let rigInput = inputDevices.first { dev in
            let n = dev.name.lowercased()
            return n.contains("x6100") || n.contains("usb audio") || n.contains("c-media") || n.contains("codec")
        }
        let rigOutput = outputDevices.first { dev in
            let n = dev.name.lowercased()
            return n.contains("x6100") || n.contains("usb audio") || n.contains("c-media") || n.contains("codec")
        }

        if let rigInput {
            self.detectedAudioDeviceName = rigInput.name
            self.detectedAudioInputUID = rigInput.uid
        } else {
            self.detectedAudioDeviceName = nil
            self.detectedAudioInputUID = nil
        }

        if let rigOutput {
            self.detectedAudioOutputUID = rigOutput.uid
        } else {
            self.detectedAudioOutputUID = nil
        }

        self.isAudioDeviceDetected = (detectedAudioDeviceName != nil)
    }

    // MARK: - Connect & Disconnect

    public func connect(port: String? = nil) {
        if let p = port { self.selectedPort = p }
        guard !selectedPort.isEmpty else {
            lastMessage = "No USB-C serial port selected for Xiegu X6100"
            return
        }

        isConnecting = true
        lastMessage = "Connecting to Xiegu X6100 on \(selectedPort)..."

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
            self.lastMessage = "Connected to Xiegu X6100 (\(portName) @ \(baudRate) 8N1, CI-V: 0x\(civAddressHex))"

            queryRadioStatus()
            startPolling()
        } else {
            self.isConnected = false
            self.isConnecting = false
            self.lastMessage = "Failed to open \(selectedPort). Verify USB-C DEV port and permissions."
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
        lastMessage = "Xiegu X6100 Disconnected"
    }

    public func toggleConnection() {
        if isConnected || isConnecting {
            disconnect()
        } else {
            connect()
        }
    }

    // MARK: - Telemetry & Polling

    private func startPolling() {
        stopPolling()
        let timer = DispatchSource.makeTimerSource(queue: serialQueue)
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(300))
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

        if isTransmitting {
            // Read RF Output Power (15 11) & SWR (15 12) while transmitting
            if pollCycle % 2 == 0 {
                sendCIV(command: [0x15, 0x11]) // Po
            } else {
                sendCIV(command: [0x15, 0x12]) // SWR
            }
        } else {
            // Read S-meter level (15 02)
            sendCIV(command: [0x15, 0x02])
        }

        // Periodically read Frequency (03) and Mode (04) every ~1.2s
        if pollCycle % 4 == 0 {
            sendCIV(command: [0x03]) // Frequency
            sendCIV(command: [0x04]) // Mode
        }
    }

    public func queryRadioStatus() {
        guard isConnected else { return }
        sendCIV(command: [0x03]) // Read Frequency
        sendCIV(command: [0x04]) // Read Mode
        sendCIV(command: [0x15, 0x02]) // Read S-meter
    }

    // MARK: - Frequency & Operating Mode Controls

    /// Sets operating frequency in Hz using CI-V command 0x05 (5-byte BCD, LSB-first)
    public func setFrequencyHz(_ hz: UInt64) {
        guard isConnected, hz > 0 else { return }
        self.frequencyHz = hz
        let bcd = Self.frequencyToBCD(hz)
        var cmd: [UInt8] = [0x05]
        cmd.append(contentsOf: bcd)
        sendCIV(command: cmd)
    }

    /// Sets operating mode on Xiegu X6100
    public func setMode(_ targetMode: String) {
        guard isConnected else { return }
        let clean = targetMode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if clean.contains("DIG") || clean.contains("USB-D") || clean.contains("DATA") || clean.contains("FT8") || clean.contains("FT4") {
            // USB mode (01) with Data Filter 2 (02)
            sendCIV(command: [0x06, 0x01, 0x02])
            // Enable Data Mode in radio (1A 06 01 01)
            sendCIV(command: [0x1A, 0x06, 0x01, 0x01])
            self.mode = "USB-D"
        } else if clean.contains("CW-R") {
            sendCIV(command: [0x06, 0x07, 0x01])
            sendCIV(command: [0x1A, 0x06, 0x00, 0x01])
            self.mode = "CW-R"
        } else if clean.contains("CW") {
            sendCIV(command: [0x06, 0x03, 0x01])
            sendCIV(command: [0x1A, 0x06, 0x00, 0x01])
            self.mode = "CW"
        } else if clean.contains("USB") {
            sendCIV(command: [0x06, 0x01, 0x01])
            sendCIV(command: [0x1A, 0x06, 0x00, 0x01])
            self.mode = "USB"
        } else if clean.contains("LSB") {
            sendCIV(command: [0x06, 0x00, 0x01])
            sendCIV(command: [0x1A, 0x06, 0x00, 0x01])
            self.mode = "LSB"
        } else if clean.contains("AM") {
            sendCIV(command: [0x06, 0x02, 0x01])
            self.mode = "AM"
        } else if clean.contains("FM") {
            sendCIV(command: [0x06, 0x05, 0x01])
            self.mode = "FM"
        }
    }

    /// Prepares transceiver specifically for digital FT8/FT4/RTTY operation
    public func prepareForDigital(frequencyHz: UInt64) {
        setFrequencyHz(frequencyHz)
        setMode("USB-D")
    }

    /// Sets RF power level in Watts (1 to 10W for X6100 QRP)
    public func setPowerWatts(_ watts: Int) {
        guard isConnected else { return }
        let clamped = max(1, min(10, watts))
        self.powerWatts = clamped

        // Scale 1-10W to CI-V 0-255 scale
        let rawVal = UInt8(Double(clamped) / 10.0 * 255.0)
        let bcdHigh = rawVal / 100
        let bcdMid = (rawVal % 100) / 10
        let bcdLow = rawVal % 10
        let byte1 = (bcdHigh << 4) | bcdMid
        let byte2 = bcdLow << 4
        sendCIV(command: [0x14, 0x0A, byte1, byte2])
    }

    // MARK: - Transmit PTT with Safety Watchdog

    /// Asserts or releases CAT PTT with hardware safety watchdog timer
    public func setPTT(_ active: Bool, maximumDuration: TimeInterval = 15.0) {
        guard isConnected else {
            if !active { isTransmitting = false }
            return
        }

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
            self.lastMessage = "Xiegu X6100 Transmitting (PTT Active)"

            // Safety watchdog timer: automatically release PTT if app stalls or disconnects
            let watchdog = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self, self.isTransmitting else { return }
                    self.setPTT(false)
                    self.lastMessage = "⚠️ PTT watchdog tripped after \(Int(maximumDuration))s"
                }
            }
            self.pttWatchdog = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + max(1.0, maximumDuration), execute: watchdog)
        } else {
            // CI-V CAT PTT OFF: 1C 00 00
            sendCIV(command: [0x1C, 0x00, 0x00])

            // Hardware RTS PTT release
            if enableHardwareRTSPTT {
                serialPort.setRTS(active: false)
            }

            self.lastMessage = "Xiegu X6100 Receive (PTT Released)"
            self.swr = 1.0
            self.alcLevel = 0.0
        }
    }

    // MARK: - Morse Code (CW) Operations

    /// Transmits text directly via CI-V command 0x17 to Xiegu X6100 internal keyer
    public func sendMorse(_ text: String) {
        guard isConnected else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }

        // CI-V Command 17: Send CW message: [0x17, char1, char2, ...]
        var cmd: [UInt8] = [0x17]
        for byte in clean.utf8 {
            cmd.append(byte)
        }
        sendCIV(command: cmd)
        self.lastMessage = "Transmitting CW: \(clean)"
    }

    /// Aborts active CW transmission (CI-V Command 17 FF)
    public func stopMorse() {
        guard isConnected else { return }
        sendCIV(command: [0x17, 0xFF])
        if enableHardwareDTRCW {
            serialPort.setDTR(active: false)
        }
        self.lastMessage = "CW Transmission Aborted"
    }

    /// Sets the keyer speed in WPM (CI-V Command 14 0C)
    public func setKeyerSpeed(_ wpm: Int) {
        guard isConnected else { return }
        let clamped = max(5, min(50, wpm))
        let bcdHigh = UInt8(clamped / 10)
        let bcdLow = UInt8(clamped % 10)
        let bcdByte = (bcdHigh << 4) | bcdLow
        sendCIV(command: [0x14, 0x0C, bcdByte])
    }

    /// Pulse hardware DTR/RTS lines for Morse keying (zero-latency pin keying over USB-C)
    public func setKeyPin(active: Bool, pin: SerialControlPin) {
        guard isConnected else { return }
        if pin == .dtr {
            serialPort.setDTR(active: active)
        } else if pin == .rts {
            serialPort.setRTS(active: active)
        }
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

            parseCIVPacket(packet)
        }
        rxBufferLock.unlock()
    }

    private func parseCIVPacket(_ packet: Data) {
        // Minimum valid CI-V packet: FE FE To From Cmd FD (6 bytes)
        guard packet.count >= 6 else { return }
        guard packet[0] == 0xFE, packet[1] == 0xFE, packet.last == 0xFD else { return }

        let cmd = packet[4]
        let subData = packet.count > 6 ? packet.subdata(in: 5..<(packet.count - 1)) : Data()

        switch cmd {
        case 0x00, 0x03:
            // Frequency Report: 5 bytes BCD LSB first
            if subData.count >= 5 {
                let freq = Self.bcdToFrequency(subData.prefix(5))
                if freq > 0 {
                    self.frequencyHz = freq
                }
            }
        case 0x01, 0x04:
            // Operating Mode Report: Mode (1 byte) + Data Filter (1 byte)
            if let modeByte = subData.first {
                let opMode = Xiegu6100Mode(rawValue: modeByte)
                let filter = subData.count > 1 ? subData[1] : 0x01
                if (modeByte == 0x01 && filter == 0x02) || modeByte == 0x04 {
                    self.mode = "USB-D"
                } else {
                    self.mode = opMode?.name ?? "USB"
                }
            }
        case 0x15:
            // Meter Telemetry
            if subData.count >= 2 {
                let meterSub = subData[0]
                let rawVal = Double(subData[1])
                if meterSub == 0x02 {
                    // S-Meter: 0 to 255 -> 0 to 15 S-units
                    self.sMeterValue = min(15.0, (rawVal / 255.0) * 15.0)
                } else if meterSub == 0x11 {
                    // Po: RF power
                    self.powerWatts = max(1, min(10, Int((rawVal / 255.0) * 10.0)))
                } else if meterSub == 0x12 {
                    // SWR
                    self.swr = max(1.0, 1.0 + (rawVal / 255.0) * 4.0)
                    self.swrUpdatedAt = Date()
                } else if meterSub == 0x13 {
                    // ALC
                    self.alcLevel = (rawVal / 255.0) * 100.0
                }
            }
        default:
            break
        }
    }

    // MARK: - BCD Helpers

    /// Converts frequency in Hz to 5-byte CI-V BCD (LSB first: 1Hz/10Hz, 100Hz/1kHz, 10kHz/100kHz, 1MHz/10MHz, 100MHz/1GHz)
    public static func frequencyToBCD(_ hz: UInt64) -> [UInt8] {
        var val = hz
        var bcd = [UInt8](repeating: 0, count: 5)
        for i in 0..<5 {
            let low = UInt8(val % 10)
            val /= 10
            let high = UInt8(val % 10)
            val /= 10
            bcd[i] = (high << 4) | low
        }
        return bcd
    }

    /// Converts 5-byte CI-V BCD (LSB first) to frequency in Hz
    public static func bcdToFrequency(_ data: Data) -> UInt64 {
        guard data.count >= 5 else { return 0 }
        var hz: UInt64 = 0
        var multiplier: UInt64 = 1
        for byte in data.prefix(5) {
            let low = UInt64(byte & 0x0F)
            let high = UInt64((byte >> 4) & 0x0F)
            hz += (low + high * 10) * multiplier
            multiplier *= 100
        }
        return hz
    }
}
