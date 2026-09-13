//
//  CWPileupSimulatorEngine.swift
//  YAAM
//
//  Native High-Performance Pileup Contest Simulator & Morse Runner Engine
//  Simulates realistic CW contest environments with multi-station concurrent pileups,
//  distinct audio pitches, individual speeds (WPM), atmospheric noise (QRN),
//  signal fading (QSB), adjacent-channel interference (QRM), and DSP IF filter emulation.
//  Includes full Enter-Sends-Message (ESM) state machine, real-time rate calculation,
//  and contest scoring.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

// MARK: - Contest Difficulty Presets

public enum CWPileupDifficulty: String, CaseIterable, Identifiable, Sendable {
    case beginner = "Beginner (Single Call)"
    case contester = "Contester (2–3 Stations)"
    case wpxChampionship = "WPX Championship (3–4 Stations)"
    case extremePileup = "Extreme Pileup (4–5 Stations)"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .beginner: return "Beginner"
        case .contester: return "Contester"
        case .wpxChampionship: return "WPX Contest"
        case .extremePileup: return "Extreme"
        }
    }

    public var iconName: String {
        switch self {
        case .beginner: return "person.fill"
        case .contester: return "person.2.fill"
        case .wpxChampionship: return "person.3.fill"
        case .extremePileup: return "flame.fill"
        }
    }

    public var stationCountRange: ClosedRange<Int> {
        switch self {
        case .beginner: return 1...1
        case .contester: return 2...3
        case .wpxChampionship: return 3...4
        case .extremePileup: return 4...5
        }
    }

    public var defaultWPM: Int {
        switch self {
        case .beginner: return 18
        case .contester: return 26
        case .wpxChampionship: return 32
        case .extremePileup: return 38
        }
    }

    public var defaultBandwidthHz: Double {
        switch self {
        case .beginner: return 500.0
        case .contester: return 400.0
        case .wpxChampionship: return 250.0
        case .extremePileup: return 150.0
        }
    }

    public var defaultQRN: Double {
        switch self {
        case .beginner: return 0.0
        case .contester: return 0.10
        case .wpxChampionship: return 0.25
        case .extremePileup: return 0.40
        }
    }

    public var qsbEnabled: Bool {
        switch self {
        case .beginner: return false
        case .contester, .wpxChampionship, .extremePileup: return true
        }
    }

    public var qrmEnabled: Bool {
        switch self {
        case .beginner, .contester: return false
        case .wpxChampionship, .extremePileup: return true
        }
    }
}

// MARK: - Simulation States

public enum CWPileupState: String, Sendable {
    case idle = "Standby"
    case transmittingCQ = "Sending CQ"
    case pileupCalling = "Pileup Calling"
    case transmittingExchange = "Sending Exchange"
    case stationResponding = "Station Responding"
    case transmittingTU = "Sending TU & Finalizing"
    case paused = "Paused"

    public var statusBadgeColor: Color {
        switch self {
        case .idle, .paused: return .secondary
        case .transmittingCQ, .transmittingExchange, .transmittingTU: return .red
        case .pileupCalling, .stationResponding: return .green
        }
    }

    public var isTransmitting: Bool {
        switch self {
        case .transmittingCQ, .transmittingExchange, .transmittingTU:
            return true
        default:
            return false
        }
    }
}

// MARK: - Virtual Station Model

public struct VirtualStation: Identifiable, Sendable {
    public let id = UUID()
    public let callsign: String
    public let pitchHz: Double
    public let wpm: Int
    public let signalStrength: Double // 0.2 to 1.0
    public let qsbSpeed: Double      // 0.1 to 0.4 Hz
    public let qsbPhase: Double      // 0 to 2*PI
    public let delayOffsetSec: Double // human latency before calling
    public let serialNumber: Int
    public var isAddressed: Bool = false
    public var isLogged: Bool = false
}

// MARK: - Logged Contest QSO Record

public struct CWPileupQSORecord: Identifiable, Sendable {
    public let id = UUID()
    public let qsoIndex: Int
    public let timestamp: Date
    public let callsign: String
    public let rstSent: String
    public let serialSent: Int
    public let rstRcvd: String
    public let serialRcvd: Int
    public let points: Int
    public let prefix: String
    public let isMultiplier: Bool
    public let isCorrect: Bool
}

// MARK: - Spectral Marker for Display

public struct CWSpectralMarker: Identifiable, Sendable {
    public let id = UUID()
    public let pitchHz: Double
    public let amplitude: Double
    public let callsign: String
    public let isActive: Bool
}

