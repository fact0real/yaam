//
//  Lab599TX500Driver.swift
//  YAAM
//
//  Dedicated Hardware Driver & CAT Controller for Lab599 Discovery TX-500
//  Engineered specifically for macOS over USB-C (AD-514/AD-502 CAT & AD-508/AD-509 Audio)
//  Kenwood-style CAT framing; verified FT8 uses LAB599 protocol MD/PT readback at 9600 baud.
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
    @Published public var stopBits: Int = 2 // Existing compatibility default; user manual specifies 8N1. Both remain selectable.
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
        Lab599TX500SMeter.description(forUnits: sMeterValue)
    }

    // MARK: - Internal Transport & Polling
    nonisolated private let serialPort = SerialPortService()
    private var receiveBuffer = ""
    private var connectionGeneration = UUID()
    private var catReplies: [String: (sequence: UInt64, value: String)] = [:]
    private var replySequence: UInt64 = 0
    private var verifyingFT8 = false

    private var pollingTimer: DispatchSourceTimer?
    private var pttWatchdog: DispatchWorkItem?
    private var pttGeneration = UUID()
    private let noticeSource = TransmitNotices.Source(name: "TX-500")
    // The KY pieces of a CW message still to be sent; cancelled by a new message, STOP and disconnect
    private var pendingMorseChunks: [DispatchWorkItem] = []
    private var morseGeneration: UInt64 = 0
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
        // Registered so that quitting YAAM can release this path (TransmitShutdown).
        TransmitShutdown.register("TX-500", isTransmitting: { [weak self] in self?.isTransmitting ?? false },
                                  owner: self, release: { [weak self] in self?.setPTT(false) })
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

        connectionGeneration = UUID()
        let connectionID = connectionGeneration
        catReplies.removeAll()
        receiveBuffer = ""
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
                guard self?.connectionGeneration == connectionID else { return }
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
        connectionGeneration = UUID()
        catReplies.removeAll()
        cancelPendingMorseChunks()
        if isConnected { stopMorse() }
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
        sendRaw("FA;MD;\(Lab599TX500SMeter.readCommand)PC;")
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
    public func setPTT(_ transmit: Bool, maximumDuration: TimeInterval = TXLimits.tx500PTT) {

        if !transmit, !isConnected {
            pttGeneration = UUID()
            pttWatchdog?.cancel()
            pttWatchdog = nil
            isTransmitting = false
            return
        }
        if transmit {
            guard !TransmitShutdown.isShuttingDown else { return }
            guard isConnected else {
                lastMessage = TXLimits.notConnectedMessage(radio: "TX-500")
                return
            }
            // Repeated key-down is idempotent: it cannot renew the first key-down's deadline.
            if pttWatchdog != nil { return }
        }
        pttGeneration = UUID()
        let generation = pttGeneration
        pttWatchdog?.cancel()
        pttWatchdog = nil

        if transmit {
            self.isTransmitting = true
            self.lastMessage = "TX-500 Transmitting (PTT Active)"
            sendRaw("TX;")

            let limit = TXLimits.pttSafetyTimer(maximumDuration)
            let keyedAt = Date()
            let started = ProcessInfo.processInfo.systemUptime
            let watchdog = DispatchWorkItem { [weak self] in
                guard let self, self.pttGeneration == generation, self.isTransmitting else { return }
                self.setPTT(false)
                self.lastMessage = TXLimits.safetyTimerMessage(radio: "TX-500", keyedAt: keyedAt, limit: limit,
                    elapsed: ProcessInfo.processInfo.systemUptime - started)
                TransmitNotices.shared.post(self.noticeSource, text: self.lastMessage)
            }
            pttWatchdog = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + limit, execute: watchdog)
        } else {
            self.isTransmitting = false
            self.lastMessage = "TX-500 Receive (PTT Released)"
            sendRaw("RX;")
        }
    }

    enum FT8VerificationError: LocalizedError {
        case refused(String)
        var errorDescription: String? { if case .refused(let text) = self { return text }; return nil }
    }

    private func freshCATReply(_ prefix: String, session: UUID, before deadline: Date) async throws -> String {
        try Task.checkCancellation()
        guard isConnected, connectionGeneration == session else { throw FT8VerificationError.refused("CAT disconnected") }
        let baseline = replySequence
        guard sendRaw(prefix + ";") else { throw FT8VerificationError.refused("CAT write failed") }
        let start = ContinuousClock.now
        while ContinuousClock.now - start < .milliseconds(400), Date() < deadline {
            try Task.checkCancellation()
            guard isConnected, connectionGeneration == session else { throw FT8VerificationError.refused("CAT connection changed") }
            if let reply = catReplies[prefix], reply.sequence > baseline { return reply.value }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw FT8VerificationError.refused("No fresh \(prefix) reply; select LAB599 CAT protocol and check the cable")
    }

    /// No audio may start until fresh documented MD6 and PT1 readbacks arrive in this slot.
    /// Reads never infer TX from the host's optimistic isTransmitting flag or the DIG preference.
    func keyFT8Verified(maximumDuration: TimeInterval, before deadline: Date) async throws {
        guard !verifyingFT8, !isTransmitting, isConnected, !TransmitShutdown.isShuttingDown else {
            throw FT8VerificationError.refused("TX-500 is unavailable or already in use")
        }
        verifyingFT8 = true
        let session = connectionGeneration
        defer { verifyingFT8 = false }
        do {
            guard try await freshCATReply("MD", session: session, before: deadline) == "MD6" else {
                throw FT8VerificationError.refused("The radio must report DIG (MD6); select DIG on the radio")
            }
            guard try await freshCATReply("PT", session: session, before: deadline) == "PT0" else {
                throw FT8VerificationError.refused("The radio did not confirm receive before TX")
            }
            try Task.checkCancellation()
            guard Date() < deadline, !isTransmitting else { throw FT8VerificationError.refused("The slot deadline passed or another transmission started") }
            setPTT(true, maximumDuration: maximumDuration)
            guard isTransmitting,
                  try await freshCATReply("PT", session: session, before: deadline) == "PT1", Date() < deadline else {
                throw FT8VerificationError.refused("The radio did not confirm TX in time for this slot")
            }
        } catch {
            // Keep cleanup at the acquired serial session; never release a replacement connection.
            if connectionGeneration == session { setPTT(false) }
            let text = "TX-500: FT8 audio was blocked at \(TXLimits.utc()): \(error.localizedDescription). RX was requested; physical receive is unconfirmed. Other YAAM tools remain available. Check the radio is on receive, select DIG and LAB599 CAT protocol, then retry the next slot."
            lastMessage = text
            TransmitNotices.shared.post(noticeSource, text: text)
            throw error
        }
    }

    /// Runs independently of the cancelled FT8 task after its synchronous RX request.
    /// A newer key-down or serial session invalidates this readback, so it cannot affect another transmission.
    func checkFT8Receive() {
        let session = connectionGeneration, generation = pttGeneration
        Task { @MainActor [weak self] in
            guard let self, self.connectionGeneration == session, self.pttGeneration == generation else { return }
            do {
                let reply = try await self.freshCATReply("PT", session: session, before: Date().addingTimeInterval(0.4))
                guard self.connectionGeneration == session, self.pttGeneration == generation else { return }
                if reply == "PT0" { return }
            } catch {
                guard self.connectionGeneration == session, self.pttGeneration == generation else { return }
            }
            let text = "TX-500: FT8 ended and RX was requested at \(TXLimits.utc()), but fresh PT0 receive was NOT confirmed. Other YAAM tools remain available. Release PTT locally and check the radio is on receive before sending again."
            self.lastMessage = text
            TransmitNotices.shared.post(self.noticeSource, text: text)
        }
    }

    // MARK: - Morse Code (CW) Operations

    /// Transmits text directly via Kenwood CAT Morse `KY <text>;` to TX-500's internal keyer
    public func sendMorse(_ text: String, wpm: Int = 24) {
        guard isConnected else { return }
        guard let clean = MorseTiming.safeText(text) else {
            lastMessage = "Nothing sent: unsupported CW text or message too long."
            return
        }
        if pendingMorseChunks.isEmpty { cancelPendingMorseChunks() } else { stopMorse() }

        // Set keyer speed first: KS<wpm>;
        let clampedWPM = max(5, min(60, wpm))
        sendRaw(String(format: "KS%03d;", clampedWPM))

        // Kenwood KY command: buffers up to 24 characters at a time. The text is cut at spaces into pieces of
        // at most 24 characters. Each later piece is sent when, by the Morse timing, the radio has keyed the one
        // before, plus a word gap: right whether the radio queues KY texts or refuses one while it is keying.
        let chunks = MorseTiming.chunks(of: clean, limit: 24)
        let start = DispatchTime.now()
        let generation = morseGeneration
        var delay: TimeInterval = 0

        for (i, chunk) in chunks.enumerated() {
            let cmd = "KY \(chunk);"
            if i == 0 {
                sendRaw(cmd)
            } else {
                let piece = DispatchWorkItem { [weak self] in
                    guard self?.isConnected == true, self?.morseGeneration == generation else { return }
                    self?.sendRaw(cmd)
                }
                pendingMorseChunks.append(piece)
                DispatchQueue.main.asyncAfter(deadline: start + delay, execute: piece)
            }
            delay += MorseTiming.duration(of: chunk, wpm: clampedWPM) + MorseTiming.handover(wpm: clampedWPM)
        }

        self.lastMessage = "Transmitting CW: \(clean)"
    }

    /// Aborts active CW transmission
    public func stopMorse() {
        cancelPendingMorseChunks()
        guard isConnected else { return }
        sendRaw("KY ;RX;")
        self.lastMessage = "CW Transmission Aborted"
    }

    /// Cancels the KY pieces of the last message that have not been sent yet
    private func cancelPendingMorseChunks() {
        morseGeneration &+= 1
        pendingMorseChunks.forEach { $0.cancel() }
        pendingMorseChunks.removeAll()
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
        if response.hasPrefix("MD") || response.hasPrefix("PT") {
            replySequence &+= 1
            catReplies[String(response.prefix(2))] = (replySequence, response)
        }
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
                // Unknown firmware codes must never be presented as verified DIG.
                self.mode = (1...7).contains(code) ? (TX500Mode(rawValue: code)?.name ?? "Unknown") : "Unknown (MD\(code))"
            }
        // S-Meter: SM + P1 (always 0) + P2 (0000 to 0030), e.g. SM00015 (Lab599 CAT guide rev.3, p.9)
        } else if response.hasPrefix("SM") {
            if let units = Lab599TX500SMeter.units(fromReply: response) {
                self.sMeterValue = units
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
                guard let self = self, self.isConnected, !self.isTransmitting, !self.verifyingFT8 else { return }
                // Poll frequency and S-meter
                self.sendRaw("FA;\(Lab599TX500SMeter.readCommand)")
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
