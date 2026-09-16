//
//  Lab599TX500Driver.swift
//  YAAM
//
//  Dedicated Hardware Driver & CAT Controller for Lab599 Discovery TX-500
//  Engineered specifically for macOS over USB-C (AD-514/AD-502 CAT & AD-508/AD-509 Audio)
//  Implements Kenwood TS-2000 emulation (Radio Menu 34: TS2000, Menu 35: 9600, Menu 09: 30)
//  Includes full mitigation for Firmware Bug #1 (DIG -> USB mode jump prevention)
//  and provides direct Morse keying (Kenwood KY / DTR-RTS) and digital mode audio integration.
//

import Combine
import Foundation
import SwiftUI
import CoreAudio
import FT8808Engine

// MARK: - TX-500 Operating Mode Enum

public enum TX500Mode: Int, CaseIterable, Identifiable, Sendable {
    case lsb = 1
    case usb = 2
    case cw = 3
    case fm = 4
    case am = 5
    case dig = 6
    case cwR = 7
    case digR = 8

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .lsb: return "LSB"
        case .usb: return "USB"
        case .cw: return "CW"
        case .fm: return "FM"
        case .am: return "AM"
        case .dig: return "DIG"
        case .cwR: return "CW-R"
        case .digR: return "DIG-R"
        }
    }

    public static func from(kenwoodCode: Int) -> TX500Mode {
        return TX500Mode(rawValue: kenwoodCode) ?? .dig
    }
}

// MARK: - Lab599 TX-500 Driver

@MainActor
public final class Lab599TX500Driver: ObservableObject {
    public static let shared = Lab599TX500Driver()

    // MARK: - Published Configuration & State
    @Published public var isConnected: Bool = false
    @Published public var isConnecting: Bool = false
    @Published public var selectedPort: String = ""
    @Published public var baudRate: Int = 9600
    @Published public var stopBits: Int = 2 // 8N2 recommended by TX-500 documentation
    @Published public var preserveDIGMode: Bool = true // MANDATORY for Firmware Bug #1 fix
    @Published public var autoConnect: Bool = false

    // Real-Time Radio Telemetry
    @Published public var frequencyHz: UInt64 = 14074000
    @Published public var mode: String = "DIG"
    @Published public var sMeterValue: Double = 0.0 // 0 to 15 S-units (S9 = 9, >9 is +dB)
    @Published public var powerWatts: Int = 10       // 1W to 10W (QRP)
    @Published public var isTransmitting: Bool = false
    @Published public var lastMessage: String = "Ready to connect to TX-500"
    @Published public var availablePorts: [String] = []

    // Hardware Audio Codec Match (AD-508 / AD-509)
    @Published public var detectedAudioDeviceName: String? = nil
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

    // MARK: - Internal Transport & Polling
    private let serialPort = SerialPortService()
    private var receiveBuffer = ""
    private var pollingTimer: DispatchSourceTimer?
    private var pttWatchdog: DispatchWorkItem?
    private let serialQueue = DispatchQueue(label: "com.yaam.tx500.driver", qos: .userInitiated)

    private init() {
        self.selectedPort = UserDefaults.standard.string(forKey: "lab599SerialPort") ?? ""
        let storedBaud = UserDefaults.standard.integer(forKey: "lab599BaudRate")
        self.baudRate = storedBaud > 0 ? storedBaud : 9600
        let storedStopBits = UserDefaults.standard.integer(forKey: "lab599StopBits")
        self.stopBits = storedStopBits > 0 ? storedStopBits : 2
        self.preserveDIGMode = UserDefaults.standard.object(forKey: "lab599PreserveDIGMode") as? Bool ?? true
        self.autoConnect = UserDefaults.standard.bool(forKey: "lab599AutoConnect")

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
        // Filter and prioritize FTDI callout nodes (/dev/cu.usbserial-*)
        self.availablePorts = allPorts.sorted { p1, p2 in
            if p1.contains("usbserial") && !p2.contains("usbserial") { return true }
            return p1 < p2
        }

        if selectedPort.isEmpty || !availablePorts.contains(selectedPort) {
            if let ftdiPort = availablePorts.first(where: { $0.contains("usbserial") }) {
                selectedPort = ftdiPort
            } else if let first = availablePorts.first {
                selectedPort = first
            }
        }
    }

    public func scanAudioDevices() {
        // Scans for USB Audio codec connected from TX-500 AD-508 or AD-509
        let audioDevices = AudioDevices.inputDevices()
        if let rigAudio = audioDevices.first(where: { $0.name.lowercased().contains("usb audio") || $0.name.lowercased().contains("c-media") }) {
            self.detectedAudioDeviceName = rigAudio.name
            self.isAudioDeviceDetected = true
        } else {
            self.detectedAudioDeviceName = nil
            self.isAudioDeviceDetected = false
        }
    }

    // MARK: - Connect & Disconnect

    public func connect(port: String? = nil) {
        if let p = port { self.selectedPort = p }
        guard !selectedPort.isEmpty else {
            lastMessage = "No serial port selected for TX-500"
            return
        }

        isConnecting = true
        lastMessage = "Connecting to TX-500 on \(selectedPort)..."

        UserDefaults.standard.set(selectedPort, forKey: "lab599SerialPort")
        UserDefaults.standard.set(baudRate, forKey: "lab599BaudRate")
        UserDefaults.standard.set(stopBits, forKey: "lab599StopBits")
        UserDefaults.standard.set(preserveDIGMode, forKey: "lab599PreserveDIGMode")

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
            self.lastMessage = "Connected to TX-500 (\(portName) @ \(baudRate) 8N\(stopBits))"

            // Start polling radio telemetry (VFO frequency, S-meter, power, mode)
            startPolling()

            // Initial query barrage
            queryRadioStatus()
        } else {
            self.isConnected = false
            self.isConnecting = false
            self.lastMessage = "Failed to open \(selectedPort). Check FTDI driver & permissions."
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
        lastMessage = "TX-500 Disconnected"
    }