// MARK: - Main Pileup Simulator Engine

@MainActor
public final class CWPileupSimulatorEngine: ObservableObject {
    public static let shared = CWPileupSimulatorEngine()

    // MARK: - Published Operator Configuration
    @Published public var myCallsign: String = "EP2AES"
    @Published public var difficulty: CWPileupDifficulty = .contester
    @Published public var baseWPM: Int = 26
    @Published public var centerPitchHz: Double = 650.0
    @Published public var filterBandwidthHz: Double = 400.0 // 100, 250, 400, 500
    @Published public var qrnLevel: Double = 0.10          // 0.0 to 0.5 noise level
    @Published public var qsbEnabled: Bool = true
    @Published public var qrmEnabled: Bool = false
    @Published public var audioVolume: Double = 0.75
    @Published public var autoCQOnIdle: Bool = false

    // MARK: - Live Simulator State
    @Published public var state: CWPileupState = .idle
    @Published public var isRunning: Bool = false
    @Published public var activeStations: [VirtualStation] = []
    @Published public var activeTargetStation: VirtualStation? = nil
    @Published public var spectralMarkers: [CWSpectralMarker] = []
    @Published public var currentTransmittingText: String = ""

    // Operator Desk Draft
    @Published public var draftCallsign: String = ""
    @Published public var draftRstSent: String = "599"
    @Published public var draftSerialSent: Int = 1
    @Published public var draftRstRcvd: String = "599"
    @Published public var draftSerialRcvd: String = ""

    // Scoring & Statistics
    @Published public var qsoRecords: [CWPileupQSORecord] = []
    @Published public var sessionStartTime: Date? = nil
    @Published public var elapsedTimeSec: TimeInterval = 0.0
    @Published public var qsoCount: Int = 0
    @Published public var qsoRatePerHour: Double = 0.0
    @Published public var totalPoints: Int = 0
    @Published public var multiplierCount: Int = 0
    @Published public var totalScore: Int = 0
    @Published public var currentStreak: Int = 0
    @Published public var bestStreak: Int = 0
    @Published public var accuracyPercentage: Double = 100.0

    // Internal Audio & Timer Machinery
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var isAudioSetup: Bool = false
    private var activePlaybackTask: Task<Void, Never>?
    private var sessionTimer: Timer?
    private var workedPrefixes: Set<String> = []

    // International Contest Callsign Database (Authentic DX/Contest Calls)
    public static let callsignDatabase: [String] = [
        "DL1ABC", "K3LR", "JA1BJK", "OH2BH", "PY2ZX", "VE3NEA", "UR5LAM",
        "EA4TX", "I2WIJ", "SM5AJV", "CT1BOH", "LA8HGA", "OM3RM", "S50A",
        "YU1ZZ", "LZ2JA", "SV1DPI", "HA8IH", "4X4DK", "VK2GR", "ZL1BY",
        "VU2PTT", "RA3W", "G4BJM", "OK1CF", "9A1A", "SP5GR", "F6KNB",
        "W1AW", "N2IC", "K1DG", "W3LPL", "AA3B", "K5ZD", "N3QE",
        "ZF2MJ", "TI7W", "KP4AA", "V31MA", "PJ2T", "P49X", "KH6LC",
        "KL7RA", "LU8DPM", "CE3CT", "CX7CO", "ZP5AA", "JA7NVF", "JH1EAQ",
        "BV2B", "HL5IVL", "HS0ZDY", "9M2TO", "VR2XMT", "YB0ECT", "DU1/JJ5GMJ",
        "ZS6CC", "5Z4/EA4ATI", "CN8KD", "EA8RM", "EA9LZ", "7Z1SJ", "A61Q",
        "HZ1SK", "9K2HN", "4Z5LA", "OD5ZZ", "JY5MM", "TA1D", "EK6GB"
    ]

    public init() {
        self.applyDifficultyPreset(difficulty)
    }

    // MARK: - Difficulty Configuration

    public func applyDifficultyPreset(_ diff: CWPileupDifficulty) {
        self.difficulty = diff
        self.baseWPM = diff.defaultWPM
        self.filterBandwidthHz = diff.defaultBandwidthHz
        self.qrnLevel = diff.defaultQRN
        self.qsbEnabled = diff.qsbEnabled
        self.qrmEnabled = diff.qrmEnabled
    }

    // MARK: - Session Lifecycle

