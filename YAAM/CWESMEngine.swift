//
//  CWESMEngine.swift
//  YAAM
//
//  Contest Enter-Sends-Message (ESM) Automation Engine
//  Fully integrates the YAAM QuickLog logging workspace with the Morse Code Keyer (CWKeyerService).
//  Implements standard high-speed contesting state-machine logic for RUN and S&P modes:
//
//  • RUN MODE (Calling CQ / Working a Pileup):
//    1. Callsign empty       -> Press Enter: Sends CQ (F1) -> Focus stays on Callsign
//    2. Callsign entered     -> Press Enter: Sends Exchange (F2: {CALL} 5NN {SERIAL}) -> Focus advances to Exchange
//    3. Exchange entered     -> Press Enter: Sends TU (F3: TU {MYCALL} TEST) -> Logs QSO, clears draft, focus to Callsign
//    4. Callsign empty again -> Press Enter: Sends CQ (F1) again!
//
//  • S&P MODE (Search & Pounce / Answering CQs):
//    1. Callsign empty       -> Press Enter: Prompts for Callsign
//    2. Callsign entered     -> Press Enter: Sends My Callsign (F1: {MYCALL}) -> Focus advances to Exchange
//    3. Exchange entered     -> Press Enter: Sends My Exchange (F2: 5NN {SERIAL}) -> Logs QSO, clears draft, focus to Callsign
//
//  • Live Real-Time Prediction & Dynamic Button Labeling:
//    Always informs the operator of the exact Morse string and action triggered by the next Enter keypress.
//

import Combine
import Foundation
import SwiftUI

enum CWESMOperatingMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case run = "RUN (CQ Pileup)"
    case searchAndPounce = "S&P (Search & Pounce)"

    var id: String { rawValue }

    var shortCode: String {
        switch self {
        case .run: return "RUN"
        case .searchAndPounce: return "S&P"
        }
    }

    var iconName: String {
        switch self {
        case .run: return "flame.fill"
        case .searchAndPounce: return "binoculars.fill"
        }
    }
}

enum CWESMAction: Equatable, Sendable {
    case sendCQ(template: String)
    case sendExchange(callsign: String, template: String)
    case sendTUAndLog(template: String)
    case sendMyCall(template: String)
    case sendMyExchangeAndLog(template: String)
    case promptCallsign

    var buttonTitle: String {
        switch self {
        case .sendCQ: return "⚡ CQ (↵)"
        case .sendExchange: return "⚡ Exch (↵)"
        case .sendTUAndLog: return "⚡ TU & Log (↵)"
        case .sendMyCall: return "⚡ My Call (↵)"
        case .sendMyExchangeAndLog: return "⚡ Exch & Log (↵)"
        case .promptCallsign: return "⚡ Enter Call"
        }
    }

    var actionDescription: String {
        switch self {
        case .sendCQ: return "Send CQ"
        case .sendExchange(let call, _): return "Send Exch to \(call)"
        case .sendTUAndLog: return "Send TU & Log QSO"
        case .sendMyCall: return "Send My Call"
        case .sendMyExchangeAndLog: return "Send Exch & Log QSO"
        case .promptCallsign: return "Waiting for Callsign"
        }
    }

    var badgeColor: Color {
        switch self {
        case .sendCQ: return .blue
        case .sendExchange: return .orange
        case .sendTUAndLog: return .green
        case .sendMyCall: return .blue
        case .sendMyExchangeAndLog: return .green
        case .promptCallsign: return .secondary
        }
    }
}

@MainActor
final class CWESMEngine: ObservableObject {
    static let shared = CWESMEngine()

