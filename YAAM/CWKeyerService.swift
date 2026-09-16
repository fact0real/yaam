//
//  CWKeyerService.swift
//  YAAM
//
//  Native Morse Code Keyer & Macro Automation Engine
//  Supports Morse over CAT, WinKeyer, TCI DSP, cwdaemon network keying, and local macOS sine-wave sidetone audio.
//  Includes PARIS-calibrated timing, customizable F1-F12 memory banks (RUN, S&P, Ragchew, Custom),
//  dynamic tokens, cut-numbers (5NN), Auto-CQ repeat scheduler, and live transmit streams.
//

import AVFoundation
import Combine
import Foundation
import Network

public enum CWTransmissionMode: String, CaseIterable, Identifiable, Sendable {
    case icomUSB = "Icom USB (CI-V CAT & Pin)"
    case winkeyer = "K1EL WinKeyer (USB Serial)"
    case serialDTR_RTS = "Serial Pin (DTR/RTS Keying)"
    case catMorse = "CAT Morse (Rig/FLRig)"
    case lab599TX500 = "Lab599 TX-500 (USB-C CAT & Pin)"
    case fx4cr = "FX-4CR (USB-C & Bluetooth CAT/Pin)"
    case xiegu6100 = "Xiegu X6100 (USB-C CAT & Pin)"
    case tci = "TCI DSP (SunSDR / Thetis)"
    case cwdaemon = "cwdaemon (UDP 6789)"
    case audioOnly = "Audio Sidetone Only"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .icomUSB: return "radio.fill"
        case .winkeyer: return "cable.connector.horizontal"
        case .serialDTR_RTS: return "cable.connector"
        case .catMorse: return "antenna.radiowaves.left.and.right"
        case .lab599TX500: return "bolt.horizontal.fill"
        case .fx4cr: return "antenna.radiowaves.left.and.right"
        case .xiegu6100: return "radio.fill"
        case .tci: return "waveform.badge.magnifyingglass"
        case .cwdaemon: return "network"
        case .audioOnly: return "speaker.wave.2.fill"
        }
    }
}

public enum CWMemoryBank: String, CaseIterable, Identifiable, Codable, Sendable {
    case run = "RUN (CQ Pileup)"
    case searchAndPounce = "S&P (Search & Pounce)"
    case ragchew = "DX / Ragchew"
    case custom = "Custom Bank"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .run: return "RUN"
        case .searchAndPounce: return "S&P"
        case .ragchew: return "Ragchew"
        case .custom: return "Custom"
        }
    }

    public var iconName: String {
        switch self {
        case .run: return "flame.fill"
        case .searchAndPounce: return "binoculars.fill"
        case .ragchew: return "quote.bubble.fill"
        case .custom: return "slider.horizontal.3"
        }
    }
}

public struct CWMacro: Identifiable, Codable, Sendable {
    public let id: Int // 1...12 (F1...F12)
    public var label: String
    public var template: String
    public var bank: CWMemoryBank

    public init(id: Int, label: String, template: String, bank: CWMemoryBank = .run) {
        self.id = id
        self.label = label
        self.template = template
        self.bank = bank
    }

    public var functionKeyTitle: String {
        return "F\(id)"
    }
}

@MainActor
public final class CWKeyerService: ObservableObject {
    public static let shared = CWKeyerService()

    // MARK: - Published State
    @Published public var isTransmitting: Bool = false
    @Published public var wpm: Int = 24
    @Published public var sidetonePitchHz: Double = 650.0
    @Published public var sidetoneEnabled: Bool = true
    @Published public var sidetoneVolume: Float = 0.5
    @Published public var transmissionMode: CWTransmissionMode = .catMorse
    @Published public var activeBufferText: String = ""
    @Published public var currentlyTransmittingChar: String = ""
    @Published public var sentHistory: [String] = []
    @Published public var cwdaemonHost: String = "127.0.0.1"
    @Published public var cwdaemonPort: Int = 6789

    // Bank Selection & Cut-Numbers
    @Published public var activeBank: CWMemoryBank = .run
    @Published public var useCutNumbers: Bool = true // 599 -> 5NN, 001 -> TT1

    // Auto-CQ Loop State
    @Published public var isAutoCQActive: Bool = false
    @Published public var autoCQIntervalSeconds: Int = 4
    @Published public var autoCQCountdown: Int = 0

    // Memory Store for all 4 banks
    @Published public var bankStorage: [CWMemoryBank: [CWMacro]] = [:]