    public func startSession() {
        stopSession()
        ensureAudioInitialized()

        isRunning = true
        state = .idle
        sessionStartTime = Date()
        elapsedTimeSec = 0.0
        qsoRecords.removeAll()
        workedPrefixes.removeAll()
        qsoCount = 0
        qsoRatePerHour = 0.0
        totalPoints = 0
        multiplierCount = 0
        totalScore = 0
        currentStreak = 0
        accuracyPercentage = 100.0
        draftSerialSent = 1
        draftCallsign = ""
        draftSerialRcvd = ""
        activeStations.removeAll()
        activeTargetStation = nil
        spectralMarkers.removeAll()

        // Start 1Hz timer for elapsed time and rolling rate calculation
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSessionClock()
            }
        }

        // Trigger initial CQ transmission or standby
        executeSendCQ()
    }

    public func pauseSession() {
        if isRunning {
            isRunning = false
            state = .paused
            stopAudioPlayback()
            sessionTimer?.invalidate()
            sessionTimer = nil
        }
    }

    public func resumeSession() {
        if !isRunning && sessionStartTime != nil {
            isRunning = true
            state = .idle
            sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateSessionClock()
                }
            }
        }
    }

    public func stopSession() {
        isRunning = false
        state = .idle
        stopAudioPlayback()
        sessionTimer?.invalidate()
        sessionTimer = nil
        activeStations.removeAll()
        activeTargetStation = nil
        spectralMarkers.removeAll()
        currentTransmittingText = ""
    }

    private func updateSessionClock() {
        guard let start = sessionStartTime, isRunning else { return }
        elapsedTimeSec = Date().timeIntervalSince(start)

        // Calculate rolling or total QSO rate (QSOs / hour)
        if elapsedTimeSec > 5.0 && qsoCount > 0 {
            let hours = elapsedTimeSec / 3600.0
            qsoRatePerHour = Double(qsoCount) / hours
        } else {
            qsoRatePerHour = 0.0
        }
    }

    // MARK: - Enter-Sends-Message (ESM) State Machine Execution

    public func handleEnterKey() {
        guard isRunning else {
            startSession()
            return
        }

        switch state {
        case .idle, .paused:
            if draftCallsign.trimmingCharacters(in: .whitespaces).isEmpty {
                executeSendCQ()
            } else {
                executeSendExchange()
            }

        case .pileupCalling:
            if !draftCallsign.trimmingCharacters(in: .whitespaces).isEmpty {
                executeSendExchange()
            } else {
                // Operator pressed enter without picking a callsign -> Re-send CQ
                executeSendCQ()
            }

        case .stationResponding:
            // Station is responding with exchange -> operator confirms with TU & Log
            executeSendTUAndLog()

        case .transmittingCQ, .transmittingExchange, .transmittingTU:
            // Already transmitting -> Esc to abort, ignore duplicate Enter
            break
        }
    }

    // MARK: - Operator Actions

    public func executeSendCQ() {
        guard isRunning else { return }
        stopAudioPlayback()

        let call = myCallsign.isEmpty ? "EP2AES" : myCallsign.uppercased()
        let cqText = "CQ TEST \(call)"
        state = .transmittingCQ
        currentTransmittingText = cqText

        playOperatorTransmission(text: cqText, wpm: baseWPM) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.currentTransmittingText = ""
                self.triggerPileupResponse()
            }
        }
    }

    public func executeSendExchange() {
        let enteredCall = draftCallsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !enteredCall.isEmpty else {
            executeSendCQ()
            return
        }

        stopAudioPlayback()
        state = .transmittingExchange
        let exchText = "\(enteredCall) 5NN \(String(format: "%03d", draftSerialSent))"
        currentTransmittingText = exchText

        playOperatorTransmission(text: exchText, wpm: baseWPM) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.currentTransmittingText = ""
                self.processStationExchangeResponse(to: enteredCall)
            }
        }
    }

    public func executeSendTUAndLog() {
        stopAudioPlayback()

        let call = myCallsign.isEmpty ? "EP2AES" : myCallsign.uppercased()
        let tuText = "TU \(call) TEST"
        state = .transmittingTU
        currentTransmittingText = tuText

        // Log the QSO
        recordCompletedQSO()

        playOperatorTransmission(text: tuText, wpm: baseWPM) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.currentTransmittingText = ""
                self.state = .idle

                // Prepare next QSO draft
                self.draftCallsign = ""
                self.draftSerialRcvd = ""
                self.activeTargetStation = nil

                // If auto-CQ is enabled or pileup has remaining callers, trigger next cycle
                if self.autoCQOnIdle {
                    self.executeSendCQ()
                } else {
                    // Quick pileup resumption if other callers are waiting
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self = self, self.isRunning, self.state == .idle else { return }
                        self.triggerFollowUpPileup()
                    }
                }
            }
        }
    }

    public func abortTransmission() {
        stopAudioPlayback()
        currentTransmittingText = ""
        if isRunning {
            state = .idle
        }
    }

    public func sendQueryAGN() {
        guard isRunning else { return }
        stopAudioPlayback()
        state = .transmittingExchange
        let agnText = "?"
        currentTransmittingText = agnText

        playOperatorTransmission(text: agnText, wpm: baseWPM) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.currentTransmittingText = ""
                if let target = self.activeTargetStation {
                    // Target repeats its exchange
                    self.playTargetStationExchange(target)
                } else {
                    // Whole pileup calls again!
                    self.triggerFollowUpPileup()
                }
            }
        }
    }

    // MARK: - Virtual Station Generation & Pileup Dynamics

    private func triggerPileupResponse() {
        activeStations.removeAll()
        activeTargetStation = nil

        let countRange = difficulty.stationCountRange
        let count = Int.random(in: countRange)

        var selectedCallsigns: [String] = []
        var available = Self.callsignDatabase.shuffled()

        for _ in 0..<count {
            if let call = available.popLast() {
                selectedCallsigns.append(call)
            }
        }

        var stations: [VirtualStation] = []
        let center = centerPitchHz
        let halfBw = filterBandwidthHz / 2.0

        for (idx, call) in selectedCallsigns.enumerated() {
            // Distribute pitch around center pitch, with 70% falling inside the filter passband
            let offset: Double
            if idx == 0 || Double.random(in: 0...1) > 0.3 {
                offset = Double.random(in: -halfBw * 0.85 ... halfBw * 0.85)
            } else {
                offset = Double.random(in: -halfBw * 1.5 ... halfBw * 1.5)
            }
            let pitch = max(350.0, min(1100.0, center + offset))

            // Realistic speed variance: baseWPM +/- 4 WPM
            let wpm = max(16, min(48, baseWPM + Int.random(in: -3...3)))
            let strength = Double.random(in: 0.5...1.0)
            let qsbSpd = Double.random(in: 0.15...0.40)
            let qsbPh = Double.random(in: 0...(2 * .pi))
            let delay = Double.random(in: 0.05...0.35) // Staggered start
            let serial = Int.random(in: 1...350)

            stations.append(VirtualStation(
                callsign: call,
                pitchHz: pitch,
                wpm: wpm,
                signalStrength: strength,
                qsbSpeed: qsbSpd,
                qsbPhase: qsbPh,
                delayOffsetSec: delay,
                serialNumber: serial
            ))
        }

        self.activeStations = stations
        self.state = .pileupCalling
        self.updateSpectralMarkers(for: stations)

        // Synthesize and play concurrent pileup audio
        playConcurrentPileup(stations: stations) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning, self.state == .pileupCalling else { return }
                // Pileup finished calling; awaiting operator response
            }
        }
    }

    private func triggerFollowUpPileup() {
        guard !activeStations.isEmpty else {
            executeSendCQ()
            return
        }

        // Remaining callers try again with slightly different staggered timings
        var refreshed: [VirtualStation] = []
        for st in activeStations where !st.isLogged {
            var s = st
            s = VirtualStation(
                callsign: s.callsign,
                pitchHz: s.pitchHz,
                wpm: s.wpm,
                signalStrength: s.signalStrength,
                qsbSpeed: s.qsbSpeed,
                qsbPhase: s.qsbPhase + Double.random(in: 0.5...1.5),
                delayOffsetSec: Double.random(in: 0.05...0.3),
                serialNumber: s.serialNumber
            )
            refreshed.append(s)
        }

        guard !refreshed.isEmpty else {
            executeSendCQ()
            return
        }

        self.activeStations = refreshed
        self.state = .pileupCalling
        self.updateSpectralMarkers(for: refreshed)

        playConcurrentPileup(stations: refreshed) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning, self.state == .pileupCalling else { return }
            }
        }
    }

    private func processStationExchangeResponse(to enteredCall: String) {
        // Look for exact match or partial match in active pileup
        var matchedStation: VirtualStation? = nil
        var isPartial = false

        for station in activeStations {
            if station.callsign == enteredCall {
                matchedStation = station
                break
            } else if station.callsign.hasPrefix(enteredCall) || station.callsign.contains(enteredCall) {
                matchedStation = station
                isPartial = true
            }
        }

        if let station = matchedStation {
            activeTargetStation = station
            if isPartial {
                // Operator entered partial call -> station clarifies with full callsign
                draftCallsign = station.callsign
            }
            draftSerialRcvd = String(format: "%03d", station.serialNumber)
            playTargetStationExchange(station, includeClarification: isPartial)
        } else {
            // Operator entered a callsign that was NOT in the pileup!
            // Pileup either ignores or sends "?"
            activeTargetStation = nil
            playUnrecognizedCallResponse()
        }
    }

    private func playTargetStationExchange(_ station: VirtualStation, includeClarification: Bool = false) {
        state = .stationResponding
        let serialStr = String(format: "%03d", station.serialNumber)
        let responseText: String
        if includeClarification {
            responseText = "\(station.callsign) 5NN \(serialStr)"
        } else {
            responseText = "5NN \(serialStr)"
        }

        playSingleStationAudio(
            text: responseText,
            pitchHz: station.pitchHz,
            wpm: station.wpm,
            amplitude: station.signalStrength
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning, self.state == .stationResponding else { return }
                // Station finished sending exchange; waiting for operator TU & Log
            }
        }
    }

    private func playUnrecognizedCallResponse() {
        state = .stationResponding
        let randomPitch = centerPitchHz + Double.random(in: -100...100)
        playSingleStationAudio(text: "?", pitchHz: randomPitch, wpm: baseWPM, amplitude: 0.6) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.state = .pileupCalling
            }
        }
    }

    // MARK: - Scoring, Multipliers, & Logbook Records

    private func recordCompletedQSO() {
        let enteredCall = draftCallsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !enteredCall.isEmpty else { return }

        let target = activeTargetStation
        let isMatch = (target?.callsign == enteredCall)

        let prefix = extractContestPrefix(from: enteredCall)
        let isNewMult = !workedPrefixes.contains(prefix)
        if isNewMult {
            workedPrefixes.insert(prefix)
            multiplierCount = workedPrefixes.count
        }

        let pts = isMatch ? 3 : 0 // 3 points per valid QSO
        let qsoIdx = qsoRecords.count + 1

        let rcvdSerial = Int(draftSerialRcvd) ?? (target?.serialNumber ?? 1)

        let record = CWPileupQSORecord(
            qsoIndex: qsoIdx,
            timestamp: Date(),
            callsign: enteredCall,
            rstSent: draftRstSent,
            serialSent: draftSerialSent,
            rstRcvd: draftRstRcvd,
            serialRcvd: rcvdSerial,
            points: pts,
            prefix: prefix,
            isMultiplier: isNewMult,
            isCorrect: isMatch
        )

        qsoRecords.insert(record, at: 0) // Prepend newest to top
        qsoCount = qsoRecords.count

        if isMatch {
            currentStreak += 1
            if currentStreak > bestStreak {
                bestStreak = currentStreak
            }
        } else {
            currentStreak = 0
        }

        let correctQSOs = qsoRecords.filter { $0.isCorrect }.count
        accuracyPercentage = Double(correctQSOs) / Double(qsoCount) * 100.0

        totalPoints = qsoRecords.reduce(0) { $0 + $1.points }
        totalScore = totalPoints * max(1, multiplierCount)

        // Increment Sent Serial for next QSO
        draftSerialSent += 1

        // Mark target station as logged so it doesn't call again
        if let targetId = target?.id {
            if let idx = activeStations.firstIndex(where: { $0.id == targetId }) {
                activeStations[idx].isLogged = true
            }
        }
    }

    public static func extractContestPrefix(from call: String) -> String {
        let clean = call.trimmingCharacters(in: .whitespaces).uppercased()
        guard !clean.isEmpty else { return "" }

        // Strip portable indicator if any (e.g. DU1/JJ5GMJ -> DU1)
        let mainPart: String
        if clean.contains("/") {
            let parts = clean.split(separator: "/")
            if parts.count >= 2 {
                mainPart = parts[0].count <= parts[1].count ? String(parts[0]) : String(parts[1])
            } else {
                mainPart = clean
            }
        } else {
            mainPart = clean
        }

        var prefix = ""
        let startsWithDigit = mainPart.first?.isNumber == true

        if startsWithDigit {
            // e.g. 4X4DK, 9A1A, 3DA0TB
            var phase = 0 // 0: initial digits, 1: letters, 2: ending digits
            for char in mainPart {
                if phase == 0 {
                    if char.isNumber {
                        prefix.append(char)
                    } else if char.isLetter {
                        phase = 1
                        prefix.append(char)
                    } else {
                        break
                    }
                } else if phase == 1 {
                    if char.isLetter {
                        prefix.append(char)
                    } else if char.isNumber {
                        phase = 2
                        prefix.append(char)
                    } else {
                        break
                    }
                } else if phase == 2 {
                    if char.isNumber {
                        prefix.append(char)
                    } else {
                        break
                    }
                }
            }
        } else {
            // e.g. DL1ABC, W1AW, KH6LC
            var phase = 0 // 0: letters, 1: digits
            for char in mainPart {
                if phase == 0 {
                    if char.isLetter {
                        prefix.append(char)
                    } else if char.isNumber {
                        phase = 1
                        prefix.append(char)
                    } else {
                        break
                    }
                } else if phase == 1 {
                    if char.isNumber {
                        prefix.append(char)
                    } else {
                        break
                    }
                }
            }
        }

        return prefix.isEmpty ? clean : prefix
    }

    private func extractContestPrefix(from call: String) -> String {
        Self.extractContestPrefix(from: call)
    }

    // MARK: - Spectral Display Mapping

    private func updateSpectralMarkers(for stations: [VirtualStation]) {
        let center = centerPitchHz
        let halfBw = filterBandwidthHz / 2.0

        self.spectralMarkers = stations.map { st in
            let inPassband = abs(st.pitchHz - center) <= halfBw
            return CWSpectralMarker(
                pitchHz: st.pitchHz,
                amplitude: inPassband ? st.signalStrength : st.signalStrength * 0.25,
                callsign: st.callsign,
                isActive: inPassband
            )
        }
    }

    // MARK: - Audio Engine & Multi-Tone DSP Synthesis

    private func ensureAudioInitialized() {
        guard !isAudioSetup || audioEngine == nil else { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let format = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            self.audioEngine = engine
            self.playerNode = player
            self.isAudioSetup = true
        } catch {
            print("❌ CWPileupSimulatorEngine: Failed to start AVAudioEngine: \(error.localizedDescription)")
        }
    }

    public func stopAudioPlayback() {
        activePlaybackTask?.cancel()
        activePlaybackTask = nil
        playerNode?.stop()
    }

    private func playOperatorTransmission(text: String, wpm: Int, onComplete: @escaping @Sendable () -> Void) {
        stopAudioPlayback()
        ensureAudioInitialized()
        guard let player = playerNode else {
            onComplete()
            return
        }

        let buffer = synthesizeSingleStationBuffer(
            text: text,
            pitchHz: centerPitchHz,
            wpm: wpm,
            amplitude: 0.85,
            attenuateByFilter: false,
            addQRN: false
        )

        guard let buf = buffer else {
            onComplete()
            return
        }

        player.stop()
        player.scheduleBuffer(buf, at: nil, options: []) {
            onComplete()
        }
        player.play()
    }

    private func playSingleStationAudio(
        text: String,
        pitchHz: Double,
        wpm: Int,
        amplitude: Double,
        onComplete: @escaping @Sendable () -> Void
    ) {
        stopAudioPlayback()
        ensureAudioInitialized()
        guard let player = playerNode else {
            onComplete()
            return
        }

        let buffer = synthesizeSingleStationBuffer(
            text: text,
            pitchHz: pitchHz,
            wpm: wpm,
            amplitude: amplitude,
            attenuateByFilter: true,
            addQRN: true
        )

        guard let buf = buffer else {
            onComplete()
            return
        }

        player.stop()
        player.scheduleBuffer(buf, at: nil, options: []) {
            onComplete()
        }
        player.play()
    }

    private func playConcurrentPileup(stations: [VirtualStation], onComplete: @escaping @Sendable () -> Void) {
        stopAudioPlayback()
        ensureAudioInitialized()
        guard let player = playerNode else {
            onComplete()
            return
        }

        let buffer = synthesizeMultiStationPileupBuffer(stations: stations)

        guard let buf = buffer else {
            onComplete()
            return
        }

        player.stop()
        player.scheduleBuffer(buf, at: nil, options: []) {
            onComplete()
        }
        player.play()
    }

    // MARK: - DSP Buffer Synthesizers

    /// Synthesizes clean Morse code for a single station with optional filter attenuation and QRN.
    public func synthesizeSingleStationBuffer(
        text: String,
        pitchHz: Double,
        wpm: Int,
        amplitude: Double,
        attenuateByFilter: Bool,
        addQRN: Bool
    ) -> AVAudioPCMBuffer? {
        guard let player = playerNode else { return nil }
        let format = player.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 48000.0
        let channels = Int(format.channelCount)
        guard channels > 0 else { return nil }

        let blocks = buildMorseToneBlocks(text: text, wpm: wpm, sampleRate: sampleRate)
        let totalFrames = blocks.reduce(0) { $0 + $1.frames }
        guard totalFrames > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(totalFrames)

        // Filter attenuation calculation
        var effectiveAmp = Float(amplitude * audioVolume)
        if attenuateByFilter {
            let freqDelta = abs(pitchHz - centerPitchHz)
            let halfBw = filterBandwidthHz / 2.0
            if freqDelta > halfBw {
                // Steep 24dB/octave crystal filter rolloff
                let excessHz = freqDelta - halfBw
                let attenuationDb = min(40.0, excessHz * 0.20)
                effectiveAmp *= Float(pow(10.0, -attenuationDb / 20.0))
            }
        }

        var monoSamples = [Float](repeating: 0, count: totalFrames)
        let omega = 2.0 * .pi * pitchHz / sampleRate
        var phase: Double = 0.0
        var writePos = 0
        let rampFrames = max(1, Int(sampleRate * 0.004)) // 4ms soft cosine rise/fall envelope

        for block in blocks {
            let frames = block.frames
            if !block.isTone {
                writePos += frames
                phase = 0.0
            } else {
                let rf = min(rampFrames, frames / 2)
                for f in 0..<frames {
                    let s = Float(sin(phase)) * effectiveAmp
                    var env: Float = 1.0
                    if f < rf {
                        env = 0.5 * (1.0 - cos(Float.pi * Float(f) / Float(rf)))
                    } else if f > (frames - rf) {
                        let endF = frames - f
                        env = 0.5 * (1.0 - cos(Float.pi * Float(endF) / Float(rf)))
                    }
                    monoSamples[writePos + f] = s * env
                    phase += omega
                    if phase > 2.0 * .pi { phase -= 2.0 * .pi }
                }
                writePos += frames
            }
        }

        // Add QRN atmospheric noise if requested
        if addQRN && qrnLevel > 0.001 {
            let noiseAmp = Float(qrnLevel * 0.12)
            for i in 0..<totalFrames {
                let noise = Float.random(in: -noiseAmp...noiseAmp)
                monoSamples[i] += noise
            }
        }

        // Copy mono samples to all audio output channels
        for ch in 0..<channels {
            if let chData = buffer.floatChannelData?[ch] {
                for i in 0..<totalFrames {
                    chData[i] = monoSamples[i]
                }
            }
        }

        return buffer
    }

    /// Synthesizes simultaneous multi-tone Morse pileup with distinct frequencies, speeds, QSB fading, and QRN.
    public func synthesizeMultiStationPileupBuffer(stations: [VirtualStation]) -> AVAudioPCMBuffer? {
        guard let player = playerNode, !stations.isEmpty else { return nil }
        let format = player.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 48000.0
        let channels = Int(format.channelCount)
        guard channels > 0 else { return nil }

        // Determine maximum duration across all calling stations including staggered delays
        var maxFrames = 0
        var stationTracks: [(station: VirtualStation, delayFrames: Int, blocks: [(isTone: Bool, frames: Int)])] = []

        for st in stations {
            let blocks = buildMorseToneBlocks(text: st.callsign, wpm: st.wpm, sampleRate: sampleRate)
            let stationDurationFrames = blocks.reduce(0) { $0 + $1.frames }
            let delayFrames = Int(st.delayOffsetSec * sampleRate)
            let totalStationFrames = delayFrames + stationDurationFrames
            if totalStationFrames > maxFrames {
                maxFrames = totalStationFrames
            }
            stationTracks.append((station: st, delayFrames: delayFrames, blocks: blocks))
        }

        guard maxFrames > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(maxFrames)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(maxFrames)

        var monoMix = [Float](repeating: 0, count: maxFrames)
        let rampFrames = max(1, Int(sampleRate * 0.004)) // 4ms soft cosine ramp

        // Render each station into the mix buffer
        for track in stationTracks {
            let st = track.station
            let freqDelta = abs(st.pitchHz - centerPitchHz)
            let halfBw = filterBandwidthHz / 2.0

            // Filter passband attenuation
            var stationAmp = Float(st.signalStrength * audioVolume * 0.65)
            if freqDelta > halfBw {
                let excessHz = freqDelta - halfBw
                let attenDb = min(36.0, excessHz * 0.22)
                stationAmp *= Float(pow(10.0, -attenDb / 20.0))
            }

            let omega = 2.0 * .pi * st.pitchHz / sampleRate
            var phase: Double = 0.0
            var writePos = track.delayFrames

            let qsbOmega = 2.0 * .pi * st.qsbSpeed / sampleRate
            var qsbPhase = st.qsbPhase

            for block in track.blocks {
                let frames = block.frames
                if !block.isTone {
                    writePos += frames
                    phase = 0.0
                    qsbPhase += qsbOmega * Double(frames)
                } else {
                    let rf = min(rampFrames, frames / 2)
                    for f in 0..<frames {
                        let targetIdx = writePos + f
                        guard targetIdx < maxFrames else { break }

                        // QSB amplitude modulation
                        var currentAmp = stationAmp
                        if qsbEnabled {
                            let qsbMod = Float(0.55 + 0.45 * sin(qsbPhase))
                            currentAmp *= qsbMod
                        }

                        let s = Float(sin(phase)) * currentAmp
                        var env: Float = 1.0
                        if f < rf {
                            env = 0.5 * (1.0 - cos(Float.pi * Float(f) / Float(rf)))
                        } else if f > (frames - rf) {
                            let endF = frames - f
                            env = 0.5 * (1.0 - cos(Float.pi * Float(endF) / Float(rf)))
                        }

                        monoMix[targetIdx] += (s * env)

                        phase += omega
                        if phase > 2.0 * .pi { phase -= 2.0 * .pi }
                        qsbPhase += qsbOmega
                    }
                    writePos += frames
                }
            }
        }

        // Add QRM adjacent interference if enabled
        if qrmEnabled {
            let qrmPitch = centerPitchHz + (Double.random(in: 0...1) > 0.5 ? 280.0 : -260.0)
            let qrmOmega = 2.0 * .pi * qrmPitch / sampleRate
            var qrmPhase: Double = 0.0
            let qrmAmp = Float(0.08 * audioVolume)
            for i in 0..<maxFrames {
                monoMix[i] += Float(sin(qrmPhase)) * qrmAmp
                qrmPhase += qrmOmega
            }
        }

        // Add atmospheric QRN noise floor
        if qrnLevel > 0.001 {
            let noiseAmp = Float(qrnLevel * 0.10)
            for i in 0..<maxFrames {
                let noise = Float.random(in: -noiseAmp...noiseAmp)
                monoMix[i] += noise
            }
        }

        // Soft limiting / compression to prevent clipping
        for i in 0..<maxFrames {
            let sample = monoMix[i]
            if sample > 0.95 {
                monoMix[i] = 0.95 + 0.05 * tanh(sample - 0.95)
            } else if sample < -0.95 {
                monoMix[i] = -0.95 + 0.05 * tanh(sample + 0.95)
            }
        }

        // Copy mono mix to all channels
        for ch in 0..<channels {
            if let chData = buffer.floatChannelData?[ch] {
                for i in 0..<maxFrames {
                    chData[i] = monoMix[i]
                }
            }
        }

        return buffer
    }

    private func buildMorseToneBlocks(text: String, wpm: Int, sampleRate: Double) -> [(isTone: Bool, frames: Int)] {
        let ditDuration = 1.2 / Double(max(5, wpm))
        let ditFrames = max(1, Int(ditDuration * sampleRate))
        let dahFrames = ditFrames * 3
        let intraCharSpaceFrames = ditFrames
        let interCharSpaceFrames = ditFrames * 3
        let wordSpaceFrames = ditFrames * 7

        var blocks: [(isTone: Bool, frames: Int)] = []
        let morseTable = CWKeyerService.morseAlphabet
        let cleanText = text.uppercased()

        for (charIdx, char) in cleanText.enumerated() {
            if char == " " {
                blocks.append((false, wordSpaceFrames))
                continue
            }
            guard let pattern = morseTable[char] else { continue }

            for (symIdx, sym) in pattern.enumerated() {
                if sym == "." {
                    blocks.append((true, ditFrames))
                } else if sym == "-" {
                    blocks.append((true, dahFrames))
                }
                if symIdx < pattern.count - 1 {
                    blocks.append((false, intraCharSpaceFrames))
                }
            }

            if charIdx < cleanText.count - 1 {
                blocks.append((false, interCharSpaceFrames))
            }
        }

        return blocks
    }
}