    // MARK: - Published State
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "cwESMEnabled")
        }
    }

    @Published var operatingMode: CWESMOperatingMode {
        didSet {
            UserDefaults.standard.set(operatingMode.rawValue, forKey: "cwESMOperatingMode")
            // Sync with CW Keyer active memory bank
            switch operatingMode {
            case .run:
                CWKeyerService.shared.activeBank = .run
            case .searchAndPounce:
                CWKeyerService.shared.activeBank = .searchAndPounce
            }
        }
    }

    @Published var hasSentExchangeInCurrentQSO: Bool = false
    @Published var hasSentCallInCurrentQSO: Bool = false
    @Published var lastExecutedActionDescription: String = ""
    @Published var autoAdvanceFocus: Bool = true

    private var previousCallsign: String = ""

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "cwESMEnabled")
        if let storedModeStr = UserDefaults.standard.string(forKey: "cwESMOperatingMode"),
           let storedMode = CWESMOperatingMode(rawValue: storedModeStr) {
            self.operatingMode = storedMode
        } else {
            self.operatingMode = .run
        }
    }

    // MARK: - State Management & Reset

    func onCallsignChanged(_ newCallsign: String) {
        let clean = newCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean != previousCallsign {
            previousCallsign = clean
            // If operator alters the target callsign mid-QSO, re-arm the exchange
            hasSentExchangeInCurrentQSO = false
            hasSentCallInCurrentQSO = false
        }
    }

    func resetForNewQSO() {
        hasSentExchangeInCurrentQSO = false
        hasSentCallInCurrentQSO = false
        previousCallsign = ""
        lastExecutedActionDescription = ""
    }

    // MARK: - Action Determination (Pure Logic)

    func determineAction(
        callsign: String,
        receivedExchange: String,
        receivedSerial: String
    ) -> CWESMAction {
        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanExch = receivedExchange.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSerial = receivedSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasReceivedExchange = !cleanExch.isEmpty || !cleanSerial.isEmpty

        switch operatingMode {
        case .run:
            if cleanCall.isEmpty {
                return .sendCQ(template: currentRunCQTemplate)
            } else if !hasSentExchangeInCurrentQSO && !hasReceivedExchange {
                return .sendExchange(callsign: cleanCall, template: currentRunExchTemplate)
            } else {
                return .sendTUAndLog(template: currentRunTUTemplate)
            }

        case .searchAndPounce:
            if cleanCall.isEmpty {
                return .promptCallsign
            } else if !hasSentCallInCurrentQSO && !hasReceivedExchange {
                return .sendMyCall(template: currentSPCallTemplate)
            } else {
                return .sendMyExchangeAndLog(template: currentSPExchTemplate)
            }
        }
    }

    // MARK: - Macro Template Resolution from CWKeyer Memory Banks

    var currentRunCQTemplate: String {
        let bank = CWKeyerService.shared.bankStorage[.run] ?? CWKeyerService.shared.defaultMacros(for: .run)
        return bank.first(where: { $0.id == 1 })?.template ?? "CQ TEST {MYCALL} {MYCALL} TEST"
    }

    var currentRunExchTemplate: String {
        let bank = CWKeyerService.shared.bankStorage[.run] ?? CWKeyerService.shared.defaultMacros(for: .run)
        return bank.first(where: { $0.id == 2 })?.template ?? "{CALL} 5NN {SERIAL}"
    }

    var currentRunTUTemplate: String {
        let bank = CWKeyerService.shared.bankStorage[.run] ?? CWKeyerService.shared.defaultMacros(for: .run)
        return bank.first(where: { $0.id == 3 })?.template ?? "TU {MYCALL} TEST"
    }

    var currentSPCallTemplate: String {
        let bank = CWKeyerService.shared.bankStorage[.searchAndPounce] ?? CWKeyerService.shared.defaultMacros(for: .searchAndPounce)
        return bank.first(where: { $0.id == 1 })?.template ?? "{MYCALL}"
    }

    var currentSPExchTemplate: String {
        let bank = CWKeyerService.shared.bankStorage[.searchAndPounce] ?? CWKeyerService.shared.defaultMacros(for: .searchAndPounce)
        return bank.first(where: { $0.id == 2 })?.template ?? "5NN {SERIAL}"
    }

    var currentSPTUTemplate: String {
        let bank = CWKeyerService.shared.bankStorage[.searchAndPounce] ?? CWKeyerService.shared.defaultMacros(for: .searchAndPounce)
        return bank.first(where: { $0.id == 3 })?.template ?? "TU"
    }

    // MARK: - Live Preview Expansion

    func previewExpandedAction(
        action: CWESMAction,
        appState: AppState
    ) -> (previewText: String, morseText: String) {
        let keyer = CWKeyerService.shared
        let myCall = appState.activeStationProfile?.callsign.isEmpty == false
            ? (appState.activeStationProfile?.callsign ?? "EP2AES")
            : "EP2AES"
        let targetCall = appState.quickLogDraft.callsign
        let rst = appState.quickLogDraft.rstSent.isEmpty ? "599" : appState.quickLogDraft.rstSent
        let name = appState.quickLogDraft.name
        let qth = appState.quickLogDraft.qth
        let serial: Int = {
            if let s = Int(appState.quickLogDraft.sentSerial), s > 0 { return s }
            if let session = appState.currentContestSession, session.isActive {
                return ContestWorkspaceLogic.nextSerial(in: session, records: appState.qsoRecords)
            }
            return max(1, appState.qsoRecords.count + 1)
        }()
        let exch = appState.quickLogDraft.receivedExchange.isEmpty ? "001" : appState.quickLogDraft.receivedExchange
        let band = appState.quickLogDraft.band
        let freq = appState.quickLogDraft.frequencyMHz

        func expand(_ tmpl: String) -> String {
            keyer.expandMacro(
                tmpl,
                myCall: myCall,
                call: targetCall.isEmpty ? "W1AW" : targetCall,
                rst: rst,
                name: name,
                qth: qth,
                serial: serial,
                exch: exch,
                band: band,
                freq: freq
            )
        }

        switch action {
        case .sendCQ(let tmpl):
            let text = expand(tmpl)
            return ("Send CQ: \"\(text)\"", text)
        case .sendExchange(let call, let tmpl):
            let text = expand(tmpl)
            return ("Send Exch to \(call): \"\(text)\"", text)
        case .sendTUAndLog(let tmpl):
            let text = expand(tmpl)
            return ("Send TU & Log QSO: \"\(text)\"", text)
        case .sendMyCall(let tmpl):
            let text = expand(tmpl)
            return ("Send My Call: \"\(text)\"", text)
        case .sendMyExchangeAndLog(let tmpl):
            let text = expand(tmpl)
            return ("Send Exch & Log QSO: \"\(text)\"", text)
        case .promptCallsign:
            return ("Enter Callsign to start QSO", "")
        }
    }

    // MARK: - Action Execution

    func executeAction(
        action: CWESMAction,
        appState: AppState,
        focusExchange: () -> Void,
        focusCallsign: () -> Void,
        saveQSO: () -> Void
    ) {
        let keyer = CWKeyerService.shared
        let myCall = appState.activeStationProfile?.callsign.isEmpty == false
            ? (appState.activeStationProfile?.callsign ?? "EP2AES")
            : "EP2AES"
        let targetCall = appState.quickLogDraft.callsign
        let rst = appState.quickLogDraft.rstSent.isEmpty ? "599" : appState.quickLogDraft.rstSent
        let name = appState.quickLogDraft.name
        let qth = appState.quickLogDraft.qth
        let serial: Int = {
            if let s = Int(appState.quickLogDraft.sentSerial), s > 0 { return s }
            if let session = appState.currentContestSession, session.isActive {
                return ContestWorkspaceLogic.nextSerial(in: session, records: appState.qsoRecords)
            }
            return max(1, appState.qsoRecords.count + 1)
        }()
        let exch = appState.quickLogDraft.receivedExchange.isEmpty ? "001" : appState.quickLogDraft.receivedExchange
        let band = appState.quickLogDraft.band
        let freq = appState.quickLogDraft.frequencyMHz

        func transmit(_ template: String) {
            keyer.send(
                text: template,
                myCall: myCall,
                call: targetCall,
                rst: rst,
                name: name,
                qth: qth,
                serial: serial,
                exch: exch,
                band: band,
                freq: freq
            )
        }

        switch action {
        case .sendCQ(let template):
            transmit(template)
            lastExecutedActionDescription = "Sent CQ"
            focusCallsign()

        case .sendExchange(let call, let template):
            transmit(template)
            hasSentExchangeInCurrentQSO = true
            lastExecutedActionDescription = "Sent Exch to \(call)"
            if autoAdvanceFocus {
                focusExchange()
            }

        case .sendTUAndLog(let template):
            transmit(template)
            lastExecutedActionDescription = "Sent TU & Logged"
            hasSentExchangeInCurrentQSO = false
            hasSentCallInCurrentQSO = false
            saveQSO()
            focusCallsign()

        case .sendMyCall(let template):
            transmit(template)
            hasSentCallInCurrentQSO = true
            lastExecutedActionDescription = "Sent My Call"
            if autoAdvanceFocus {
                focusExchange()
            }

        case .sendMyExchangeAndLog(let template):
            transmit(template)
            lastExecutedActionDescription = "Sent Exch & Logged"
            hasSentExchangeInCurrentQSO = false
            hasSentCallInCurrentQSO = false
            saveQSO()
            focusCallsign()

        case .promptCallsign:
            appState.quickLogStatus = "Type Callsign first for S&P"
            focusCallsign()
        }
    }
}