    // Computed property for backwards compatibility
    public var macros: [CWMacro] {
        get {
            return bankStorage[activeBank] ?? defaultMacros(for: activeBank)
        }
        set {
            bankStorage[activeBank] = newValue
            saveMacros()
        }
    }

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var transmitTask: Task<Void, Never>?
    private var autoCQTask: Task<Void, Never>?
    weak var rigControlClientRef: RigControlClient?

    public init() {
        self.wpm = UserDefaults.standard.integer(forKey: "cwKeyerWPM") > 0 ? UserDefaults.standard.integer(forKey: "cwKeyerWPM") : 24
        self.sidetonePitchHz = UserDefaults.standard.double(forKey: "cwSidetonePitch") > 0 ? UserDefaults.standard.double(forKey: "cwSidetonePitch") : 650.0
        self.useCutNumbers = UserDefaults.standard.object(forKey: "cwUseCutNumbers") as? Bool ?? true
        let storedInterval = UserDefaults.standard.integer(forKey: "cwAutoCQInterval")
        self.autoCQIntervalSeconds = storedInterval >= 2 ? storedInterval : 4

        loadMacros()
        setupAudioEngine()
        setupWinKeyerBindings()
    }

    private func setupWinKeyerBindings() {
        WinKeyerDriver.shared.onCharacterEchoed = { [weak self] char in
            Task { @MainActor [weak self] in
                guard let self = self, self.transmissionMode == .winkeyer else { return }
                self.currentlyTransmittingChar = char
            }
        }
        WinKeyerDriver.shared.onTransmissionComplete = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.transmissionMode == .winkeyer else { return }
                self.isTransmitting = false
                self.currentlyTransmittingChar = ""
                self.activeBufferText = ""
            }
        }
        WinKeyerDriver.shared.onPaddleBreakIn = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handlePaddleBreakIn()
            }
        }
    }

    public var hardwareStatusSummary: (isConnected: Bool, title: String, detail: String) {
        switch transmissionMode {
        case .winkeyer:
            let wk = WinKeyerDriver.shared
            return (wk.isConnected, wk.isConnected ? wk.wkVersion : "Disconnected", wk.selectedPort.isEmpty ? "No port" : wk.selectedPort.components(separatedBy: "/").last ?? wk.selectedPort)
        case .serialDTR_RTS:
            let sk = SerialKeyerDriver.shared
            let pinDesc = "CW:\(sk.cwPin.rawValue) PTT:\(sk.pttPin.rawValue)"
            return (sk.isConnected, sk.isConnected ? "Serial Keyer" : "Disconnected", sk.isConnected ? pinDesc : (sk.selectedPort.isEmpty ? "No port" : sk.selectedPort.components(separatedBy: "/").last ?? sk.selectedPort))
        case .catMorse:
            if FX4CRDriver.shared.isConnected {
                let d = FX4CRDriver.shared
                return (true, "FX-4CR CAT (\(d.connectionType.rawValue))", "\(d.formattedFrequency) \(d.mode)")
            } else if IcomUSBRadioDriver.shared.isConnected {
                let d = IcomUSBRadioDriver.shared
                return (true, "\(d.model.rawValue) CI-V", "\(d.formattedFrequency) \(d.mode)")
            } else if rigControlClientRef?.state.isConnected == true {
                let snap = rigControlClientRef?.snapshot
                return (true, "Hamlib CAT", snap != nil ? "\(snap!.frequencyMHz) \(snap!.mode)" : "Connected")
            } else if FLRigClient.shared.isConnected {
                return (true, "FLRig CAT", "\(String(format: "%.3f", FLRigClient.shared.frequencyHz / 1_000_000)) MHz")
            } else {
                return (false, "CAT Offline", "Connect Rig / FLRig")
            }
        case .icomUSB:
            let icom = IcomUSBRadioDriver.shared
            let portShort = icom.selectedPort.isEmpty ? "No port" : icom.selectedPort.components(separatedBy: "/").last ?? icom.selectedPort
            return (icom.isConnected, icom.isConnected ? "\(icom.model.rawValue) CI-V" : "Icom Offline", portShort)
        case .lab599TX500:
            let tx500 = Lab599TX500Driver.shared
            return (tx500.isConnected, tx500.isConnected ? "TX-500 CAT/Pin" : "TX-500 Offline", tx500.selectedPort.isEmpty ? "No port" : tx500.selectedPort.components(separatedBy: "/").last ?? tx500.selectedPort)
        case .fx4cr:
            let fx4cr = FX4CRDriver.shared
            let portShort = fx4cr.selectedPort.isEmpty ? "No port" : fx4cr.selectedPort.components(separatedBy: "/").last ?? fx4cr.selectedPort
            return (fx4cr.isConnected, fx4cr.isConnected ? "FX-4CR (\(fx4cr.connectionType.rawValue))" : "FX-4CR Offline", portShort)
        case .xiegu6100:
            let xiegu = Xiegu6100Driver.shared
            let portShort = xiegu.selectedPort.isEmpty ? "No port" : xiegu.selectedPort.components(separatedBy: "/").last ?? xiegu.selectedPort
            return (xiegu.isConnected, xiegu.isConnected ? "Xiegu X6100 CI-V" : "X6100 Offline", portShort)
        case .tci:
            return (TCIClient.shared.isConnected, TCIClient.shared.isConnected ? "TCI Connected" : "TCI Offline", "ExpertSDR")
        case .cwdaemon:
            return (true, "cwdaemon", "\(cwdaemonHost):\(cwdaemonPort)")
        case .audioOnly:
            return (true, "Audio Sidetone", "Local Sounder")
        }
    }

    // MARK: - Audio Sidetone Setup

    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)
        engine.connect(player, to: mainMixer, format: format)

        do {
            try engine.start()
            self.audioEngine = engine
            self.playerNode = player
        } catch {
            print("Audio engine init error: \(error)")
        }
    }

    // MARK: - WPM Adjustment

    public func increaseWPM(_ delta: Int = 1) {
        wpm = min(50, wpm + delta)
        UserDefaults.standard.set(wpm, forKey: "cwKeyerWPM")
    }

    public func decreaseWPM(_ delta: Int = 1) {
        wpm = max(10, wpm - delta)
        UserDefaults.standard.set(wpm, forKey: "cwKeyerWPM")
    }

    public func setWPM(_ newWpm: Int) {
        wpm = max(10, min(50, newWpm))
        UserDefaults.standard.set(wpm, forKey: "cwKeyerWPM")
    }

    // MARK: - Cut-Numbers Translation (Standard Contest Conventions)

    public func applyCutNumbers(_ text: String) -> String {
        guard useCutNumbers else { return text }
        var result = text
        result = result.replacingOccurrences(of: "599", with: "5NN")
        return result
    }

    public func cutSerial(_ serial: Int) -> String {
        let raw = String(format: "%03d", serial)
        guard useCutNumbers else { return raw }
        return raw
            .replacingOccurrences(of: "0", with: "T")
            .replacingOccurrences(of: "9", with: "N")
    }

    // MARK: - Macro Expansion with Rich Ham Radio Tokens

    @Published public var isPaddleBreakInActive: Bool = false
    public var onPaddleBreakIn: (() -> Void)?
    private var paddleResetTask: Task<Void, Never>?

    public var isAutoCQRunning: Bool {
        return isAutoCQActive
    }

    public func handlePaddleBreakIn() {
        guard isTransmitting || isAutoCQRunning else { return }
        stop()
        isPaddleBreakInActive = true
        onPaddleBreakIn?()

        paddleResetTask?.cancel()
        paddleResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.isPaddleBreakInActive = false
        }
    }

    public func expandMacro(
        _ template: String,
        myCall: String = "",
        call: String = "",
        rst: String = "599",
        name: String = "",
        qth: String = "",
        serial: Int = 1,
        exch: String = "",
        band: String = "",
        freq: String = ""
    ) -> String {
        let sentRst = useCutNumbers && rst == "599" ? "5NN" : (rst.isEmpty ? "5NN" : rst)
        let serialFormatted = useCutNumbers ? cutSerial(serial) : String(format: "%03d", serial)

        // Query CallHistoryLookupEngine for predicted exchange details
        let hist = CallHistoryLookupEngine.shared.lookup(callsign: call)
        let resolvedName = !name.isEmpty ? name : (hist?.name ?? "")
        let resolvedExch = !exch.isEmpty ? exch : (hist?.userExchange ?? "")
        let resolvedState = hist?.state ?? ""
        let resolvedSect = hist?.arrlSection ?? ""
        let resolvedGrid = hist?.gridSquare ?? ""
        let resolvedZone: String = {
            if let z = hist?.cqZone, z > 0 {
                return z < 10 ? "0\(z)" : "\(z)"
            }
            return ""
        }()

        var result = template
            .replacingOccurrences(of: "{MYCALL}", with: myCall.uppercased())
            .replacingOccurrences(of: "{CALL}", with: call.uppercased())
            .replacingOccurrences(of: "{RST}", with: sentRst)
            .replacingOccurrences(of: "{SENT_RST}", with: sentRst)
            .replacingOccurrences(of: "{NAME}", with: resolvedName.uppercased())
            .replacingOccurrences(of: "{HISNAME}", with: resolvedName.uppercased())
            .replacingOccurrences(of: "{QTH}", with: qth.uppercased())
            .replacingOccurrences(of: "{SERIAL}", with: serialFormatted)
            .replacingOccurrences(of: "{EXCH}", with: (resolvedExch.isEmpty ? exch : resolvedExch).uppercased())
            .replacingOccurrences(of: "{HISEXCH}", with: (resolvedExch.isEmpty ? exch : resolvedExch).uppercased())
            .replacingOccurrences(of: "{HISZONE}", with: resolvedZone)
            .replacingOccurrences(of: "{ZONE}", with: resolvedZone)
            .replacingOccurrences(of: "{HISSTATE}", with: resolvedState.uppercased())
            .replacingOccurrences(of: "{STATE}", with: resolvedState.uppercased())
            .replacingOccurrences(of: "{HISSECT}", with: resolvedSect.uppercased())
            .replacingOccurrences(of: "{HISGRID}", with: resolvedGrid.uppercased())
            .replacingOccurrences(of: "{BAND}", with: band.uppercased())
            .replacingOccurrences(of: "{FREQ}", with: freq)

        if useCutNumbers {
            result = applyCutNumbers(result)
        }

        return result
    }

    public func expandTemplate(
        _ template: String,
        myCall: String = "",
        call: String = "",
        rst: String = "599",
        name: String = "",
        qth: String = "",
        serial: Int = 1,
        exch: String = "",
        band: String = "",
        freq: String = ""
    ) -> String {
        return expandMacro(
            template,
            myCall: myCall,
            call: call,
            rst: rst,
            name: name,
            qth: qth,
            serial: serial,
            exch: exch,
            band: band,
            freq: freq
        )
    }

    // MARK: - Send Transmission

    public func send(
        text: String,
        myCall: String = "",
        call: String = "",
        rst: String = "599",
        name: String = "",
        qth: String = "",
        serial: Int = 1,
        exch: String = "",
        band: String = "",
        freq: String = ""
    ) {
        let expanded = expandMacro(
            text,
            myCall: myCall,
            call: call,
            rst: rst,
            name: name,
            qth: qth,
            serial: serial,
            exch: exch,
            band: band,
            freq: freq
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !expanded.isEmpty else { return }

        stopTransmitOnly()
        self.isTransmitting = true
        self.activeBufferText = expanded
        self.currentlyTransmittingChar = ""

        if !sentHistory.contains(expanded) {
            sentHistory.insert(expanded, at: 0)
            if sentHistory.count > 30 {
                sentHistory.removeLast()
            }
        }

        transmitTask = Task { [weak self] in
            guard let self else { return }

            // 1. Hardware / Network backend execution
            switch self.transmissionMode {
            case .winkeyer:
                WinKeyerDriver.shared.setSpeed(self.wpm)
                WinKeyerDriver.shared.sendMorseText(expanded)
                // Sidetone and progress handled by WinKeyer echo callbacks
                return
            case .serialDTR_RTS:
                SerialKeyerDriver.shared.sendMorse(
                    text: expanded,
                    wpm: self.wpm,
                    onCharacter: { [weak self] ch in self?.currentlyTransmittingChar = ch },
                    onComplete: { [weak self] in
                        self?.isTransmitting = false
                        self?.activeBufferText = ""
                        self?.currentlyTransmittingChar = ""
                    }
                )
                // Progress driven by SerialKeyerDriver callbacks; also play sidetone
                if self.sidetoneEnabled {
                    await self.playMorseSidetone(text: expanded)
                } else {
                    await self.simulateTransmitProgress(text: expanded)
                }
            case .catMorse:
                await self.sendViaCAT(text: expanded)
                if self.sidetoneEnabled {
                    await self.playMorseSidetone(text: expanded)
                } else {
                    await self.simulateTransmitProgress(text: expanded)
                }
            case .icomUSB:
                let icom = IcomUSBRadioDriver.shared
                if icom.isConnected {
                    icom.setKeyerSpeed(self.wpm)
                    icom.sendMorse(expanded)
                }
                if self.sidetoneEnabled {
                    await self.playMorseSidetone(text: expanded)
                } else {
                    await self.simulateTransmitProgress(text: expanded)
                }
            case .lab599TX500:
                let tx500 = Lab599TX500Driver.shared
                if tx500.isConnected {
                    tx500.sendMorse(expanded, wpm: self.wpm)
                }
                if self.sidetoneEnabled {
                    await self.playMorseSidetone(text: expanded)
                } else {
                    await self.simulateTransmitProgress(text: expanded)
                }
            case .fx4cr:
                let fx4cr = FX4CRDriver.shared
                if fx4cr.isConnected {
                    fx4cr.sendMorse(expanded, wpm: self.wpm)
                }
                if self.sidetoneEnabled {
                    await self.playMorseSidetone(text: expanded)
                } else {
                    await self.simulateTransmitProgress(text: expanded)
                }
            case .xiegu6100:
                let xiegu = Xiegu6100Driver.shared
                if xiegu.isConnected {
                    xiegu.setKeyerSpeed(self.wpm)
                    xiegu.sendMorse(expanded)
                }
                if self.sidetoneEnabled {
                    await self.playMorseSidetone(text: expanded)
                } else {
                    await self.simulateTransmitProgress(text: expanded)
                }
            case .tci:
                TCIClient.shared.sendCW(text: expanded, wpm: self.wpm)
                await self.simulateTransmitProgress(text: expanded)
            case .cwdaemon:
                self.sendViaCWDaemon(text: expanded)
                if self.sidetoneEnabled {
                    await self.playMorseSidetone(text: expanded)
                } else {
                    await self.simulateTransmitProgress(text: expanded)
                }
            case .audioOnly:
                if self.sidetoneEnabled {
                    await self.playMorseSidetone(text: expanded)
                }
            }

            self.isTransmitting = false
            self.activeBufferText = ""
            self.currentlyTransmittingChar = ""
        }
    }

    private func stopTransmitOnly() {
        transmitTask?.cancel()
        transmitTask = nil
        isTransmitting = false
        activeBufferText = ""
        currentlyTransmittingChar = ""

        switch transmissionMode {
        case .winkeyer:
            WinKeyerDriver.shared.abort()
        case .serialDTR_RTS:
            SerialKeyerDriver.shared.abort()
        case .icomUSB:
            IcomUSBRadioDriver.shared.stopMorse()
        case .lab599TX500:
            Lab599TX500Driver.shared.stopMorse()
        case .fx4cr:
            FX4CRDriver.shared.stopMorse()
        case .xiegu6100:
            Xiegu6100Driver.shared.stopMorse()
        case .tci:
            TCIClient.shared.stopCW()
        case .cwdaemon:
            sendCWDaemonPacket(data: Data([0x1B]))
        case .catMorse:
            Task { [weak self] in
                guard let self else { return }
                if FX4CRDriver.shared.isConnected {
                    FX4CRDriver.shared.stopMorse()
                } else if Lab599TX500Driver.shared.isConnected {
                    Lab599TX500Driver.shared.stopMorse()
                } else if IcomUSBRadioDriver.shared.isConnected {
                    IcomUSBRadioDriver.shared.stopMorse()
                } else if Xiegu6100Driver.shared.isConnected {
                    Xiegu6100Driver.shared.stopMorse()
                } else if self.rigControlClientRef?.state.isConnected == true {
                    self.rigControlClientRef?.stopMorse()
                } else if FLRigClient.shared.isConnected {
                    try? await FLRigClient.shared.stopMorse()
                }
            }
        case .audioOnly:
            break
        }
    }

    public func stop() {
        stopAutoCQ()
        stopTransmitOnly()
    }

    // MARK: - Auto-CQ Repeater Loop

    public func toggleAutoCQ(
        template: String,
        myCall: String = "",
        call: String = "",
        rst: String = "599",
        name: String = "",
        qth: String = "",
        serial: Int = 1,
        exch: String = "",
        band: String = "",
        freq: String = ""
    ) {
        if isAutoCQActive {
            stopAutoCQ()
        } else {
            startAutoCQ(
                template: template,
                myCall: myCall,
                call: call,
                rst: rst,
                name: name,
                qth: qth,
                serial: serial,
                exch: exch,
                band: band,
                freq: freq
            )
        }
    }

    public func startAutoCQ(
        template: String,
        myCall: String = "",
        call: String = "",
        rst: String = "599",
        name: String = "",
        qth: String = "",
        serial: Int = 1,
        exch: String = "",
        band: String = "",
        freq: String = ""
    ) {
        stopAutoCQ()
        isAutoCQActive = true

        autoCQTask = Task { [weak self] in
            guard let self else { return }

            while self.isAutoCQActive && !Task.isCancelled {
                // Send the CQ macro
                self.send(
                    text: template,
                    myCall: myCall,
                    call: call,
                    rst: rst,
                    name: name,
                    qth: qth,
                    serial: serial,
                    exch: exch,
                    band: band,
                    freq: freq
                )

                // Wait for transmission to finish
                while self.isTransmitting && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }

                guard self.isAutoCQActive && !Task.isCancelled else { break }

                // Countdown pause interval
                for remaining in stride(from: self.autoCQIntervalSeconds, through: 1, by: -1) {
                    guard self.isAutoCQActive && !Task.isCancelled else { break }
                    self.autoCQCountdown = remaining
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                self.autoCQCountdown = 0
            }

            self.isAutoCQActive = false
            self.autoCQCountdown = 0
        }
    }

    public func stopAutoCQ() {
        isAutoCQActive = false
        autoCQCountdown = 0
        autoCQTask?.cancel()
        autoCQTask = nil
    }

    // MARK: - CAT Morse Sender

    private func sendViaCAT(text: String) async {
        // Priority 0: Direct FX-4CR Kenwood CAT KY Morse
        if FX4CRDriver.shared.isConnected {
            FX4CRDriver.shared.sendMorse(text, wpm: wpm)
        // Priority 1: Direct Lab599 TX-500 Kenwood CAT KY Morse
        } else if Lab599TX500Driver.shared.isConnected {
            Lab599TX500Driver.shared.sendMorse(text, wpm: wpm)
        // Priority 2: Direct Icom USB CI-V CAT Command 17
        } else if IcomUSBRadioDriver.shared.isConnected {
            IcomUSBRadioDriver.shared.setKeyerSpeed(wpm)
            IcomUSBRadioDriver.shared.sendMorse(text)
        // Priority 2.5: Direct Xiegu X6100 CI-V CAT Command 17
        } else if Xiegu6100Driver.shared.isConnected {
            Xiegu6100Driver.shared.setKeyerSpeed(wpm)
            Xiegu6100Driver.shared.sendMorse(text)
        // Priority 3: Hamlib rigctld \send_morse
        } else if rigControlClientRef?.state.isConnected == true {
            rigControlClientRef?.setKeyerSpeed(wpm)
            rigControlClientRef?.sendMorse(text)
        // Priority 4: FLRig XML-RPC rig.send_morse
        } else if FLRigClient.shared.isConnected {
            try? await FLRigClient.shared.sendMorse(text)
        }
    }

    // MARK: - cwdaemon UDP Sender

    private func sendViaCWDaemon(text: String) {
        let speedCmd = Data("\u{1b}2\(wpm)".utf8)
        sendCWDaemonPacket(data: speedCmd)

        let msgData = Data(text.utf8)
        sendCWDaemonPacket(data: msgData)
    }

    private func sendCWDaemonPacket(data: Data) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(cwdaemonPort)) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(cwdaemonHost), port: port, using: .udp)
        connection.start(queue: .global())
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Morse Code Timing & Sidetone Synthesizer

    private func estimateDits(for text: String) -> Int {
        let wordCount = max(1, text.split(separator: " ").count)
        return wordCount * 50
    }

    private func simulateTransmitProgress(text: String) async {
        let ditDuration = 1.2 / Double(wpm)
        for char in text.uppercased() {
            guard !Task.isCancelled else { break }
            self.currentlyTransmittingChar = String(char)
            let ditCount = Self.morseAlphabet[char]?.count ?? 2
            let charDuration = ditDuration * Double(ditCount * 2 + 2)
            try? await Task.sleep(nanoseconds: UInt64(charDuration * 1_000_000_000))
        }
    }

    private func playMorseSidetone(text: String) async {
        let ditDuration = 1.2 / Double(wpm)
        let morseTable = Self.morseAlphabet

        for char in text.uppercased() {
            guard !Task.isCancelled else { break }
            self.currentlyTransmittingChar = String(char)

            if char == " " {
                try? await Task.sleep(nanoseconds: UInt64(ditDuration * 7 * 1_000_000_000))
                continue
            }

            guard let pattern = morseTable[char] else { continue }

            for symbol in pattern {
                guard !Task.isCancelled else { break }

                if symbol == "." {
                    playTone(duration: ditDuration)
                    try? await Task.sleep(nanoseconds: UInt64(ditDuration * 1_000_000_000))
                } else if symbol == "-" {
                    playTone(duration: ditDuration * 3)
                    try? await Task.sleep(nanoseconds: UInt64(ditDuration * 3 * 1_000_000_000))
                }

                // Inter-element space (1 dit)
                try? await Task.sleep(nanoseconds: UInt64(ditDuration * 1_000_000_000))
            }

            // Inter-character space (3 dits)
            try? await Task.sleep(nanoseconds: UInt64(ditDuration * 2 * 1_000_000_000))
        }
    }

    private func playTone(duration: TimeInterval) {
        guard let player = playerNode, let engine = audioEngine, engine.isRunning else { return }
        let format = player.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 48000.0
        let channels = Int(format.channelCount)
        guard channels > 0 else { return }

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let freq = sidetonePitchHz
        let amp = Float(sidetoneVolume) * 0.3
        let rampFrames = min(Int(sampleRate * 0.005), Int(frameCount) / 2) // 5ms soft cosine ramp

        var monoSamples = [Float](repeating: 0, count: Int(frameCount))
        for frame in 0..<Int(frameCount) {
            let pureSin = Float(sin(2.0 * .pi * freq * Double(frame) / sampleRate))
            var envelope: Float = 1.0
            if frame < rampFrames {
                envelope = 0.5 * (1.0 - cos(Float.pi * Float(frame) / Float(rampFrames)))
            } else if frame > Int(frameCount) - rampFrames {
                let endFrame = Int(frameCount) - frame
                envelope = 0.5 * (1.0 - cos(Float.pi * Float(endFrame) / Float(rampFrames)))
            }
            monoSamples[frame] = pureSin * amp * envelope
        }

        for ch in 0..<channels {
            if let chData = buffer.floatChannelData?[ch] {
                for i in 0..<Int(frameCount) {
                    chData[i] = monoSamples[i]
                }
            }
        }

        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    // MARK: - Macro Memory Persistence & Defaults

    public func updateMacro(bank: CWMemoryBank, id: Int, label: String, template: String) {
        var bankMacros = bankStorage[bank] ?? defaultMacros(for: bank)
        if let index = bankMacros.firstIndex(where: { $0.id == id }) {
            bankMacros[index].label = label
            bankMacros[index].template = template
        } else {
            bankMacros.append(CWMacro(id: id, label: label, template: template, bank: bank))
        }
        bankStorage[bank] = bankMacros
        saveMacros()
    }

    public func resetBankToDefaults(bank: CWMemoryBank) {
        bankStorage[bank] = defaultMacros(for: bank)
        saveMacros()
    }

    private func saveMacros() {
        if let encoded = try? JSONEncoder().encode(bankStorage) {
            UserDefaults.standard.set(encoded, forKey: "cwBankStorageV2")
        }
    }

    private func loadMacros() {
        if let data = UserDefaults.standard.data(forKey: "cwBankStorageV2"),
           let decoded = try? JSONDecoder().decode([CWMemoryBank: [CWMacro]].self, from: data) {
            self.bankStorage = decoded
        } else {
            // Seed all default banks
            for bank in CWMemoryBank.allCases {
                self.bankStorage[bank] = defaultMacros(for: bank)
            }
        }
    }

    public func defaultMacros(for bank: CWMemoryBank) -> [CWMacro] {
        switch bank {
        case .run:
            return [
                CWMacro(id: 1, label: "CQ TEST", template: "CQ TEST {MYCALL} {MYCALL} TEST", bank: .run),
                CWMacro(id: 2, label: "EXCH", template: "{CALL} 5NN {SERIAL}", bank: .run),
                CWMacro(id: 3, label: "TU NOW", template: "TU {MYCALL} TEST", bank: .run),
                CWMacro(id: 4, label: "MY CALL", template: "{MYCALL}", bank: .run),
                CWMacro(id: 5, label: "HIS CALL", template: "{CALL}", bank: .run),
                CWMacro(id: 6, label: "CORRECT", template: "{CALL} 5NN {SERIAL}", bank: .run),
                CWMacro(id: 7, label: "REPEAT EXCH", template: "EXCH {SERIAL}", bank: .run),
                CWMacro(id: 8, label: "AGN?", template: "AGN?", bank: .run),
                CWMacro(id: 9, label: "QRZ?", template: "QRZ? {MYCALL}", bank: .run),
                CWMacro(id: 10, label: "RST ONLY", template: "5NN", bank: .run),
                CWMacro(id: 11, label: "CHECK/ZONE", template: "{EXCH}", bank: .run),
                CWMacro(id: 12, label: "73 TU", template: "73 TU {MYCALL}", bank: .run)
            ]
        case .searchAndPounce:
            return [
                CWMacro(id: 1, label: "MY CALL", template: "{MYCALL}", bank: .searchAndPounce),
                CWMacro(id: 2, label: "SEND EXCH", template: "5NN {SERIAL}", bank: .searchAndPounce),
                CWMacro(id: 3, label: "TU", template: "TU", bank: .searchAndPounce),
                CWMacro(id: 4, label: "HIS CALL", template: "{CALL}", bank: .searchAndPounce),
                CWMacro(id: 5, label: "MY CALL X2", template: "{MYCALL} {MYCALL}", bank: .searchAndPounce),
                CWMacro(id: 6, label: "REPEAT EXCH", template: "EXCH {SERIAL} {SERIAL}", bank: .searchAndPounce),
                CWMacro(id: 7, label: "QTH / STATE", template: "QTH {QTH}", bank: .searchAndPounce),
                CWMacro(id: 8, label: "NAME", template: "NAME {NAME}", bank: .searchAndPounce),
                CWMacro(id: 9, label: "?", template: "?", bank: .searchAndPounce),
                CWMacro(id: 10, label: "RST", template: "5NN", bank: .searchAndPounce),
                CWMacro(id: 11, label: "CONFIRM", template: "CFM TU", bank: .searchAndPounce),
                CWMacro(id: 12, label: "73 SK", template: "73 GL EE", bank: .searchAndPounce)
            ]
        case .ragchew:
            return [
                CWMacro(id: 1, label: "CQ DX", template: "CQ CQ DX DE {MYCALL} {MYCALL} K", bank: .ragchew),
                CWMacro(id: 2, label: "5NN TU", template: "{CALL} UR 5NN 5NN TU", bank: .ragchew),
                CWMacro(id: 3, label: "MY CALL", template: "{MYCALL} DE {MYCALL} K", bank: .ragchew),
                CWMacro(id: 4, label: "HIS CALL", template: "{CALL} DE {MYCALL} PSE K", bank: .ragchew),
                CWMacro(id: 5, label: "NAME & QTH", template: "TNX FER CALL BT OP {NAME} ES QTH {QTH} BT HW CPY? {CALL} DE {MYCALL} K", bank: .ragchew),
                CWMacro(id: 6, label: "RIG & ANT", template: "RIG HR 100W ES DIPOLE BT HW? DE {MYCALL} K", bank: .ragchew),
                CWMacro(id: 7, label: "WEATHER", template: "WX HR SUNNY ES WARM BT {CALL} DE {MYCALL} K", bank: .ragchew),
                CWMacro(id: 8, label: "QSL VIA", template: "QSL VIA LOTW ES BURO BT {CALL} DE {MYCALL} K", bank: .ragchew),
                CWMacro(id: 9, label: "PSE AGN", template: "PSE AGN? DE {MYCALL} K", bank: .ragchew),
                CWMacro(id: 10, label: "FB OM", template: "FB OM TNX FER FB QSO BT 73", bank: .ragchew),
                CWMacro(id: 11, label: "QRU", template: "QRU NIL HR BT 73 GL", bank: .ragchew),
                CWMacro(id: 12, label: "73 SK", template: "TNX FER QSO 73 ES CUAGN {CALL} DE {MYCALL} SK ..", bank: .ragchew)
            ]
        case .custom:
            return [
                CWMacro(id: 1, label: "F1: Custom CQ", template: "CQ CQ DE {MYCALL} {MYCALL} K", bank: .custom),
                CWMacro(id: 2, label: "F2: Custom Exch", template: "{CALL} 5NN {SERIAL}", bank: .custom),
                CWMacro(id: 3, label: "F3: Callsign", template: "{MYCALL}", bank: .custom),
                CWMacro(id: 4, label: "F4: Target Call", template: "{CALL}", bank: .custom),
                CWMacro(id: 5, label: "F5: Info", template: "OP {NAME} QTH {QTH}", bank: .custom),
                CWMacro(id: 6, label: "F6: Contest Serial", template: "NR {SERIAL}", bank: .custom),
                CWMacro(id: 7, label: "F7: QRZ?", template: "QRZ? DE {MYCALL}", bank: .custom),
                CWMacro(id: 8, label: "F8: 73", template: "73 TU EE", bank: .custom),
                CWMacro(id: 9, label: "F9: BK", template: "BK", bank: .custom),
                CWMacro(id: 10, label: "F10: CFM", template: "CFM TU", bank: .custom),
                CWMacro(id: 11, label: "F11: TEST", template: "TEST {MYCALL}", bank: .custom),
                CWMacro(id: 12, label: "F12: SK", template: "SK EE", bank: .custom)
            ]
        }
    }

    // MARK: - Morse Code Dictionary

    public static let morseAlphabet: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
        "F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
        "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---",
        "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
        "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--",
        "Z": "--..", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        "0": "-----", "/": "-..-.", "?": "..--..", "=": "-...-", ",": "--..--",
        ".": ".-.-.-", "!": "-.-.--", "-": "-....-", "@": ".--.-."
    ]
}
