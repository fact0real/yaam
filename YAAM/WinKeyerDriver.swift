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
    @Published public var pttLeadInMs: Int = 20
    @Published public var pttTailMs: Int = 30
    @Published public var keyingCompensationMs: Int = 0
    @Published public var farnsworthWpm: Int = 0
    @Published public var ditDahRatio: Int = 50
    @Published public var paddleSwap: Bool = false
    @Published public var autoSpace: Bool = false
    @Published public var isTransmitting: Bool = false
    @Published public var sentBuffer: String = ""
    @Published public var lastEchoedChar: String = ""
    @Published public var statusMessage: String = "Disconnected"
    @Published public var availableSerialPorts: [String] = []

    public var onCharacterEchoed: (@Sendable (String) -> Void)?
    public var onTransmissionComplete: (@Sendable () -> Void)?
    public var onPaddleBreakIn: (@Sendable () -> Void)?

    public func triggerPaddleBreakIn() {
        abort()
        onPaddleBreakIn?()
    }

    private let serial = SerialPortService.shared
    private var echoTimer: Timer?
    /// True from Host Open until the WinKeyer answers: the first byte it sends back is its revision code.
    private var awaitingRevision = false
    private var connectionGeneration: UInt64 = 0
    private var handshakeTask: Task<Void, Never>?
    private var pendingText: [UInt8] = []
    private var outstandingText: [UInt8] = []
    private var bufferPaused = false
    private var hardwareBusy = false
    private var startMarker: UInt8?
    private var nextMarker: UInt8 = 1
    private var startTimeout: Task<Void, Never>?
    private var transmissionMonitor: Task<Void, Never>?
    private var lastCharacterAcknowledged = ContinuousClock.now

    public init() {
        self.selectedPort = UserDefaults.standard.string(forKey: "winkeyerPort") ?? ""
        self.baudRate = UserDefaults.standard.integer(forKey: "winkeyerBaud") == 9600 ? 9600 : 1200
        let storedWPM = UserDefaults.standard.integer(forKey: "winkeyerWPM")
        self.wpm = storedWPM > 0 ? max(5, min(60, storedWPM)) : 24
        self.pttLeadInMs = UserDefaults.standard.object(forKey: "winkeyerLeadIn") != nil ? UserDefaults.standard.integer(forKey: "winkeyerLeadIn") : 20
        self.pttTailMs = UserDefaults.standard.object(forKey: "winkeyerTail") != nil ? UserDefaults.standard.integer(forKey: "winkeyerTail") : 30
        self.keyingCompensationMs = UserDefaults.standard.integer(forKey: "winkeyerCompensation")
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
        disconnect()
        if let p = port { self.selectedPort = p }
        if let b = baud { self.baudRate = b }

        UserDefaults.standard.set(selectedPort, forKey: "winkeyerPort")
        UserDefaults.standard.set(baudRate, forKey: "winkeyerBaud")

        guard !selectedPort.isEmpty else {
            statusMessage = "No serial port selected"
            return
        }

        statusMessage = "Opening \(selectedPort)..."

        let generation = connectionGeneration
        awaitingRevision = true
        let ok = serial.openPort(path: selectedPort, baudRate: baudRate, stopBits: 2) { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self, self.connectionGeneration == generation else { return }
                self.handleIncomingData(data)
            }
        }

        if ok {
            self.statusMessage = "Port open. Handshaking with WinKeyer..."
            // Admin: Host Open [0x00, 0x02]; the WinKeyer answers its revision code (K1EL WK3 datasheet, p. 5)
            awaitingRevision = true
            sendRawBytes([0x00, 0x02])

            handshakeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, self.connectionGeneration == generation, self.awaitingRevision else { return }
                self.disconnect()
                self.statusMessage = "WinKeyer did not confirm Host Open. Nothing sent; reconnect the device."
            }
        } else {
            awaitingRevision = false
            self.isConnected = false
            self.statusMessage = "Failed to open \(selectedPort)"
        }
    }

    public func disconnect() {
        connectionGeneration &+= 1
        handshakeTask?.cancel()
        handshakeTask = nil
        startTimeout?.cancel()
        startTimeout = nil
        transmissionMonitor?.cancel()
        transmissionMonitor = nil
        pendingText.removeAll()
        outstandingText.removeAll()
        startMarker = nil
        bufferPaused = false
        hardwareBusy = false
        // Send Close Command [0x00, 0x03]
        if isConnected {
            // Clear Buffer first (p. 10): the datasheet does not say that Host Close empties the buffer.
            sendRawBytes([0x0A, 0x00, 0x03])
        }
        serial.closePort()
        isConnected = false
        isTransmitting = false
        awaitingRevision = false
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
        setPTTDelays(leadInMs: pttLeadInMs, tailMs: pttTailMs)
        setKeyingCompensation(keyingCompensationMs)
        if farnsworthWpm > 0 { setFarnsworth(farnsworthWpm) }
        setDitDahRatio(ditDahRatio)
    }

    public func setSpeed(_ speedWPM: Int) {
        self.wpm = max(5, min(60, speedWPM))
        UserDefaults.standard.set(self.wpm, forKey: "winkeyerWPM")
        // Set WPM Speed: [0x02, <WPM>], 5-99 (K1EL WK3 datasheet, p. 8)
        sendRawBytes([0x02, UInt8(self.wpm)])
    }

    public func setMode(_ keyerMode: WinKeyerMode) {
        self.mode = keyerMode
        // Set WinKeyer Mode: [0x0E, <mode register>] (K1EL WK3 datasheet, p. 11)
        sendRawBytes([0x0E, Self.modeRegister(keyerMode, paddleSwap: paddleSwap, autoSpace: autoSpace)])
    }

    /// The mode register, as the datasheet's table 12 (p. 11) lays it out: bits 5-4 the key mode (00 iambic B,
    /// 01 iambic A, 10 ultimatic, 11 bug), bit 3 paddle swap, bit 2 serial echoback (on: the WinKeyer sends back each
    /// letter once it has sent it, which handleIncomingData reports), bit 1 autospace. Bits 7 (paddle watchdog off),
    /// 6 (paddle echoback) and 0 (contest spacing) stay 0.
    static func modeRegister(_ keyerMode: WinKeyerMode, paddleSwap: Bool, autoSpace: Bool) -> UInt8 {
        let keyMode: UInt8
        switch keyerMode {
        case .iambicB: keyMode = 0b00
        case .iambicA: keyMode = 0b01
        case .ultimatic: keyMode = 0b10
        case .bug: keyMode = 0b11
        }
        var modeByte: UInt8 = keyMode << 4
        if paddleSwap { modeByte |= 0x08 }
        modeByte |= 0x04
        if autoSpace { modeByte |= 0x02 }
        return modeByte
    }

    public func setSidetone(_ hz: Int) {
        self.sidetoneHz = hz
        // Sidetone Control: [0x01, N] (K1EL WK3 datasheet, p. 7). N from the WK1/WK2 table (table 7, the one in force
        // outside WK3 mode, which this driver never sets): 1=4000Hz, 2=2000Hz, 3=1333Hz, 4=1000Hz, 5=800Hz, 6=666Hz,
        // 7=571Hz, 8=500Hz, 9=444Hz, 10=400Hz. Bit 7 (paddle-only sidetone) stays 0.
        var code: UInt8 = 6 // ~666 Hz
        if hz >= 1000 { code = 4 }
        else if hz >= 800 { code = 5 }
        else if hz >= 650 { code = 6 }
        else if hz >= 550 { code = 7 }
        else if hz >= 480 { code = 8 }
        else { code = 9 }
        sendRawBytes([0x01, code])
    }

    public func setWeight(_ wt: Int) {
        self.weight = max(10, min(90, wt))
        // Set Weighting: [0x03, <val>], 10-90, 50 = no adjustment (K1EL WK3 datasheet, p. 8)
        sendRawBytes([0x03, UInt8(self.weight)])
    }

    public func setPTTDelays(leadInMs: Int, tailMs: Int) {
        self.pttLeadInMs = max(0, min(2500, leadInMs))
        self.pttTailMs = max(0, min(2500, tailMs))
        UserDefaults.standard.set(self.pttLeadInMs, forKey: "winkeyerLeadIn")
        UserDefaults.standard.set(self.pttTailMs, forKey: "winkeyerTail")
        // Set PTT Lead/Tail: [0x04, lead-in, tail], each 0-250 in 10 ms steps (K1EL WK3 datasheet, p. 8)
        let leadUnits = UInt8(min(250, self.pttLeadInMs / 10))
        let tailUnits = UInt8(min(250, self.pttTailMs / 10))
        sendRawBytes([0x04, leadUnits, tailUnits])
    }

    public func setKeyingCompensation(_ ms: Int) {
        self.keyingCompensationMs = max(0, min(31, ms))
        UserDefaults.standard.set(self.keyingCompensationMs, forKey: "winkeyerCompensation")
        // Set Key Comp: [0x11, ms], 0-250 ms (K1EL WK3 datasheet, p. 13)
        sendRawBytes([0x11, UInt8(self.keyingCompensationMs)])
    }

    public func setFarnsworth(_ fwpm: Int) {
        self.farnsworthWpm = fwpm <= 0 ? 0 : max(10, min(60, fwpm))
        // Set Farns WPM: [0x0D, fwpm] (K1EL WK3 datasheet, p. 10)
        sendRawBytes([0x0D, UInt8(max(10, self.farnsworthWpm == 0 ? wpm : self.farnsworthWpm))])
    }

    public func setDitDahRatio(_ ratio: Int) {
        self.ditDahRatio = max(33, min(66, ratio))
        // Set Dit/Dah Ratio: [0x17, ratio], 33-66, 50 = 1:3 (K1EL WK3 datasheet, pp. 14-15)
        sendRawBytes([0x17, UInt8(self.ditDahRatio)])
    }

    public func testKeyPulse() {
        guard isConnected else { return }
        // Sends test letter 'E' (single dit) to verify physical key line
        sendMorseText("E")
    }

    // MARK: - Text Transmission & Abort

    public func sendMorseText(_ text: String) {
        guard isConnected else { return }
        guard let upper = MorseTiming.safeText(text) else {
            statusMessage = "Nothing sent: unsupported CW text or message too long."
            return
        }
        abort(reportEnd: false)

        self.isTransmitting = true
        self.sentBuffer = upper

        pendingText = Array(upper.utf8)
        // An admin echo forms a barrier after Clear Buffer: old idle/status/echo bytes cannot finish a new send.
        nextMarker = nextMarker == 31 ? 1 : nextMarker + 1
        startMarker = nextMarker
        sendRawBytes([0x00, 0x04, nextMarker])
        startTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.startMarker != nil else { return }
            self.abort()
            self.statusMessage = "WinKeyer did not confirm the buffer clear. Transmission stopped."
        }
        lastCharacterAcknowledged = .now
        transmissionMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, self.isTransmitting else { return }
                if self.lastCharacterAcknowledged.duration(to: .now) > .seconds(10) {
                    self.abort(reportEnd: false)
                    self.disconnect()
                    self.statusMessage = "WinKeyer stopped: no character acknowledgement. Reconnect the device."
                    self.onTransmissionComplete?()
                    return
                }
            }
        }
    }

    /// Clears the WinKeyer's buffer. reportEnd false: the caller resets its own state and sends next (CWKeyerService).
    public func abort(reportEnd: Bool = true) {
        transmissionMonitor?.cancel()
        transmissionMonitor = nil
        startTimeout?.cancel()
        startTimeout = nil
        startMarker = nil
        pendingText.removeAll()
        outstandingText.removeAll()
        hardwareBusy = false
        guard isConnected else { return }
        // WinKeyer Clear Buffer Command: [0x0A]
        sendRawBytes([0x0A])
        self.isTransmitting = false
        self.sentBuffer = ""
        self.statusMessage = "Transmission Aborted"
        if reportEnd { onTransmissionComplete?() }
    }

    // MARK: - Raw I/O and Incoming Byte Parser

    private func sendRawBytes(_ bytes: [UInt8]) {
        guard isConnected || (awaitingRevision && bytes == [0x00, 0x02]) else { return }
        let data = Data(bytes)
        if !serial.writeData(data) {
            isConnected = false
            awaitingRevision = false
            disconnect()
            statusMessage = "WinKeyer serial write failed; connection closed."
            onTransmissionComplete?()
        }
    }

    private func pumpText() {
        guard isConnected, isTransmitting, startMarker == nil, !bufferPaused else { return }
        let count = min(pendingText.count, max(0, 32 - outstandingText.count))
        guard count > 0 else { return }
        let bytes = Array(pendingText.prefix(count))
        pendingText.removeFirst(count)
        outstandingText.append(contentsOf: bytes)
        sendRawBytes(bytes)
    }

    /// What the WinKeyer sends back (K1EL WK3 datasheet, pp. 3, 9, 11 and 14): status bytes 110xxxxx, speed pot bytes
    /// 10xxxxxx, and otherwise plain ASCII: the revision code once, right after Host Open, then the echo of each letter.
    private func handleIncomingData(_ data: Data) {
        guard isConnected || awaitingRevision else { return }
        for byte in data {
            if let marker = startMarker {
                guard byte == marker else { continue }
                startMarker = nil
                startTimeout?.cancel()
                startTimeout = nil
                lastCharacterAcknowledged = .now
                bufferPaused = false
                hardwareBusy = false
                pumpText()
                continue
            }
            if (byte & 0xE0) == 0xC0 {
                // Status byte (p. 14, table 14): bit 4 WAIT, bit 3 KEYDOWN (tune), bit 2 BUSY, bit 1 BREAKIN (the
                // paddle was touched), bit 0 XOFF (the buffer is more than 2/3 full). Only BREAKIN is the paddle:
                // XOFF and KEYDOWN must not stop the CW.
                if (byte & 0x02) != 0 {
                    abort(reportEnd: false)
                    self.onPaddleBreakIn?()
                    continue
                }
                bufferPaused = (byte & 0x01) != 0
                hardwareBusy = (byte & 0x1C) != 0
                pumpText()
                if !hardwareBusy, pendingText.isEmpty, outstandingText.isEmpty, isTransmitting {
                    self.isTransmitting = false
                    self.onTransmissionComplete?()
                }
            } else if byte >= 0x80 {
                // Speed pot byte, 10xxxxxx (p. 9, table 8): the speed pot is not used here. 111xxxxx is not defined.
            } else if awaitingRevision {
                // Host Open's answer: the revision code, a decimal number (p. 5: 31 for rev 31.03)
                awaitingRevision = false
                handshakeTask?.cancel()
                handshakeTask = nil
                self.isConnected = true
                self.wkVersion = "K1EL WinKeyer v\(byte)"
                self.statusMessage = "Connected (\(wkVersion))"
                syncAllSettings()
            } else if byte >= 0x20 {
                // Echo of a letter the WinKeyer has just sent, in plain ASCII (p. 3; p. 11, mode bit 2)
                let charStr = String(Character(UnicodeScalar(byte)))
                self.lastEchoedChar = charStr
                self.onCharacterEchoed?(charStr)
                let echoedIndex = byte == 0x20 ? outstandingText.startIndex
                    : (outstandingText.firstIndex { $0 != 0x20 } ?? outstandingText.endIndex)
                if outstandingText.indices.contains(echoedIndex), outstandingText[echoedIndex] == byte {
                    lastCharacterAcknowledged = .now
                    outstandingText.removeFirst(echoedIndex + 1)
                    pumpText()
                }
            }
        }
    }
}
