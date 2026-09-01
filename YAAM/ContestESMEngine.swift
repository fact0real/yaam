//
//  ContestESMEngine.swift
//  YAAM
//
//  Intelligent ESM (Enter Sends Message) State Machine for Contest & CW/Digital Operations
//  Eliminates RUMlogNG echoback stalls and keyboard ambiguities with a visual,
//  bidirectional state machine supporting RUN and Search & Pounce (S&P) workflows.
//

import Combine
import Foundation
import SwiftUI

public enum ContestOperatorRole: String, CaseIterable, Identifiable, Sendable {
    case run = "RUN (CQ Pileup)"
    case searchAndPounce = "S&P (Search & Pounce)"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .run: return "RUN"
        case .searchAndPounce: return "S&P"
        }
    }
}

public enum ESMState: String, CaseIterable, Sendable {
    case idleCQ = "Idle / Calling CQ"
    case callEntered = "Callsign Entered"
    case exchEntered = "Exchange Received"
    case callCorrected = "Callsign Corrected"
    case spCallStation = "S&P: Call Target"
    case spSendExch = "S&P: Send Exchange"
    case spLogReady = "S&P: Ready to Log"

    public var actionDescription: String {
        switch self {
        case .idleCQ: return "Send CQ (F1)"
        case .callEntered: return "Send His Call + Exchange (F2)"
        case .exchEntered: return "Log QSO & Send TU / Next CQ (F3)"
        case .callCorrected: return "Send Corrected Call + TU (F5)"
        case .spCallStation: return "Send My Callsign (F4)"
        case .spSendExch: return "Send My Exchange (F2)"
        case .spLogReady: return "Log QSO (↵)"
        }
    }

    public var actionColor: Color {
        switch self {
        case .idleCQ: return .blue
        case .callEntered: return .orange
        case .exchEntered: return .green
        case .callCorrected: return .purple
        case .spCallStation: return .blue
        case .spSendExch: return .orange
        case .spLogReady: return .green
        }
    }
}

@MainActor
public final class ContestESMEngine: ObservableObject {
    public static let shared = ContestESMEngine()

    // MARK: - Published State
    @Published public var isESMEnabled: Bool = true
    @Published public var role: ContestOperatorRole = .run
    @Published public var currentState: ESMState = .idleCQ
    @Published public var activeOutgoingText: String = ""
    @Published public var transmittedCharsCount: Int = 0
    @Published public var isTransmitting: Bool = false
    @Published public var statusMessage: String = "Ready"

    // Custom Macro Templates
    @Published public var f1CQ: String = "CQ TEST {MYCALL} {MYCALL} K"
    @Published public var f2Exch: String = "{CALL} 599 {EXCH}"
    @Published public var f3TU: String = "TU {MYCALL} CQ"
    @Published public var f4MyCall: String = "{MYCALL}"
    @Published public var f5HisCallTU: String = "{CALL} TU {MYCALL} CQ"
    @Published public var f6RepeatExch: String = "EXCH {EXCH}"
    @Published public var f7Question: String = "?"
    @Published public var f8AGN: String = "AGN?"

    private var initialCallRecorded: String = ""

    public init() {
        self.isESMEnabled = UserDefaults.standard.object(forKey: "contestESMEnabled") as? Bool ?? true
    }

    // MARK: - Evaluate State Automatically from Inputs

    public func evaluateState(callsign: String, rcvdExchange: String) {
        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanExch = rcvdExchange.trimmingCharacters(in: .whitespacesAndNewlines)

        if role == .run {
            if cleanCall.isEmpty {
                currentState = .idleCQ
                initialCallRecorded = ""
            } else if !initialCallRecorded.isEmpty && cleanCall != initialCallRecorded && !cleanExch.isEmpty {
                currentState = .callCorrected
            } else if cleanExch.isEmpty {
                currentState = .callEntered
                if initialCallRecorded.isEmpty { initialCallRecorded = cleanCall }
            } else {
                currentState = .exchEntered
            }
        } else {
            // S&P Mode
            if cleanCall.isEmpty {
                currentState = .spCallStation
            } else if cleanExch.isEmpty {
                currentState = .spCallStation
            } else {
                currentState = .spSendExch
            }
        }
    }

