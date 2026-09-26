//
//  POTASOTAEngine.swift
//  YAAM
//
//  Central Session & Activation Engine for POTA & SOTA Field Operations.
//  Coordinates active activation state, real-time QSO rate, 10-QSO threshold milestones,
//  Park-to-Park (P2P) / Summit-to-Summit (S2S) detection, and hardware CAT sync.
//

import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - Field Logging Error
public enum FieldLoggingError: LocalizedError, Equatable, Sendable {
    case emptyCallsign
    case noActiveSession
    case duplicate(String)

    public var errorDescription: String? {
        switch self {
        case .emptyCallsign: return "Callsign cannot be empty"
        case .noActiveSession: return "No active activation session. Please start a session first."
        case .duplicate(let msg): return msg
        }
    }
}

// MARK: - POTASOTAEngine Implementation

@MainActor
public final class POTASOTAEngine: ObservableObject {
    public static let shared = POTASOTAEngine()

    // Active Field Session
    @Published public var activeSession: FieldActivationSession?
    @Published var sessionQSOs: [QSORecordModel] = []
    @Published var recentLogs: [QSORecordModel] = []

    // Field Ergonomics
    @Published public var isOutdoorHighContrastMode: Bool = false
    @Published public var playAudioFeedbackOnLog: Bool = true
    @Published public var lastLoggedCallsign: String? = nil
    @Published public var showMilestoneCelebration: Bool = false