    public func toggleConnection() {
        if isConnected || isConnecting {
            disconnect()
        } else {
            connect()
        }
    }

    // MARK: - Kenwood TS-2000 Protocol Commands

    /// Polls current frequency, mode, S-meter, and power
    public func queryRadioStatus() {
        guard isConnected else { return }
        sendRaw("FA;MD;SM;PC;")
    }

    /// Tunes VFO-A to target frequency in Hz
    public func setFrequencyHz(_ hz: UInt64) {
        guard isConnected, hz > 0 else { return }
        self.frequencyHz = hz
        let cmd = String(format: "FA%011llu;", hz)
        sendRaw(cmd)
    }

    /// Sets operating mode.
    /// CRITICAL: If `preserveDIGMode` is true and target is a digital mode or voice,
    /// this suppresses sending mode commands to prevent Firmware Bug #1!
    public func setMode(_ targetMode: String) {
        guard isConnected else { return }

        let clean = targetMode.uppercased()
        if preserveDIGMode && (clean.contains("DIG") || clean.contains("USB-D") || clean.contains("DATA") || clean.contains("PKT")) {
            // Keep radio in DIG mode; omit CAT mode string to protect REM/DATA audio routing
            self.mode = "DIG"
            return
        }

        if clean.contains("CW") {
            self.mode = "CW"
            sendRaw("MD3;") // Kenwood CW mode
        } else if clean.contains("USB") {
            self.mode = "USB"
            sendRaw("MD2;")
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

    /// Sets RF power level in Watts (1 to 10W for TX-500)
    public func setPowerWatts(_ watts: Int) {
        guard isConnected else { return }
        let clamped = max(1, min(10, watts))
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
            self.lastMessage = "TX-500 Transmitting (PTT Active)"
            sendRaw("TX;")

            // Safety watchdog timer: automatically release PTT if app stalls or disconnects
            let watchdog = DispatchWorkItem { [weak self] in
                guard let self = self, self.isTransmitting else { return }
                self.setPTT(false)
                self.lastMessage = "PTT released by TX-500 safety timer"
            }
            self.pttWatchdog = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + max(1.0, maximumDuration), execute: watchdog)
        } else {
            self.isTransmitting = false
            self.lastMessage = "TX-500 Receive (PTT Released)"
            sendRaw("RX;")
        }
    }

    // MARK: - Morse Code (CW) Operations

    /// Transmits text directly via Kenwood CAT Morse `KY <text>;` to TX-500's internal keyer
    public func sendMorse(_ text: String, wpm: Int = 24) {
        guard isConnected else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }

        // Set keyer speed first: KS<wpm>;
        let clampedWPM = max(5, min(60, wpm))
        sendRaw(String(format: "KS%03d;", clampedWPM))

        // Kenwood KY command: buffers up to 24 characters at a time
        // We chunk long strings into safe 24-character pieces
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
                // Micro-delay between successive 24-char chunks
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.5) { [weak self] in
                    guard self?.isConnected == true else { return }
                    self?.sendRaw(cmd)
                }
            }
        }

        self.lastMessage = "Transmitting CW: \(clean)"
    }

    /// Aborts active CW transmission
    public func stopMorse() {
        guard isConnected else { return }
        sendRaw("KY ;RX;")
        self.lastMessage = "CW Transmission Aborted"
    }

    /// Pulse hardware DTR/RTS lines for Morse keying (if keying via serial pin)
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

    private func parseKenwoodResponse(_ response: String) {
        // VFO-A Frequency: FA00014074000
        if response.hasPrefix("FA") {
            let numStr = response.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if let freq = UInt64(numStr), freq > 0 {
                self.frequencyHz = freq
            }
        // Operating Mode: MD1 ... MD9
        } else if response.hasPrefix("MD") {
            let modeCodeStr = response.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if let code = Int(modeCodeStr) {
                let txMode = TX500Mode.from(kenwoodCode: code)
                // If preserveDIGMode is active and radio indicates DIG or USB, keep as DIG
                if preserveDIGMode && (txMode == .dig || txMode == .digR) {
                    self.mode = "DIG"
                } else {
                    self.mode = txMode.name
                }
            }
        // S-Meter: SM0005 (0 to 15)
        } else if response.hasPrefix("SM") {
            let sStr = response.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if let rawVal = Double(sStr) {
                // Kenwood SM is 0000 to 0015 (or 0030 for +60dB scale)
                self.sMeterValue = min(15.0, rawVal)
            }
        // Power Control: PC010 (Watts)
        } else if response.hasPrefix("PC") {
            let pwrStr = response.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if let watts = Int(pwrStr), watts > 0 {
                self.powerWatts = min(10, watts)
            }
        // Transceiver Status Query: IF
        } else if response.hasPrefix("IF") {
            // IF format: IF[freq 11][vfo 4][rit 5][rit_on 1][xit_on 1][mem 3][tx 1][mode 1]...
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
                // Poll frequency and S-meter
                self.sendRaw("FA;SM;")
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
