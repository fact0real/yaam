//
//  SerialKeyerDriver.swift
//  YAAM
//
//  Direct Hardware CW Keyer & PTT Controller via Serial Control Lines (DTR & RTS)
//  Provides microsecond-accurate Morse dit/dah pulsing over USB-to-UART bridges
//  (FTDI, CP210x, CH340, Prolific) and optoisolated transceiver keying interfaces.
//

import Combine
import Foundation
import SwiftUI

public enum SerialControlPin: String, CaseIterable, Identifiable, Codable, Sendable {
    case dtr = "DTR"
    case rts = "RTS"
    case none = "None / Disabled"

    public var id: String { rawValue }
}

@MainActor
public final class SerialKeyerDriver: ObservableObject {
    public static let shared = SerialKeyerDriver()

    // MARK: - Published State
    @Published public var isConnected: Bool = false
    @Published public var selectedPort: String = ""
    @Published public var cwPin: SerialControlPin = .dtr
    @Published public var pttPin: SerialControlPin = .rts
    @Published public var isInverted: Bool = false // True for active-low (optoisolator/transistor)
    @Published public var pttLeadInMs: Int = 25
    @Published public var pttTailMs: Int = 50
    @Published public var isTransmitting: Bool = false
    @Published public var statusMessage: String = "Disconnected"
    @Published public var availablePorts: [String] = []

    private let serialPort = SerialPortService()
    private var transmitTask: Task<Void, Never>?

    public init() {
        self.selectedPort = UserDefaults.standard.string(forKey: "serialKeyerPort") ?? ""
        let savedCW = UserDefaults.standard.string(forKey: "serialKeyerCWPin") ?? "DTR"
        self.cwPin = SerialControlPin(rawValue: savedCW) ?? .dtr
        let savedPTT = UserDefaults.standard.string(forKey: "serialKeyerPTTPin") ?? "RTS"
        self.pttPin = SerialControlPin(rawValue: savedPTT) ?? .rts
        self.isInverted = UserDefaults.standard.bool(forKey: "serialKeyerInverted")
        self.pttLeadInMs = UserDefaults.standard.object(forKey: "serialKeyerLeadIn") != nil
            ? UserDefaults.standard.integer(forKey: "serialKeyerLeadIn")
            : 25
        self.pttTailMs = UserDefaults.standard.object(forKey: "serialKeyerTail") != nil
            ? UserDefaults.standard.integer(forKey: "serialKeyerTail")
            : 50
        refreshPorts()
    }

    public func refreshPorts() {
        self.availablePorts = SerialPortService.availablePorts()
        if selectedPort.isEmpty, let first = availablePorts.first {
            selectedPort = first
        }
    }

    // MARK: - Port Lifecycle

    public func connect(port: String? = nil) {
        if let p = port { self.selectedPort = p }
        guard !selectedPort.isEmpty else {
            statusMessage = "No serial port selected"
            return
        }

        UserDefaults.standard.set(selectedPort, forKey: "serialKeyerPort")
        UserDefaults.standard.set(cwPin.rawValue, forKey: "serialKeyerCWPin")
        UserDefaults.standard.set(pttPin.rawValue, forKey: "serialKeyerPTTPin")
        UserDefaults.standard.set(isInverted, forKey: "serialKeyerInverted")
        UserDefaults.standard.set(pttLeadInMs, forKey: "serialKeyerLeadIn")
        UserDefaults.standard.set(pttTailMs, forKey: "serialKeyerTail")

        let ok = serialPort.openPort(path: selectedPort, baudRate: 9600)
        if ok {
            self.isConnected = true
            self.statusMessage = "Connected (\(selectedPort.components(separatedBy: "/").last ?? selectedPort))"
            // Ensure lines start inactive
            applyControlLines(cwActive: false, pttActive: false)
        } else {
            self.isConnected = false
            self.statusMessage = "Failed to open \(selectedPort)"
        }
    }

    public func disconnect() {
        abort()
        applyControlLines(cwActive: false, pttActive: false)
        serialPort.closePort()
        isConnected = false
        statusMessage = "Disconnected"
    }

