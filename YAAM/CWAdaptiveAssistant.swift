//
//  CWAdaptiveAssistant.swift
//  YAAM
//
//  Intelligent Adaptive Co-Pilot for CW Morse Communications
//  Analyzes decoded Morse streams to extract calling station, intent, exchange reports,
//  and QTH/name metadata. Automatically suggests context-aware replies, provides 1-click
//  speed synchronization, and integrates with QuickLog.
//

import Combine
import Foundation
import SwiftUI

public enum CWQSOIntent: String, Sendable {
    case callingCQ = "Station Calling CQ"
    case contestExchange = "Contest Report Received"
    case ragchewInfo = "Operator Info / QTH Received"
    case signOff = "Final Sign-off / 73"
    case general = "Monitoring Traffic"

    public var iconName: String {
        switch self {
        case .callingCQ: return "antenna.radiowaves.left.and.right"
        case .contestExchange: return "number.square.fill"
        case .ragchewInfo: return "person.crop.circle.badge.checkmark"
        case .signOff: return "hand.wave.fill"
        case .general: return "waveform"
        }
    }
}

@MainActor
public final class CWAdaptiveAssistant: ObservableObject {
    public static let shared = CWAdaptiveAssistant()

    @Published public var detectedCallsign: String = ""
    @Published public var detectedRST: String = ""
    @Published public var detectedExchange: String = ""
    @Published public var detectedName: String = ""
    @Published public var detectedQTH: String = ""
    @Published public var detectedIntent: CWQSOIntent = .general
    @Published public var intentDescription: String = "Listening on frequency..."
    @Published public var suggestedReply: String = ""
    @Published public var hasActionableSuggestion: Bool = false

    private init() {}

    // MARK: - Stream Analysis

    public func analyzeDecodedStream(_ fullText: String) {
        let clean = fullText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let words = clean.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !words.isEmpty else { return }

        // Look at the last 15 words for active context
        let recentWords = Array(words.suffix(15))
        let recentText = recentWords.joined(separator: " ")

        // 1. Detect CQ: "CQ [TEST/DX] [DE] <CALLSIGN>"
        if recentText.contains("CQ") {
            detectedIntent = .callingCQ
            if let call = extractCallsignAfterCQ(recentWords) {
                detectedCallsign = call
                intentDescription = "Station \(call) is calling CQ"
                suggestedReply = "{MYCALL}"
                hasActionableSuggestion = true
                return
            }
        }

        // 2. Detect Contest Report: "5NN" or "599" followed by serial or zone
        if recentText.contains("5NN") || recentText.contains("599") {
            detectedIntent = .contestExchange
            detectedRST = "599"

            if let repIndex = recentWords.firstIndex(where: { $0 == "5NN" || $0 == "599" }), repIndex + 1 < recentWords.count {
                detectedExchange = recentWords[repIndex + 1]
            }

            intentDescription = "Exchange received from \(detectedCallsign.isEmpty ? "station" : detectedCallsign)"
            suggestedReply = "5NN {SERIAL} TU"
            hasActionableSuggestion = true
            return
        }

        // 3. Detect Name & QTH
        if recentText.contains("NAME") || recentText.contains("QTH") || recentText.contains("OP") {
            detectedIntent = .ragchewInfo

            if let nameIdx = recentWords.firstIndex(where: { $0 == "NAME" || $0 == "OP" }), nameIdx + 1 < recentWords.count {
                detectedName = recentWords[nameIdx + 1]
            }
            if let qthIdx = recentWords.firstIndex(where: { $0 == "QTH" }), qthIdx + 1 < recentWords.count {
                detectedQTH = recentWords[qthIdx + 1]
            }

            intentDescription = "Operator details: \(detectedName) from \(detectedQTH)"
            suggestedReply = "TNX FER INFO UR 5NN FB 73"
            hasActionableSuggestion = true
            return
        }

        // 4. Detect Sign-off: "73", "SK", "TU EE"
        if recentText.contains("73") || recentText.contains("SK") || recentText.contains("TU") {
            detectedIntent = .signOff
            intentDescription = "Station signing off with 73 / SK"
            suggestedReply = "73 TU EE"
            hasActionableSuggestion = true
            return
        }

        // General listening
        if hasActionableSuggestion && detectedCallsign.isEmpty {
            hasActionableSuggestion = false
            detectedIntent = .general
            intentDescription = "Monitoring traffic..."
        }
    }

    private func extractCallsignAfterCQ(_ words: [String]) -> String? {
        // Look for the callsign after "CQ" or "DE"
        if let deIndex = words.lastIndex(of: "DE"), deIndex + 1 < words.count {
            let candidate = words[deIndex + 1]
            if isCallsignCandidate(candidate) {
                return candidate
            }
        }
        for word in words.reversed() {
            if isCallsignCandidate(word) && word != "TEST" && word != "DX" {
                return word
            }
        }
        return nil
    }

    private func isCallsignCandidate(_ word: String) -> Bool {
        guard word.count >= 3 && word.count <= 8 else { return false }
        let hasDigit = word.contains(where: \.isNumber)
        let hasLetter = word.contains(where: \.isLetter)
        let excluded = ["5NN", "599", "73", "88", "TEST", "CQ", "AGN", "TU", "NAME", "QTH"]
        return hasDigit && hasLetter && !excluded.contains(word)
    }

    // MARK: - Actions

    public func syncSpeedToDecoder() {
        let incomingWpm = Int(round(CWAudioDecoderEngine.shared.estimatedWPM))
        CWKeyerService.shared.setWPM(incomingWpm)
    }

    public func sendSuggestedReply(myCall: String) {
        guard !suggestedReply.isEmpty else { return }
        CWKeyerService.shared.send(
            text: suggestedReply,
            myCall: myCall,
            call: detectedCallsign,
            rst: detectedRST.isEmpty ? "599" : detectedRST,
            name: detectedName,
            qth: detectedQTH,
            exch: detectedExchange
        )
    }

    func populateQuickLog(appState: AppState) {
        if !detectedCallsign.isEmpty {
            appState.quickLogDraft.callsign = detectedCallsign
        }
        if !detectedRST.isEmpty {
            appState.quickLogDraft.rstReceived = detectedRST
        }
        if !detectedExchange.isEmpty {
            appState.quickLogDraft.receivedExchange = detectedExchange
        }
        if !detectedName.isEmpty {
            appState.quickLogDraft.name = detectedName
        }
        if !detectedQTH.isEmpty {
            appState.quickLogDraft.qth = detectedQTH
        }
    }
}