    // Telemetry & Hardware Sync
    @ObservedObject private var rigEngine = RigControlEngine.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        restoreSessionFromUserDefaults()
    }

    // MARK: - Session Management

    public func startSession(
        program: FieldProgramType,
        reference: String,
        parkName: String,
        callsign: String,
        grid: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        notes: String = ""
    ) {
        let goal = program.requiredQSOsForActivation
        let session = FieldActivationSession(
            program: program,
            myReference: reference.uppercased().trimmingCharacters(in: .whitespacesAndNewlines),
            referenceName: parkName,
            operatorCallsign: callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines),
            gridSquare: grid.uppercased().trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: latitude,
            longitude: longitude,
            startTime: Date(),
            endTime: nil,
            qsoCount: 0,
            parkToParkCount: 0,
            summitToSummitCount: 0,
            targetGoal: goal,
            isActive: true,
            notes: notes,
            workedBands: [],
            workedModes: []
        )

        self.activeSession = session
        self.sessionQSOs = []
        saveSessionToUserDefaults()

        // Also notify RoverModeEngine if grid is specified
        if !grid.isEmpty && RoverModeEngine.shared.activeSession == nil {
            _ = RoverModeEngine.shared.activate(
                grid: grid,
                label: "\(program.rawValue) \(reference)",
                duration: .fourHours,
                stampInOutgoingQSOs: false
            )
        }
    }

    public func endSession() {
        guard var session = activeSession else { return }
        session.isActive = false
        session.endTime = Date()
        self.activeSession = session
        saveSessionToUserDefaults()
    }

    public func clearSession() {
        self.activeSession = nil
        self.sessionQSOs = []
        UserDefaults.standard.removeObject(forKey: "potaActiveSession_v1")
    }

    // MARK: - Rapid Pileup Logging Action

    func logFieldQSO(
        callsign: String,
        sentRST: String,
        receivedRST: String,
        contactedRef: String = "",
        comment: String = "",
        appState: AppState
    ) -> Result<QSORecordModel, FieldLoggingError> {
        let cleanCall = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCall.isEmpty else {
            return .failure(.emptyCallsign)
        }

        guard let session = activeSession, session.isActive else {
            return .failure(.noActiveSession)
        }

        // 1. Determine frequency & band from CAT Rig or active draft
        let freqMHz: Double
        let band: String
        let mode: String

        if rigEngine.isConnected && rigEngine.frequencyHz > 0 {
            freqMHz = rigEngine.frequencyMHz
            band = rigEngine.currentBand
            mode = rigEngine.mode
        } else {
            let draftFreq = Double(appState.quickLogDraft.frequencyMHz) ?? 14.074
            freqMHz = draftFreq > 0 ? draftFreq : 14.074
            band = AmateurBandPlan.band(forMHz: freqMHz) ?? "20m"
            mode = !appState.quickLogDraft.mode.isEmpty ? appState.quickLogDraft.mode : "SSB"
        }

        // 2. Check duplicate in current session
        let isDupe = sessionQSOs.contains { qso in
            qso["CALL"].uppercased() == cleanCall &&
            qso["BAND"].uppercased() == band.uppercased() &&
            qso["MODE"].uppercased() == mode.uppercased()
        }
        if isDupe {
            return .failure(.duplicate("Duplicate: \(cleanCall) already logged on \(band) \(mode) in this session!"))
        }

        // 3. Construct UTC timestamp
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let dateStr = String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        let timeStr = String(format: "%02d%02d%02d", components.hour ?? 0, components.minute ?? 0, components.second ?? 0)

        // 4. Populate standard ADIF fields for POTA / SOTA
        var fields: [String: String] = [
            "QSO_DATE": dateStr,
            "TIME_ON": timeStr,
            "CALL": cleanCall,
            "FREQ": String(format: "%.6f", freqMHz),
            "BAND": band.lowercased(),
            "MODE": mode.uppercased(),
            "RST_SENT": sentRST.isEmpty ? (mode.contains("CW") ? "599" : "59") : sentRST,
            "RST_RCVD": receivedRST.isEmpty ? (mode.contains("CW") ? "599" : "59") : receivedRST,
            "STATION_CALLSIGN": session.operatorCallsign,
            "OPERATOR": session.operatorCallsign,
            "QSL_SENT": "N",
            "QSL_RCVD": "N",
            "APP_YAAM_SOURCE": "FieldOps"
        ]

        if !session.gridSquare.isEmpty {
            fields["MY_GRIDSQUARE"] = session.gridSquare
        }

        // Tag POTA / SOTA references
        let cleanContactedRef = contactedRef.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var isP2P = false
        var isS2S = false

        switch session.program {
        case .pota:
            fields["MY_SIG"] = "POTA"
            fields["MY_SIG_INFO"] = session.myReference
            fields["MY_POTA_REF"] = session.myReference
            if !cleanContactedRef.isEmpty {
                fields["POTA_REF"] = cleanContactedRef
                fields["SIG"] = "POTA"
                fields["SIG_INFO"] = cleanContactedRef
                isP2P = true
            }
        case .sota:
            fields["MY_SIG"] = "SOTA"
            fields["MY_SIG_INFO"] = session.myReference
            fields["MY_SOTA_REF"] = session.myReference
            if !cleanContactedRef.isEmpty {
                fields["SOTA_REF"] = cleanContactedRef
                fields["SIG"] = "SOTA"
                fields["SIG_INFO"] = cleanContactedRef
                isS2S = true
            }
        case .wwff:
            fields["MY_SIG"] = "WWFF"
            fields["MY_SIG_INFO"] = session.myReference
            fields["MY_WWFF_REF"] = session.myReference
            if !cleanContactedRef.isEmpty {
                fields["WWFF_REF"] = cleanContactedRef
                isP2P = true
            }
        case .iota:
            fields["MY_IOTA"] = session.myReference
            if !cleanContactedRef.isEmpty {
                fields["IOTA"] = cleanContactedRef
            }
        }

        if !comment.isEmpty {
            fields["COMMENT"] = comment
        }

        let record = QSORecordModel(fields: fields)

        // 5. Commit to AppState & LogbookDatabase
        appState.addFieldQSO(record)

        // 6. Update Session Stats
        var updatedSession = session
        updatedSession.qsoCount += 1
        if isP2P { updatedSession.parkToParkCount += 1 }
        if isS2S { updatedSession.summitToSummitCount += 1 }

        if !updatedSession.workedBands.contains(band) {
            updatedSession.workedBands.append(band)
        }
        if !updatedSession.workedModes.contains(mode) {
            updatedSession.workedModes.append(mode)
        }

        let justQualified = updatedSession.qsoCount == updatedSession.targetGoal
        self.activeSession = updatedSession
        self.sessionQSOs.insert(record, at: 0)
        self.recentLogs.insert(record, at: 0)
        self.lastLoggedCallsign = cleanCall
        saveSessionToUserDefaults()

        // 7. Feedback Cues
        if playAudioFeedbackOnLog {
            playAudioBeep()
        }
        if justQualified {
            showMilestoneCelebration = true
        }

        return .success(record)
    }

    // MARK: - Audio Cue
    private func playAudioBeep() {
        NSSound(named: "Ping")?.play()
    }

    // MARK: - Persistence
    private func saveSessionToUserDefaults() {
        guard let session = activeSession else { return }
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: "potaActiveSession_v1")
        }
    }

    private func restoreSessionFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: "potaActiveSession_v1"),
              let session = try? JSONDecoder().decode(FieldActivationSession.self, from: data) else {
            return
        }
        self.activeSession = session
    }
}