    // MARK: - Line Control

    private func applyControlLines(cwActive: Bool, pttActive: Bool) {
        guard isConnected else { return }

        let effectiveCW = isInverted ? !cwActive : cwActive
        let effectivePTT = isInverted ? !pttActive : pttActive

        if cwPin == .dtr {
            serialPort.setDTR(active: effectiveCW)
        } else if cwPin == .rts {
            serialPort.setRTS(active: effectiveCW)
        }

        if pttPin == .dtr && cwPin != .dtr {
            serialPort.setDTR(active: effectivePTT)
        } else if pttPin == .rts && cwPin != .rts {
            serialPort.setRTS(active: effectivePTT)
        }
    }

    public func testKeyPulse() {
        guard isConnected else { return }
        Task {
            applyControlLines(cwActive: true, pttActive: pttPin != .none)
            try? await Task.sleep(nanoseconds: 70_000_000) // 70ms dit pulse
            applyControlLines(cwActive: false, pttActive: false)
        }
    }

    // MARK: - Precise Morse Transmission

    public func sendMorse(
        text: String,
        wpm: Int,
        onCharacter: (@Sendable @MainActor (String) -> Void)? = nil,
        onComplete: (@Sendable @MainActor () -> Void)? = nil
    ) {
        guard isConnected else { return }
        abort()

        let upper = text.uppercased()
        guard !upper.isEmpty else { return }

        self.isTransmitting = true
        let ditSec = 1.2 / Double(max(5, min(60, wpm)))
        let ditNs = UInt64(ditSec * 1_000_000_000)
        let dahNs = ditNs * 3
        let elementSpaceNs = ditNs
        let charSpaceNs = ditNs * 2 // total 3 with last element space
        let wordSpaceNs = ditNs * 4 // total 7 with previous char space

        transmitTask = Task { [weak self] in
            guard let self else { return }

            // PTT Lead-in Delay (lets amplifier / TR relay settle)
            if self.pttPin != .none {
                self.applyControlLines(cwActive: false, pttActive: true)
                let leadNs = UInt64(max(0, self.pttLeadInMs)) * 1_000_000
                if leadNs > 0 {
                    try? await Task.sleep(nanoseconds: leadNs)
                }
            }

            for char in upper {
                guard !Task.isCancelled else { break }

                let charStr = String(char)
                onCharacter?(charStr)

                if char == " " {
                    try? await Task.sleep(nanoseconds: wordSpaceNs)
                    continue
                }

                guard let pattern = CWKeyerService.morseAlphabet[char] else {
                    continue
                }

                for symbol in pattern {
                    guard !Task.isCancelled else { break }

                    if symbol == "." {
                        self.applyControlLines(cwActive: true, pttActive: self.pttPin != .none)
                        try? await Task.sleep(nanoseconds: ditNs)
                        self.applyControlLines(cwActive: false, pttActive: self.pttPin != .none)
                        try? await Task.sleep(nanoseconds: elementSpaceNs)
                    } else if symbol == "-" {
                        self.applyControlLines(cwActive: true, pttActive: self.pttPin != .none)
                        try? await Task.sleep(nanoseconds: dahNs)
                        self.applyControlLines(cwActive: false, pttActive: self.pttPin != .none)
                        try? await Task.sleep(nanoseconds: elementSpaceNs)
                    }
                }

                // Inter-character space
                try? await Task.sleep(nanoseconds: charSpaceNs)
            }

            // PTT Tail Delay
            if self.pttPin != .none && !Task.isCancelled {
                let tailNs = UInt64(max(0, self.pttTailMs)) * 1_000_000
                if tailNs > 0 {
                    try? await Task.sleep(nanoseconds: tailNs)
                }
            }

            self.applyControlLines(cwActive: false, pttActive: false)
            self.isTransmitting = false
            onComplete?()
        }
    }

    public func abort() {
        transmitTask?.cancel()
        transmitTask = nil
        applyControlLines(cwActive: false, pttActive: false)
        isTransmitting = false
    }
}