    // MARK: - Execute ESM Action on [Enter / Return]

    public func handleEnterPressed(
        callsign: inout String,
        sentExchange: String,
        rcvdExchange: inout String,
        onLogQSO: () -> Bool
    ) {
        guard isESMEnabled else {
            _ = onLogQSO()
            return
        }

        evaluateState(callsign: callsign, rcvdExchange: rcvdExchange)

        switch currentState {
        case .idleCQ:
            // Send F1 CQ
            executeMacro(f1CQ, call: callsign, sentExch: sentExchange, rcvdExch: rcvdExchange)
            statusMessage = "Calling CQ..."

        case .callEntered:
            // Send F2 His Call + Exchange
            executeMacro(f2Exch, call: callsign, sentExch: sentExchange, rcvdExch: rcvdExchange)
            statusMessage = "Sent exchange to \(callsign). Awaiting report..."

        case .exchEntered:
            // Send F3 TU + Next CQ and Log QSO!
            executeMacro(f3TU, call: callsign, sentExch: sentExchange, rcvdExch: rcvdExchange)
            let logged = onLogQSO()
            if logged {
                initialCallRecorded = ""
                currentState = .idleCQ
                statusMessage = "Logged \(callsign). Ready for next CQ."
            }

        case .callCorrected:
            // Send F5 Corrected Call + TU and Log QSO!
            executeMacro(f5HisCallTU, call: callsign, sentExch: sentExchange, rcvdExch: rcvdExchange)
            let logged = onLogQSO()
            if logged {
                initialCallRecorded = ""
                currentState = .idleCQ
                statusMessage = "Logged corrected call \(callsign)."
            }

        case .spCallStation:
            // S&P: Send F4 My Callsign
            executeMacro(f4MyCall, call: callsign, sentExch: sentExchange, rcvdExch: rcvdExchange)
            statusMessage = "Called \(callsign). Listening for response..."

        case .spSendExch:
            // S&P: Send F2 My Exchange
            let macro = "599 {EXCH}"
            executeMacro(macro, call: callsign, sentExch: sentExchange, rcvdExch: rcvdExchange)
            currentState = .spLogReady
            statusMessage = "Sent exchange to \(callsign)."

        case .spLogReady:
            // S&P: Log QSO
            let logged = onLogQSO()
            if logged {
                currentState = .spCallStation
                statusMessage = "Logged \(callsign) in S&P."
            }
        }
    }

    @Published public var myCallsign: String = "EP2AES"
    @Published public var nextSerial: Int = 1

    // MARK: - Macro Templating & Execution

    public func executeMacro(_ template: String, call: String, sentExch: String, rcvdExch: String) {
        let myCall = self.myCallsign.isEmpty ? "EP2AES" : self.myCallsign
        let serialStr = String(format: "%03d", nextSerial)

        let text = template
            .replacingOccurrences(of: "{MYCALL}", with: myCall)
            .replacingOccurrences(of: "{CALL}", with: call.uppercased())
            .replacingOccurrences(of: "{EXCH}", with: sentExch.isEmpty ? serialStr : sentExch)
            .replacingOccurrences(of: "{RCVD_EXCH}", with: rcvdExch)
            .replacingOccurrences(of: "{SERIAL}", with: serialStr)

        self.activeOutgoingText = text
        self.isTransmitting = true

        // Transmit via CW Keyer Service
        CWKeyerService.shared.send(text: text)
    }

    // MARK: - Abort / Wipe (Esc / Alt+W)

    public func abortAndWipe(callsign: inout String, rcvdExchange: inout String) {
        CWKeyerService.shared.stop()
        callsign = ""
        rcvdExchange = ""
        initialCallRecorded = ""
        currentState = role == .run ? .idleCQ : .spCallStation
        isTransmitting = false
        activeOutgoingText = ""
        statusMessage = "Aborted & Wiped"
    }

    public func toggleRole() {
        role = role == .run ? .searchAndPounce : .run
        currentState = role == .run ? .idleCQ : .spCallStation
    }
}
