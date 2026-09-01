//
//  WinKeyerDriver.swift
//  YAAM
//
//  K1EL WinKeyer 2 / WinKeyer 3 Hardware Protocol Driver
//  Binary serial protocol implementation for hardware-level precision CW keying,
//  paddle emulation, sidetone frequency control, and live character echo feedback.
//

import Combine
import Foundation
import SwiftUI

public enum WinKeyerMode: Int, CaseIterable, Identifiable, Sendable {
    case iambicA = 0
    case iambicB = 1
    case ultimatic = 2
    case bug = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .iambicA: return "Iambic A"
        case .iambicB: return "Iambic B (Standard)"
        case .ultimatic: return "Ultimatic"
        case .bug: return "Bug Emulation"
        }
    }
}

@MainActor
public final class WinKeyerDriver: ObservableObject {
    public static let shared = WinKeyerDriver()

    // MARK: - Published State
    @Published public var isConnected: Bool = false
    @Published public var selectedPort: String = ""
    @Published public var baudRate: Int = 1200
    @Published public var wkVersion: String = "Unknown"
    @Published public var wpm: Int = 24
    @Published public var mode: WinKeyerMode = .iambicB
    @Published public var sidetoneHz: Int = 600
    @Published public var weight: Int = 50
    @Published public var paddleSwap: Bool = false
    @Published public var autoSpace: Bool = false
    @Published public var isTransmitting: Bool = false
    @Published public var sentBuffer: String = ""
    @Published public var lastEchoedChar: String = ""
    @Published public var statusMessage: String = "Disconnected"
    @Published public var availableSerialPorts: [String] = []

    private let serial = SerialPortService.shared
    private var echoTimer: Timer?

    public init() {
        self.selectedPort = UserDefaults.standard.string(forKey: "winkeyerPort") ?? ""
        self.baudRate = UserDefaults.standard.integer(forKey: "winkeyerBaud") == 9600 ? 9600 : 1200
        self.wpm = max(5, UserDefaults.standard.integer(forKey: "winkeyerWPM"))
        if self.wpm == 0 { self.wpm = 24 }
        refreshPorts()
    }

    public func refreshPorts() {
        self.availableSerialPorts = SerialPortService.availablePorts()
        if selectedPort.isEmpty, let first = availableSerialPorts.first {
            selectedPort = first
        }
    }

    // MARK: - Connect & Initialize WinKeyer

    public func connect(port: String? = nil, baud: Int? = nil) {
        if let p = port { self.selectedPort = p }
        if let b = baud { self.baudRate = b }

        UserDefaults.standard.set(selectedPort, forKey: "winkeyerPort")
        UserDefaults.standard.set(baudRate, forKey: "winkeyerBaud")

        guard !selectedPort.isEmpty else {
            statusMessage = "No serial port selected"
            return
        }

        statusMessage = "Opening \(selectedPort)..."

        let ok = serial.openPort(path: selectedPort, baudRate: baudRate) { [weak self] data in
            Task { @MainActor [weak self] in
                self?.handleIncomingData(data)
            }
        }

        if ok {
            self.isConnected = true
            self.statusMessage = "Port open. Handshaking with WinKeyer..."
            // Send Open / Echo Handshake Command [0x00, 0x02]
            sendRawBytes([0x00, 0x02])

            // Configure initial parameters
            Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                self.syncAllSettings()
            }
        } else {
            self.isConnected = false
            self.statusMessage = "Failed to open \(selectedPort)"
        }
    }

    public func disconnect() {
        // Send Close Command [0x00, 0x03]
        if isConnected {
            sendRawBytes([0x00, 0x03])
        }
        serial.closePort()
        isConnected = false
        isTransmitting = false
        wkVersion = "Unknown"
        statusMessage = "Disconnected"
    }

    // MARK: - Settings Synchronization

    public func syncAllSettings() {
        guard isConnected else { return }
        setSpeed(wpm)
        setMode(mode)
        setSidetone(sidetoneHz)
        setWeight(weight)
    }

    public func setSpeed(_ speedWPM: Int) {
        self.wpm = max(5, min(60, speedWPM))
        UserDefaults.standard.set(self.wpm, forKey: "winkeyerWPM")
        // WinKeyer Speed Command: [0x02, <WPM>]
        sendRawBytes([0x02, UInt8(self.wpm)])
    }

    public func setMode(_ keyerMode: WinKeyerMode) {
        self.mode = keyerMode
        // WinKeyer Mode Register: [0x01, <val>]
        var modeByte: UInt8 = UInt8(keyerMode.rawValue)
        if paddleSwap { modeByte |= 0x04 }
        if autoSpace { modeByte |= 0x10 }
        sendRawBytes([0x01, modeByte])
    }

    public func setSidetone(_ hz: Int) {
        self.sidetoneHz = hz
        // WK Sidetone Table: 1=4000Hz, 2=2000Hz, 3=1333Hz, 4=1000Hz, 5=800Hz, 6=666Hz, 7=571Hz, 8=500Hz, 9=444Hz, 10=400Hz
        var code: UInt8 = 6 // ~666 Hz
        if hz >= 1000 { code = 4 }
        else if hz >= 800 { code = 5 }
        else if hz >= 650 { code = 6 }
        else if hz >= 550 { code = 7 }
        else if hz >= 480 { code = 8 }
        else { code = 9 }
        sendRawBytes([0x04, code])
    }

    public func setWeight(_ wt: Int) {
        self.weight = max(10, min(90, wt))
        // WK Weight Command: [0x03, <val>] (Standard 50)
        sendRawBytes([0x03, UInt8(self.weight)])
    }

    // MARK: - Text Transmission & Abort

    public func sendMorseText(_ text: String) {
        guard isConnected else { return }
        let upper = text.uppercased()
        guard !upper.isEmpty else { return }

        self.isTransmitting = true
        self.sentBuffer = upper

        // Convert string to bytes
        var bytes: [UInt8] = []
        for char in upper.utf8 {
            bytes.append(char)
        }
        sendRawBytes(bytes)
    }

    public func abort() {
        guard isConnected else { return }
        // WinKeyer Clear Buffer Command: [0x0A]
        sendRawBytes([0x0A])
        self.isTransmitting = false
        self.sentBuffer = ""
        self.statusMessage = "Transmission Aborted"
    }

    // MARK: - Raw I/O and Incoming Byte Parser

    private func sendRawBytes(_ bytes: [UInt8]) {
        let data = Data(bytes)
        serial.writeData(data)
    }

    private func handleIncomingData(_ data: Data) {
        for byte in data {
            if byte >= 0x10 && byte <= 0x35 {
                // Version response (e.g. 0x23 = WK2.3, 0x31 = WK3.1)
                let major = (byte >> 4) & 0x0F
                let minor = byte & 0x0F
                self.wkVersion = "K1EL WinKeyer v\(major).\(minor)"
                self.statusMessage = "Connected (\(wkVersion))"
            } else if byte >= 0x80 {
                // Sent character echo byte
                let charVal = byte & 0x7F
                let unicode = UnicodeScalar(charVal)
                let charStr = String(Character(unicode))
                self.lastEchoedChar = charStr
            } else if byte == 0xC0 {
                // Buffer empty / transmission complete
                self.isTransmitting = false
            }
        }
    }
}
