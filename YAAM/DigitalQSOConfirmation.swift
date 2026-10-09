//
//  DigitalQSOConfirmation.swift
//  YAAM
//
//  How a Digital Suite QSO (RTTY/PSK, Hellschreiber, Olivia, JS8, SSTV) gets its frequency and band, and when the
//  operator confirms it before it is saved.
//

import Combine
import Foundation

// MARK: - The radio's frequency

nonisolated enum RadioFrequency {
    /// One place YAAM can read the radio's frequency from.
    struct Source: Sendable {
        let isConnected: Bool
        let frequencyHz: UInt64
    }

    /// The frequency of the first connected source, in the order given, or nil when none is connected. A source that
    /// is not connected is never read: they all start at 14.074 MHz before they connect.
    static func firstConnected(_ sources: [Source]) -> UInt64? {
        sources.first(where: { $0.isConnected && $0.frequencyHz > 0 })?.frequencyHz
    }
}

// MARK: - When the operator confirms

nonisolated enum DigitalQSOConfirmationMode: String, CaseIterable, Identifiable, Sendable {
    /// Ask only when something is missing: no radio frequency, a frequency outside the bands, or an empty field
    case whenFrequencyMissing
    /// Ask before every QSO
    case always

    static let storageKey = "digitalQSOConfirmationMode"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .whenFrequencyMissing: return "Only when the frequency is missing"
        case .always: return "Always"
        }
    }

    /// What the option is good and not good for, shown under the setting.
    var tradeOffs: String {
        switch self {
        case .whenFrequencyMissing:
            return "Good for: fast logging with the radio connected; you are asked only when something is missing. "
                + "Not good for: checking each QSO before it is saved."
        case .always:
            return "Good for: checking every QSO (callsign, reports, frequency, band) before it is saved. "
                + "Not good for: busy operating; one more click per QSO."
        }
    }

    static var current: DigitalQSOConfirmationMode {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .whenFrequencyMissing
    }
}

// MARK: - The QSO before it is saved

nonisolated struct DigitalQSODraft: Identifiable, Equatable, Sendable {
    let id = UUID()
    var callsign: String
    let mode: String
    var reportSent: String
    var reportReceived: String
    /// The frequency as the operator sees it, in MHz; the Quick Log rules read it (AmateurBandPlan.normalizedMHz)
    var frequencyText: String
    /// The radio's frequency when the draft was made, or nil when no radio was connected
    let radioFrequencyHz: UInt64?

    init(callsign: String, mode: String, reportSent: String, reportReceived: String, radioFrequencyHz: UInt64?) {
        self.callsign = callsign
        self.mode = mode
        self.reportSent = reportSent
        self.reportReceived = reportReceived
        self.radioFrequencyHz = radioFrequencyHz
        self.frequencyText = radioFrequencyHz.map { AmateurBandPlan.formattedMHz(Double($0) / 1_000_000) } ?? ""
    }

    var isSSTV: Bool { mode.uppercased() == "SSTV" }
    var cleanCallsign: String { callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    var cleanReportSent: String { reportSent.trimmingCharacters(in: .whitespacesAndNewlines) }
    var cleanReportReceived: String { reportReceived.trimmingCharacters(in: .whitespacesAndNewlines) }

    var frequencyMHz: Double? { AmateurBandPlan.normalizedMHz(frequencyText) }
    /// The band of the frequency, as the Quick Log finds it; nil outside the amateur bands
    var band: String? { frequencyMHz.flatMap(AmateurBandPlan.band(forMHz:)) }
    var frequencyHz: UInt64? { frequencyMHz.map { UInt64(($0 * 1_000_000).rounded()) } }

    /// Everything a QSO needs. Both reports are needed because an empty one is saved as 599; for SSTV they are RSV.
    var isComplete: Bool {
        Self.isValidCallsign(cleanCallsign) && band != nil
            && reportIsValid(cleanReportSent) && reportIsValid(cleanReportReceived)
    }

    private func reportIsValid(_ report: String) -> Bool {
        isSSTV ? Self.isValidRSV(report) : !report.isEmpty
    }

    /// SSTV is always confirmed; the other modes when the setting says so or when something is missing.
    func needsConfirmation(_ setting: DigitalQSOConfirmationMode) -> Bool {
        isSSTV || setting == .always || !isComplete
    }

    /// The same rule as the Quick Log (AppState.isValidOperatorCallsign): 3 to 20 characters, letters and digits,
    /// only A-Z, 0-9, "/" and "-".
    static func isValidCallsign(_ callsign: String) -> Bool {
        guard (3...20).contains(callsign.count),
              callsign.contains(where: \.isLetter),
              callsign.contains(where: \.isNumber) else { return false }
        let allowed = CharacterSet.uppercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: "/-"))
        return callsign.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// RSV: readability 1-5, signal strength 1-9, video (picture) quality 1-5, in ASCII digits as ADIF stores them.
    static func isValidRSV(_ report: String) -> Bool {
        let digits = report.unicodeScalars.compactMap { ("0"..."9").contains($0) ? Int($0.value) - 48 : nil }
        guard report.unicodeScalars.count == 3, digits.count == 3 else { return false }
        return (1...5).contains(digits[0]) && (1...9).contains(digits[1]) && (1...5).contains(digits[2])
    }
}

// MARK: - Between the engines and the logbook

@MainActor
final class DigitalQSOConfirmationCenter: ObservableObject {
    static let shared = DigitalQSOConfirmationCenter()

    /// The QSO shown for confirmation; nothing is saved until Record QSO.
    @Published var pending: DigitalQSODraft?
    /// Saves a QSO in the logbook (AppState.recordDigitalModemQSO).
    var record: ((DigitalQSODraft) -> Void)?

    /// A QSO from an engine: saved at once when nothing is missing and the setting allows it, otherwise shown.
    func submit(_ draft: DigitalQSODraft, setting: DigitalQSOConfirmationMode) {
        if draft.needsConfirmation(setting) {
            pending = draft
        } else {
            record?(draft)
        }
    }

    /// Record QSO: saves the confirmed QSO and returns true; a QSO that is not complete is not saved.
    @discardableResult
    func recordPending(_ draft: DigitalQSODraft) -> Bool {
        guard draft.isComplete else { return false }
        record?(draft)
        pending = nil
        return true
    }

    /// Discard QSO: closes the confirmation and saves nothing.
    func discardPending() {
        pending = nil
    }
}
