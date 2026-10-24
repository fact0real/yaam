//
//  CWKeyerService.swift
//  YAAM
//
//  Native Morse Code Keyer & Macro Automation Engine
//  Supports Morse over CAT, WinKeyer, TCI DSP, cwdaemon network keying, and local macOS sine-wave sidetone audio.
//  Includes PARIS-calibrated timing, customizable F1-F12 memory banks (RUN, S&P, Ragchew, Custom),
//  dynamic tokens, cut-numbers (5NN), Auto-CQ repeat scheduler, and live transmit streams.
//

import AppKit
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
    /// Why the last send was refused (no callsign of the operator, or one that is not accepted; or the keying
    /// hardware of the selected mode is not connected), empty after a send that went out. It is cleared when the
    /// active station profile changes.
    @Published public var transmitRefusal: String = ""
    /// Independent of the next send/profile change; only the operator dismisses this notice.
    @Published public var operationNotice = ""
    @Published public var maximumMessageSeconds = 120 {
        didSet { let n = min(600, max(10, maximumMessageSeconds)); if n != maximumMessageSeconds { maximumMessageSeconds = n }; UserDefaults.standard.set(n, forKey: "cwMaximumMessageSeconds") }
    }
    @Published public var autoCQMaximumCalls = 20 {
        didSet { let n = min(100, max(1, autoCQMaximumCalls)); if n != autoCQMaximumCalls { autoCQMaximumCalls = n }; UserDefaults.standard.set(n, forKey: "cwAutoCQMaximumCalls") }
    }
    @Published public var autoCQMaximumMinutes = 10 {
        didSet { let n = min(30, max(1, autoCQMaximumMinutes)); if n != autoCQMaximumMinutes { autoCQMaximumMinutes = n }; UserDefaults.standard.set(n, forKey: "cwAutoCQMaximumMinutes") }
    }
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
    private var connectionWatchTask: Task<Void, Never>?
    private var autoCQTask: Task<Void, Never>?
    /// True only while the Auto-CQ loop hands its own CQ to send(): every other message is sent by hand and ends it.
    private var autoCQIsSending = false
    private var activeTransmissionMode: CWTransmissionMode?
    private var catStopTask: Task<Void, Never>?
    private var messageLimitTask: Task<Void, Never>?
    private var pendingAcceptance: ((Bool) -> Void)?
    private var autoCQLimitTask: Task<Void, Never>?
    private var autoCQGeneration = UUID()

    private func finishAcceptance(_ accepted: Bool) {
        let completion = pendingAcceptance
        pendingAcceptance = nil
        completion?(accepted)
    }
    private var isShuttingDown = false
    // Use the shared connection before any Operator Desk view has appeared. Tests may still inject a client.
    weak var rigControlClientRef: RigControlClient? = RigControlClient.shared

    /// In CAT Morse mode, the destination that took the last text (set by sendViaCAT), so that STOP reaches it even
    /// if the connection states have changed since. Nil until a text has gone to one.
    private enum CATMorsePath { case fx4cr, tx500, icomUSB, xiegu6100, rigctl, flrig }
    private var catMorsePath: CATMorsePath?
    private var pendingCATTransport: AnyObject?
    /// Stops the keyer when the app quits (see init).
    private var terminationObserver: NSObjectProtocol?
    private var connectionLossObserver: NSObjectProtocol?

    public init() {
        self.wpm = MorseTiming.clampedWPM(UserDefaults.standard.object(forKey: "cwKeyerWPM") as? Int ?? 24)
        self.maximumMessageSeconds = min(600, max(10, UserDefaults.standard.object(forKey: "cwMaximumMessageSeconds") as? Int ?? 120))
        self.autoCQMaximumCalls = min(100, max(1, UserDefaults.standard.object(forKey: "cwAutoCQMaximumCalls") as? Int ?? 20))
        self.autoCQMaximumMinutes = min(30, max(1, UserDefaults.standard.object(forKey: "cwAutoCQMaximumMinutes") as? Int ?? 10))
        self.sidetonePitchHz = UserDefaults.standard.double(forKey: "cwSidetonePitch") > 0 ? UserDefaults.standard.double(forKey: "cwSidetonePitch") : 650.0
        self.useCutNumbers = UserDefaults.standard.object(forKey: "cwUseCutNumbers") as? Bool ?? true
        let storedInterval = UserDefaults.standard.integer(forKey: "cwAutoCQInterval")
        self.autoCQIntervalSeconds = storedInterval >= 2 ? storedInterval : 4

        loadMacros()
        setupAudioEngine()
        setupWinKeyerBindings()

        // Quitting the app stops what is being sent, as STOP does; otherwise the radio or the WinKeyer would finish
        // the text it holds after the app has gone. queue nil: the block runs at once, on the thread that posts the
        // notification (the main thread, at quit), before the app exits.
        connectionLossObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("YAAMRadioConnectionLost"), object: nil, queue: nil
        ) { [weak self] notice in
            MainActor.assumeIsolated { self?.stopForConnectionLoss(notice.object as AnyObject?) }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private func setupWinKeyerBindings() {
        WinKeyerDriver.shared.onCharacterEchoed = { [weak self] char in
            Task { @MainActor [weak self] in
                guard let self = self, self.activeTransmissionMode == .winkeyer else { return }
                self.currentlyTransmittingChar = char
            }
        }
        WinKeyerDriver.shared.onTransmissionComplete = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.activeTransmissionMode == .winkeyer, !WinKeyerDriver.shared.isTransmitting else { return }
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
            // The same destinations, in the same order, as sendViaCAT.
            if FX4CRDriver.shared.isConnected {
                let d = FX4CRDriver.shared
                return (true, "FX-4CR CAT (\(d.connectionType.rawValue))", "\(d.formattedFrequency) \(d.mode)")
            } else if Lab599TX500Driver.shared.isConnected {
                let d = Lab599TX500Driver.shared
                return (true, "TX-500 CAT", "\(d.formattedFrequency) \(d.mode)")
            } else if IcomUSBRadioDriver.shared.isConnected {
                let d = IcomUSBRadioDriver.shared
                return (true, "\(d.model.rawValue) CI-V", "\(d.formattedFrequency) \(d.mode)")
            } else if Xiegu6100Driver.shared.isConnected {
                let d = Xiegu6100Driver.shared
                return (true, "Xiegu X6100 CI-V", "\(d.formattedFrequency) \(d.mode)")
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
        wpm = MorseTiming.clampedWPM(wpm.addingReportingOverflow(delta).overflow ? 60 : wpm + delta)
        UserDefaults.standard.set(wpm, forKey: "cwKeyerWPM")
    }

    public func decreaseWPM(_ delta: Int = 1) {
        wpm = MorseTiming.clampedWPM(wpm.subtractingReportingOverflow(delta).overflow ? 5 : wpm - delta)
        UserDefaults.standard.set(wpm, forKey: "cwKeyerWPM")
    }

    public func setWPM(_ newWpm: Int) {
        wpm = MorseTiming.clampedWPM(newWpm)
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

    /// Why a send under this callsign would be refused, or nil when it may go. Every way into the keyer
    /// (macro buttons, live text, Auto-CQ, the Enter key, the decoder's reply) asks this. A send is refused without
    /// the operator's callsign, and when the keying hardware of the selected mode is not connected: nothing would
    /// be keyed, while the screen showed ON AIR and the sidetone played. Audio Sidetone Only plays the Morse on this
    /// Mac and keys no radio, so it needs neither.
    public func refusalReason(myCall: String) -> String? {
        if transmissionMode == .audioOnly { return nil }
        if let issue = TransmitIdentity.callsignRefusal(myCall) { return issue }
        return keyerOfflineRefusal
    }

    /// The refusal when the keying hardware of the selected mode is not connected (as the status pill shows it),
    /// or nil when it is.
    private var keyerOfflineRefusal: String? {
        let status = hardwareStatusSummary
        if status.isConnected { return nil }
        return "Nothing sent: \(status.title) (\(status.detail)). Connect the CW keying hardware, or choose Audio Sidetone Only."
    }

    /// The text as it can go out in Morse: a letter with an accent becomes the plain letter (É→E, Ñ→N, Ç→C, Ü→U).
    /// `unsendable` lists, once each, the characters still outside ASCII (Ø, ß, Æ, typographic dashes, emoji…),
    /// which the radios cannot take: the TX-500 and the FX-4CR drop a whole KY command that holds one, and the
    /// WinKeyer gets bytes outside its range. An invisible one is named by its code (U+00A0). ASCII is left as is.
    nonisolated static func morseText(_ text: String) -> (text: String, unsendable: String) {
        MorseTiming.normalizedText(text)
    }

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
        freq: String = "",
        onAccepted: ((Bool) -> Void)? = nil
    ) {
        guard !isShuttingDown else { onAccepted?(false); return }
        let typed = expandMacro(
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

        guard !typed.isEmpty else { onAccepted?(false); return }
        guard typed.utf8.count <= MorseTiming.maximumTextLength else {
            transmitRefusal = "Nothing sent: CW messages are limited to \(MorseTiming.maximumTextLength) bytes."
            onAccepted?(false)
            return
        }

        // Nothing is keyed unless the operator's own callsign is set; checked before an earlier send is stopped.
        if let issue = refusalReason(myCall: myCall) {
            transmitRefusal = issue
            onAccepted?(false)
            return
        }
        // Accents are folded. A text with a character that has no Morse is refused here: nothing is stopped or sent.
        let (expanded, unsendable) = Self.morseText(typed)
        if !unsendable.isEmpty {
            transmitRefusal = "No Morse for \(unsendable): change the text before transmitting."
            onAccepted?(false)
            return
        }
        var speed = MorseTiming.clampedWPM(wpm)
        if transmissionMode == .icomUSB || (transmissionMode == .catMorse && !FX4CRDriver.shared.isConnected && !Lab599TX500Driver.shared.isConnected && IcomUSBRadioDriver.shared.isConnected) { speed = min(45, max(6, speed)) }
        if transmissionMode == .xiegu6100 || (transmissionMode == .catMorse && !FX4CRDriver.shared.isConnected && !Lab599TX500Driver.shared.isConnected && !IcomUSBRadioDriver.shared.isConnected && Xiegu6100Driver.shared.isConnected) { speed = min(50, speed) }
        let duration = MorseTiming.duration(of: expanded, wpm: speed)
        guard duration <= Double(maximumMessageSeconds) else {
            transmitRefusal = "Nothing sent: this CW message needs \(Int(duration.rounded(.up))) s at \(speed) WPM; the limit is \(maximumMessageSeconds) s. Shorten it or adjust CW limits."
            onAccepted?(false)
            return
        }
        // A message sent by hand (a macro, typed text, the contest keys) is the operator's answer: Auto-CQ ends, so
        // that no CQ follows it over the other station. A refused send above leaves Auto-CQ running.
        if isAutoCQActive && !autoCQIsSending {
            stopAutoCQ()
        }
        transmitRefusal = ""

        stopTransmitOnly()
        pendingAcceptance = onAccepted
        wpm = speed
        let selectedMode = transmissionMode
        activeTransmissionMode = selectedMode
        pendingCATTransport = selectedMode == .catMorse ? preferredCATTransport : nil
        self.isTransmitting = true
        self.activeBufferText = expanded
        self.currentlyTransmittingChar = ""

        if !sentHistory.contains(expanded) {
            sentHistory.insert(expanded, at: 0)
            if sentHistory.count > 30 {
                sentHistory.removeLast()
            }
        }

        let messageLimit = maximumMessageSeconds
        messageLimitTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(messageLimit)) } catch { return }
            guard let self, self.isTransmitting, !Task.isCancelled else { return }
            self.stop()
            self.operationNotice = "CW stopped at its \(messageLimit)-second limit at \(TXLimits.utc()). Receive was requested; verify receive on the radio before sending again."
        }
        transmitTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }

            if selectedMode != .catMorse, let lost = self.disconnectedTransmissionDevice {
                self.transmitRefusal = "Nothing sent: \(lost) disconnected before CW submission."
                self.finishAcceptance(false)
                self.isTransmitting = false
                self.activeBufferText = ""
                return
            }
            self.watchActiveConnection()
            // 1. Hardware / Network backend execution
            switch selectedMode {
            case .winkeyer:
                WinKeyerDriver.shared.setSpeed(self.wpm)
                WinKeyerDriver.shared.sendMorseText(expanded)
                self.finishAcceptance(true)
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
                self.finishAcceptance(true)
                // Progress driven by SerialKeyerDriver callbacks; also play sidetone
                if self.sidetoneEnabled {
                    await self.playMorseSidetone(text: expanded)
                } else {
                    await self.simulateTransmitProgress(text: expanded)
                }
            case .catMorse:
                // When no destination took the text (flrig refused it or did not answer), nothing is played: the
                // screen goes idle at once and the refusal says why.
                let accepted = await self.sendViaCAT(text: expanded)
                guard !Task.isCancelled else { return }
                self.finishAcceptance(accepted)
                if accepted {
                    if self.sidetoneEnabled {
                        await self.playMorseSidetone(text: expanded)
                    } else {
                        await self.simulateTransmitProgress(text: expanded)
                    }
                } else if !Task.isCancelled && self.isAutoCQActive {
                    // An Auto-CQ CQ that no destination took ends Auto-CQ, as a CQ refused before it is sent does.
                    // Its refusal is set here, after Auto-CQ has looked for one, so Auto-CQ would ask again after
                    // every pause.
                    self.stopAutoCQ()
                }
            case .icomUSB:
                let icom = IcomUSBRadioDriver.shared
                if icom.isConnected {
                    icom.setKeyerSpeed(self.wpm)
                    icom.sendMorse(expanded)
                }
                self.finishAcceptance(true)
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
                self.finishAcceptance(true)
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
                self.finishAcceptance(true)
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
                self.finishAcceptance(true)
                if self.sidetoneEnabled {
                    await self.playMorseSidetone(text: expanded)
                } else {
                    await self.simulateTransmitProgress(text: expanded)
                }
            case .tci:
                TCIClient.shared.sendCW(text: expanded, wpm: self.wpm)
                self.finishAcceptance(true)
                await self.simulateTransmitProgress(text: expanded)
            case .cwdaemon:
                self.sendViaCWDaemon(text: expanded)
                self.finishAcceptance(true)
                if self.sidetoneEnabled {
                    await self.playMorseSidetone(text: expanded)
                } else {
                    await self.simulateTransmitProgress(text: expanded)
                }
            case .audioOnly:
                self.finishAcceptance(true)
                if self.sidetoneEnabled {
                    await self.playMorseSidetone(text: expanded)
                }
            }

            // Cancelled by STOP or by a newer send(): stopTransmitOnly() has already reset this, and a newer message
            // may own the screen now.
            guard !Task.isCancelled else { return }
            self.isTransmitting = false
            self.activeBufferText = ""
            self.currentlyTransmittingChar = ""
        }
    }

    /// Watch the destination that accepted this message, even if another radio becomes connected later.
    /// A transport loss ends local progress and Auto-CQ; STOP is still attempted on the original destination.
    private func watchActiveConnection() {
        connectionWatchTask?.cancel()
        connectionWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                guard let self, self.isTransmitting, !Task.isCancelled else { return }
                if let lost = self.disconnectedTransmissionDevice {
                    self.transmitRefusal = "\(lost) disconnected during CW at \(TXLimits.utc()). Local CW progress stopped; radio receive is unconfirmed. Other YAAM tools remain available. Release PTT locally and check the radio before sending again."
                    self.stop()
                    return
                }
            }
        }
    }

    private var preferredCATTransport: AnyObject? {
        if FX4CRDriver.shared.isConnected { return FX4CRDriver.shared }
        if Lab599TX500Driver.shared.isConnected { return Lab599TX500Driver.shared }
        if IcomUSBRadioDriver.shared.isConnected { return IcomUSBRadioDriver.shared }
        if Xiegu6100Driver.shared.isConnected { return Xiegu6100Driver.shared }
        if rigControlClientRef?.state.isConnected == true { return rigControlClientRef }
        if FLRigClient.shared.isConnected { return FLRigClient.shared }
        return nil
    }

    private var activeTransportObject: AnyObject? {
        switch activeTransmissionMode {
        case .icomUSB?: return IcomUSBRadioDriver.shared
        case .lab599TX500?: return Lab599TX500Driver.shared
        case .fx4cr?: return FX4CRDriver.shared
        case .xiegu6100?: return Xiegu6100Driver.shared
        case .winkeyer?: return WinKeyerDriver.shared
        case .serialDTR_RTS?: return SerialKeyerDriver.shared
        case .tci?: return TCIClient.shared
        case .catMorse?:
            if let pendingCATTransport { return pendingCATTransport }
            switch catMorsePath {
            case .icomUSB?: return IcomUSBRadioDriver.shared
            case .tx500?: return Lab599TX500Driver.shared
            case .fx4cr?: return FX4CRDriver.shared
            case .xiegu6100?: return Xiegu6100Driver.shared
            case .rigctl?: return rigControlClientRef
            case .flrig?: return FLRigClient.shared
            case nil: return nil
            }
        default: return nil
        }
    }

    private func stopForConnectionLoss(_ transport: AnyObject?) {
        guard isTransmitting || isAutoCQActive, let transport, let activeTransportObject,
              transport === activeTransportObject else { return }
        transmitRefusal = "CW stopped after its radio connection changed at \(TXLimits.utc()). Auto-CQ is off. Receive was requested; verify the original radio before sending again."
        operationNotice = transmitRefusal
        stop()
    }

    private var disconnectedTransmissionDevice: String? {
        func lost(_ connected: Bool, _ name: String) -> String? { connected ? nil : name }
        switch activeTransmissionMode {
        case .icomUSB?: return lost(IcomUSBRadioDriver.shared.isConnected, "Icom USB")
        case .lab599TX500?: return lost(Lab599TX500Driver.shared.isConnected, "TX-500")
        case .fx4cr?: return lost(FX4CRDriver.shared.isConnected, "FX-4CR")
        case .xiegu6100?: return lost(Xiegu6100Driver.shared.isConnected, "Xiegu X6100")
        case .winkeyer?: return lost(WinKeyerDriver.shared.isConnected, "WinKeyer")
        case .serialDTR_RTS?: return lost(SerialKeyerDriver.shared.isConnected, "Serial keyer")
        case .tci?: return lost(TCIClient.shared.isConnected, "TCI")
        case .catMorse?:
            switch catMorsePath {
            case .fx4cr?: return lost(FX4CRDriver.shared.isConnected, "FX-4CR")
            case .tx500?: return lost(Lab599TX500Driver.shared.isConnected, "TX-500")
            case .icomUSB?: return lost(IcomUSBRadioDriver.shared.isConnected, "Icom USB")
            case .xiegu6100?: return lost(Xiegu6100Driver.shared.isConnected, "Xiegu X6100")
            case .rigctl?: return lost(rigControlClientRef?.state.isConnected == true, "rigctld")
            case .flrig?: return lost(FLRigClient.shared.isConnected, "FLRig")
            case nil: return nil
            }
        case .audioOnly?, .cwdaemon?, nil: return nil
        }
    }

    private func stopTransmitOnly() {
        messageLimitTask?.cancel()
        messageLimitTask = nil
        pendingCATTransport = nil
        finishAcceptance(false)
        transmitTask?.cancel()
        transmitTask = nil
        connectionWatchTask?.cancel()
        connectionWatchTask = nil
        isTransmitting = false
        activeBufferText = ""
        currentlyTransmittingChar = ""

        switch activeTransmissionMode ?? transmissionMode {
        case .winkeyer:
            // This clears the WinKeyer before a new message (or on STOP), and the state above is already reset. A
            // reported end would arrive after the new message has started and mark it as ended while it is sent.
            WinKeyerDriver.shared.abort(reportEnd: false)
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
            sendCWDaemonPacket(data: Data([0x1B, 0x34]))
        case .catMorse:
            stopCATMorse()
        case .audioOnly:
            break
        }
    }

    /// STOP in CAT Morse mode goes to the destination that took the last text, whatever its connection state says
    /// now; when no text has gone to one, to the first connected destination in sendViaCAT's order. It is written
    /// at once, except flrig's stop, which is asynchronous.
    private func stopCATMorse() {
        switch catMorsePath {
        case .fx4cr?:
            FX4CRDriver.shared.stopMorse()
        case .tx500?:
            Lab599TX500Driver.shared.stopMorse()
        case .icomUSB?:
            IcomUSBRadioDriver.shared.stopMorse()
        case .xiegu6100?:
            Xiegu6100Driver.shared.stopMorse()
        case .rigctl?:
            rigControlClientRef?.stopMorse()
        case .flrig?:
            queueFLRigStop()
        case nil:
            if FX4CRDriver.shared.isConnected {
                FX4CRDriver.shared.stopMorse()
            } else if Lab599TX500Driver.shared.isConnected {
                Lab599TX500Driver.shared.stopMorse()
            } else if IcomUSBRadioDriver.shared.isConnected {
                IcomUSBRadioDriver.shared.stopMorse()
            } else if Xiegu6100Driver.shared.isConnected {
                Xiegu6100Driver.shared.stopMorse()
            } else if rigControlClientRef?.state.isConnected == true {
                rigControlClientRef?.stopMorse()
            } else if FLRigClient.shared.isConnected {
                queueFLRigStop()
            }
        }
    }

    public func stop() {
        stopAutoCQ()
        stopTransmitOnly()
    }

    private func queueFLRigStop() {
        let previous = catStopTask
        catStopTask = Task {
            await previous?.value
            do { try await FLRigClient.shared.stopMorse() }
            catch {
                self.operationNotice = "flrig: CW stop was not confirmed at \(TXLimits.utc()): \(error.localizedDescription). Queued CW may still be keyed. Receiving and other YAAM tools remain available. Stop CW in flrig or on the radio and verify receive."
            }
        }
    }

    func beginTermination() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        stop()
    }

    func prepareForTermination() async {
        beginTermination()
        await catStopTask?.value
        // Leave time for already-enqueued network STOP writes before the process exits.
        try? await Task.sleep(for: .milliseconds(300))
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
        if let issue = refusalReason(myCall: myCall) {
            transmitRefusal = issue
            return
        }
        transmitRefusal = ""
        stopAutoCQ()
        isAutoCQActive = true
        autoCQGeneration = UUID()
        let limitGeneration = autoCQGeneration
        let minutes = autoCQMaximumMinutes
        autoCQLimitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled, let self, self.isAutoCQActive, self.autoCQGeneration == limitGeneration else { return }
            self.stop()
            self.operationNotice = "CW Auto-CQ stopped after its \(minutes)-minute limit at \(TXLimits.utc()). Receiving and logging remain available. Start Auto-CQ again to resume."
        }

        autoCQTask = Task { [weak self] in
            guard let self else { return }

            var calls = 0
            while self.isAutoCQActive && !Task.isCancelled {
                guard calls < self.autoCQMaximumCalls else {
                    self.operationNotice = "CW Auto-CQ stopped after \(calls) calls at \(TXLimits.utc()). Receiving and logging remain available. Start Auto-CQ again to resume."
                    break
                }
                calls += 1
                // Send the CQ macro
                self.autoCQIsSending = true
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
                self.autoCQIsSending = false
                // A CQ that is refused (the keying hardware went away) ends Auto-CQ; the refusal is shown.
                guard self.transmitRefusal.isEmpty else { break }

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

                // A message still going out is not cut by the next CQ, whose send() aborts whatever is being sent.
                // A message sent by hand ends Auto-CQ (see send()), so nothing waits here today: kept as a guard.
                while self.isTransmitting && self.isAutoCQActive && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }

            guard !Task.isCancelled else { return }
            self.isAutoCQActive = false
            self.autoCQCountdown = 0
        }
    }

    public func stopAutoCQ() {
        autoCQGeneration = UUID()
        autoCQLimitTask?.cancel()
        autoCQLimitTask = nil
        isAutoCQActive = false
        autoCQCountdown = 0
        autoCQTask?.cancel()
        autoCQTask = nil
    }

    // MARK: - CAT Morse Sender

    /// Hands the text to the first connected destination. Returns false when none took it: flrig refused it or did
    /// not answer (its error is put in transmitRefusal), or nothing is connected any more. The other destinations
    /// give no answer and count as having taken it.
    private func sendViaCAT(text: String) async -> Bool {
        await catStopTask?.value
        guard !Task.isCancelled else { return false }
        pendingCATTransport = nil
        // Priority 0: Direct FX-4CR Kenwood CAT KY Morse
        if FX4CRDriver.shared.isConnected {
            catMorsePath = .fx4cr
            FX4CRDriver.shared.sendMorse(text, wpm: wpm)
        // Priority 1: Direct Lab599 TX-500 Kenwood CAT KY Morse
        } else if Lab599TX500Driver.shared.isConnected {
            catMorsePath = .tx500
            Lab599TX500Driver.shared.sendMorse(text, wpm: wpm)
        // Priority 2: Direct Icom USB CI-V CAT Command 17
        } else if IcomUSBRadioDriver.shared.isConnected {
            catMorsePath = .icomUSB
            IcomUSBRadioDriver.shared.setKeyerSpeed(wpm)
            IcomUSBRadioDriver.shared.sendMorse(text)
        // Priority 2.5: Direct Xiegu X6100 CI-V CAT Command 17
        } else if Xiegu6100Driver.shared.isConnected {
            catMorsePath = .xiegu6100
            Xiegu6100Driver.shared.setKeyerSpeed(wpm)
            Xiegu6100Driver.shared.sendMorse(text)
        // Priority 3: Hamlib rigctld \send_morse
        } else if rigControlClientRef?.state.isConnected == true {
            catMorsePath = .rigctl
            rigControlClientRef?.setKeyerSpeed(wpm)
            rigControlClientRef?.sendMorse(text)
        // Priority 4: FLRig XML-RPC rig.cwio_text (flrig's own keyer; flrig has no rig.send_morse)
        } else if FLRigClient.shared.isConnected {
            catMorsePath = .flrig
            do {
                try await FLRigClient.shared.sendMorse(text, wpm: wpm)
            } catch {
                // Not after a STOP or a newer send: they own the screen now, and their own stop has gone to flrig.
                if !Task.isCancelled {
                    transmitRefusal = error.localizedDescription
                    // flrig may still take a text it did not answer for in time: it is stopped too, so that nothing
                    // goes out while the screen says the text was not sent.
                    queueFLRigStop()
                }
                return false
            }
        } else {
            catMorsePath = nil
            if !Task.isCancelled { transmitRefusal = keyerOfflineRefusal ?? "" }
            return false
        }
        return true
    }

    // MARK: - cwdaemon UDP Sender

    private func sendViaCWDaemon(text: String) {
        let speedCmd = Data("\u{1b}2\(wpm)".utf8)
        sendCWDaemonPacket(data: speedCmd)

        let msgData = Data(text.utf8)
        sendCWDaemonPacket(data: msgData)
    }

    private func sendCWDaemonPacket(data: Data) {
        guard (1...65_535).contains(cwdaemonPort),
              let port = NWEndpoint.Port(rawValue: UInt16(cwdaemonPort)) else { return }
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

    /// The end-of-message clock when no sidetone is played (sidetone off, and always for TCI): the sidetone's own
    /// Morse timing, silent, so that the screen is not idle before the radio has finished.
    private func simulateTransmitProgress(text: String) async {
        await playMorseSidetone(text: text, sound: false)
    }

    /// After the last character the screen stays ON AIR this much longer: the radio starts keying a little after the
    /// command reaches it, and a TX-500 or FX-4CR message sent in pieces pauses between them.
    private static let messageTail: TimeInterval = 0.3

    private func playMorseSidetone(text: String, sound: Bool = true) async {
        let started = ContinuousClock.now
        let ditDuration = 1.2 / Double(wpm)
        let chunked = activeTransmissionMode == .lab599TX500 || activeTransmissionMode == .fx4cr
            || (activeTransmissionMode == .catMorse && (catMorsePath == .tx500 || catMorsePath == .fx4cr))
        let pieces = chunked ? MorseTiming.chunks(of: text, limit: 24) : [text]
        let plannedDuration = pieces.reduce(0) { $0 + MorseTiming.duration(of: $1, wpm: wpm) }
            + Double(max(0, pieces.count - 1)) * MorseTiming.handover(wpm: wpm) + Self.messageTail
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
                    if sound { playTone(duration: ditDuration) }
                    try? await Task.sleep(nanoseconds: UInt64(ditDuration * 1_000_000_000))
                } else if symbol == "-" {
                    if sound { playTone(duration: ditDuration * 3) }
                    try? await Task.sleep(nanoseconds: UInt64(ditDuration * 3 * 1_000_000_000))
                }

                // Inter-element space (1 dit)
                try? await Task.sleep(nanoseconds: UInt64(ditDuration * 1_000_000_000))
            }

            // Inter-character space (3 dits)
            try? await Task.sleep(nanoseconds: UInt64(ditDuration * 2 * 1_000_000_000))
        }
        let elapsed = started.duration(to: .now)
        let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let remaining = max(Self.messageTail, plannedDuration - elapsedSeconds)
        try? await Task.sleep(for: .seconds(remaining))
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
