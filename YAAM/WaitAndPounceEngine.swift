//
//  WaitAndPounceEngine.swift
//  YAAM
//
//  Autonomous & Semi-Autonomous Wait and Pounce (W&P) DX Hunter Engine for FT8 & FT4.
//  Tracks target DX stations while engaged in QSOs with third parties, detects the exact
//  completion moment (RR73 / 73 / CQ), and fires an instantaneous pounce at the start of
//  the next 15-second timeslot before pileups form.
//

import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI

// MARK: - State & Status Models

public enum WaitAndPounceStatus: Equatable, Sendable {
    case idle
    case hunting(mode: String)
    case tracking(target: String, interlocutor: String, stage: String, snr: Int32, deltaHz: UInt32)
    case armed(target: String, deltaHz: UInt32, secondsRemaining: Double)
    case pouncing(target: String, attempt: Int, maxAttempts: Int, deltaHz: UInt32)
    case engaged(target: String, snr: Int32)
    case cooldown(target: String, reason: String)

    public var title: String {
        switch self {
        case .idle:
            return "IDLE"
        case .hunting(let mode):
            return "HUNTING (\(mode))"
        case .tracking(let target, let interlocutor, let stage, _, _):
            return "TRACKING \(target) ↔ \(interlocutor) [\(stage)]"
        case .armed(let target, _, let sec):
            return String(format: "ARMED ON \(target) (Pounce in %.1fs)", max(0, sec))
        case .pouncing(let target, let attempt, let maxAtt, _):
            return "POUNCING ⚡️ \(target) [Try \(attempt)/\(maxAtt)]"
        case .engaged(let target, let snr):
            let snrStr = snr >= 0 ? "+\(snr)" : "\(snr)"
            return "ENGAGED WITH \(target) (\(snrStr) dB) 🎉"
        case .cooldown(let target, let reason):
            return "COOLDOWN: \(target) (\(reason))"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .idle:
            return .secondary
        case .hunting:
            return .blue
        case .tracking:
            return .orange
        case .armed:
            return .yellow
        case .pouncing:
            return .red
        case .engaged:
            return .green
        case .cooldown:
            return .purple
        }
    }

    public var badgeIcon: String {
        switch self {
        case .idle:
            return "scope"
        case .hunting:
            return "waveform.badge.magnifyingglass"
        case .tracking:
            return "arrow.triangle.2.circlepath"
        case .armed:
            return "bolt.badge.clock.fill"
        case .pouncing:
            return "antenna.radiowaves.left.and.right"
        case .engaged:
            return "checkmark.seal.fill"
        case .cooldown:
            return "clock.arrow.circlepath"
        }
    }

    public var isActivelyCalling: Bool {
        if case .pouncing = self { return true }
        return false
    }

    public var isArmedOrTracking: Bool {
        switch self {
        case .tracking, .armed, .pouncing: return true
        default: return false
        }
    }
}

public enum TargetHuntMode: String, CaseIterable, Identifiable, Sendable {
    case manualWatchlist = "Watchlist / Manual"
    case autoNewDXCC = "Auto: New DXCC (ATNO)"
    case autoNewBand = "Auto: New Band"
    case autoNewGrid = "Auto: New Grid"
    case apexTarget = "Auto: Apex Tactical Target"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .manualWatchlist: return "Watchlist"
        case .autoNewDXCC: return "New DXCC"
        case .autoNewBand: return "New Band"
        case .autoNewGrid: return "New Grid"
        case .apexTarget: return "Apex"
        }
    }

    public var iconName: String {
        switch self {
        case .manualWatchlist: return "list.bullet"
        case .autoNewDXCC: return "star.fill"
        case .autoNewBand: return "target"
        case .autoNewGrid: return "square.grid.2x2.fill"
        case .apexTarget: return "flame.fill"
        }
    }
}

public enum PounceFrequencyMode: String, CaseIterable, Identifiable, Sendable {
    case simplex = "Simplex (On DX Freq)"
    case autoClearSplit = "Auto-Clear (Split Passband)"
    case holdTxFreq = "Hold Tx Freq"

    public var id: String { rawValue }
}

public struct PounceTarget: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var callsign: String
    public var countryName: String
    public var flagEmoji: String
    public var grid: String
    public var deltaFrequencyHz: UInt32
    public var snr: Int32
    public var mode: String
    public var interlocutor: String
    public var lastSeen: Date
    public var rawDecode: WSJTXLiveDecode?

    public init(
        id: UUID = UUID(),
        callsign: String,
        countryName: String = "",
        flagEmoji: String = "🌐",
        grid: String = "",
        deltaFrequencyHz: UInt32 = 1500,
        snr: Int32 = -10,
        mode: String = "FT8",
        interlocutor: String = "",
        lastSeen: Date = Date(),
        rawDecode: WSJTXLiveDecode? = nil
    ) {
        self.id = id
        self.callsign = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.countryName = countryName
        self.flagEmoji = flagEmoji
        self.grid = grid.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.deltaFrequencyHz = deltaFrequencyHz
        self.snr = snr
        self.mode = mode
        self.interlocutor = interlocutor.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastSeen = lastSeen
        self.rawDecode = rawDecode
    }
}

// MARK: - Main Wait & Pounce Engine

@MainActor
public final class WaitAndPounceEngine: ObservableObject {
    public static let shared = WaitAndPounceEngine()

    // MARK: - Published State
    @Published public private(set) var status: WaitAndPounceStatus = .idle
    @Published public private(set) var activeTarget: PounceTarget? = nil
    @Published public private(set) var currentAttempt: Int = 0
    @Published public private(set) var secondsRemainingInCycle: Double = 15.0
    @Published public private(set) var cycleProgressPercentage: Double = 0.0
    @Published public private(set) var lastEventMessage: String = "Wait & Pounce ready"
    @Published public private(set) var eventLog: [String] = []

    // MARK: - User Configuration
    @Published public var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "waitAndPounceEnabled")
            if !isEnabled {
                haltAndDisarm()
            } else if activeTarget != nil {
                status = .hunting(mode: huntMode.shortLabel)
            }
        }
    }

    @Published public var huntMode: TargetHuntMode = .manualWatchlist {
        didSet {
            UserDefaults.standard.set(huntMode.rawValue, forKey: "waitAndPounceHuntMode")
        }
    }

    @Published public var frequencyMode: PounceFrequencyMode = .autoClearSplit {
        didSet {
            UserDefaults.standard.set(frequencyMode.rawValue, forKey: "waitAndPounceFreqMode")
        }
    }

    @Published public var maxAttempts: Int = 3 {
        didSet {
            UserDefaults.standard.set(maxAttempts, forKey: "waitAndPounceMaxAttempts")
        }
    }

    @Published public var watchlistText: String = "" {
        didSet {
            UserDefaults.standard.set(watchlistText, forKey: "waitAndPounceWatchlist")
            rebuildWatchlist()
        }
    }

    @Published public var splitAudioOffsetHz: Int = 2100 {
        didSet {
            UserDefaults.standard.set(splitAudioOffsetHz, forKey: "waitAndPounceSplitOffset")
        }
    }

    @Published public var voiceAnnouncementsEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(voiceAnnouncementsEnabled, forKey: "waitAndPounceVoiceEnabled")
        }
    }

    // MARK: - Internal Engine Properties
    private var watchlistCalls: Set<String> = []
    private var cycleTimer: DispatchSourceTimer?
    private var myCallsign: String = ""
    private var myGrid: String = ""
    private var activeBand: String = "20M"
    private var targetArmScheduled: Bool = false
    private var lastDecodedCycleTime: Date = Date()
    private var recentOccupiedBins: Set<UInt32> = [] // Used for auto-clear frequency calculation

    // MARK: - Initializer

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "waitAndPounceEnabled")
        if let modeRaw = UserDefaults.standard.string(forKey: "waitAndPounceHuntMode"),
           let mode = TargetHuntMode(rawValue: modeRaw) {
            self.huntMode = mode
        }
        if let fqRaw = UserDefaults.standard.string(forKey: "waitAndPounceFreqMode"),
           let fq = PounceFrequencyMode(rawValue: fqRaw) {
            self.frequencyMode = fq
        }
        let att = UserDefaults.standard.integer(forKey: "waitAndPounceMaxAttempts")
        self.maxAttempts = (1...5).contains(att) ? att : 3
        self.watchlistText = UserDefaults.standard.string(forKey: "waitAndPounceWatchlist") ?? ""
        let off = UserDefaults.standard.integer(forKey: "waitAndPounceSplitOffset")
        self.splitAudioOffsetHz = off > 0 ? off : 2100
        self.voiceAnnouncementsEnabled = UserDefaults.standard.object(forKey: "waitAndPounceVoiceEnabled") as? Bool ?? true

        rebuildWatchlist()
        startPrecisionCycleTimer()
    }

    deinit {
        cycleTimer?.cancel()
    }

    // MARK: - Context Updates

    public func updateStationContext(callsign: String, grid: String, band: String) {
        self.myCallsign = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.myGrid = grid.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !band.isEmpty {
            self.activeBand = band.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public func setTarget(
        callsign: String,
        grid: String = "",
        deltaHz: UInt32 = 1500,
        mode: String = "FT8",
        interlocutor: String = "",
        snr: Int32 = -10,
        rawDecode: WSJTXLiveDecode? = nil
    ) {
        let clean = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        let dxcc = DXCCDatabase.resolve(callsign: clean)
        let target = PounceTarget(
            callsign: clean,
            countryName: dxcc.entityName,
            flagEmoji: dxcc.flagEmoji,
            grid: grid,
            deltaFrequencyHz: deltaHz,
            snr: snr,
            mode: mode,
            interlocutor: interlocutor,
            lastSeen: Date(),
            rawDecode: rawDecode
        )

        self.activeTarget = target
        self.currentAttempt = 0
        self.isEnabled = true
        self.status = .hunting(mode: "Target: \(clean)")
        self.logEvent("🎯 Target set: \(clean) (\(dxcc.entityName)) on \(deltaHz) Hz")

        if voiceAnnouncementsEnabled {
            DigitalAudioAlertEngine.shared.announceWaitAndPounceTargetAcquired(callsign: clean, country: dxcc.entityName)
        }
    }

    public func clearTarget() {
        self.activeTarget = nil
        self.currentAttempt = 0
        self.targetArmScheduled = false
        if isEnabled {
            self.status = .hunting(mode: huntMode.shortLabel)
        } else {
            self.status = .idle
        }
        self.logEvent("Target cleared")
    }

    // MARK: - Watchlist Management

    public func addToWatchlist(_ callsign: String) {
        let clean = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var list = watchlistCalls
        list.insert(clean)
        self.watchlistText = list.sorted().joined(separator: ", ")
    }

    public func removeFromWatchlist(_ callsign: String) {
        let clean = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var list = watchlistCalls
        list.remove(clean)
        self.watchlistText = list.sorted().joined(separator: ", ")
    }

    private func rebuildWatchlist() {
        let items = watchlistText
            .components(separatedBy: CharacterSet(charactersIn: ",; \n\t"))
            .map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.watchlistCalls = Set(items)
    }

    // MARK: - Real-Time Decode Processing

    public func processDecodes(_ decodes: [WSJTXLiveDecode], activeBand: String) {
        guard !decodes.isEmpty else { return }
        self.activeBand = activeBand.isEmpty ? "20M" : activeBand.uppercased()

        // Cache occupied audio passband bins for smart split calculation
        var occupied: Set<UInt32> = []
        for d in decodes {
            occupied.insert(d.deltaFrequencyHz)
        }
        self.recentOccupiedBins = occupied

        // 1. Check if our target responded to US (Instant QSO Handover)
        if let target = activeTarget {
            for decode in decodes {
                if decode.callerCallsign == target.callsign && decode.isDirectedToMe(myCall: myCallsign) {
                    handleQSOEngaged(with: target, decode: decode)
                    return
                }
            }
        }

        // 2. If hunting without an active target, see if any decode matches auto-hunt or watchlist
        if activeTarget == nil && isEnabled {
            evaluateNewTargetCandidates(from: decodes)
        }

        // 3. If we have an active target, evaluate target status and QSO lifecycle
        if let target = activeTarget {
            evaluateActiveTarget(target, in: decodes)
        }
    }

    private func handleQSOEngaged(with target: PounceTarget, decode: WSJTXLiveDecode) {
        self.status = .engaged(target: target.callsign, snr: decode.snr)
        self.logEvent("🎉 SUCCESS! \(target.callsign) responded to US! Handing over to Auto-Sequence.")

        if voiceAnnouncementsEnabled {
            DigitalAudioAlertEngine.shared.announceWaitAndPounceEngaged(callsign: target.callsign)
        }

        // Send reply to ensure WSJT-X / SDR-Control auto-sequence locks onto the contact
        sendReplyPacket(for: target, decode: decode)

        // Post notification so call roster & target queue know we are now in active QSO
        NotificationCenter.default.post(
            name: .init("WaitAndPounceDidEngageTarget"),
            object: nil,
            userInfo: ["callsign": target.callsign, "snr": decode.snr]
        )

        // Reset pounce counter and disarm hunt after contact is secured
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else { return }
            if case .engaged = self.status {
                self.clearTarget()
            }
        }
    }

    private func evaluateNewTargetCandidates(from decodes: [WSJTXLiveDecode]) {
        for decode in decodes {
            let caller = decode.callerCallsign.uppercased()
            guard !caller.isEmpty && caller != myCallsign else { continue }

            var isCandidate = false
            var reason = ""

            switch huntMode {
            case .manualWatchlist:
                if watchlistCalls.contains(caller) {
                    isCandidate = true
                    reason = "Watchlist Match"
                }
            case .autoNewDXCC:
                if let entry = DigitalCallRosterEngine.shared.entries.first(where: { $0.callsign == caller }),
                   entry.status == .newDXCC {
                    isCandidate = true
                    reason = "All-Time New DXCC"
                }
            case .autoNewBand:
                if let entry = DigitalCallRosterEngine.shared.entries.first(where: { $0.callsign == caller }),
                   entry.status == .newBand {
                    isCandidate = true
                    reason = "New Band DXCC"
                }
            case .autoNewGrid:
                if let entry = DigitalCallRosterEngine.shared.entries.first(where: { $0.callsign == caller }),
                   entry.status == .newGrid {
                    isCandidate = true
                    reason = "New Grid"
                }
            case .apexTarget:
                if let apex = DigitalCallRosterEngine.shared.apexTarget, apex.callsign == caller {
                    isCandidate = true
                    reason = "Apex Tactical Target"
                }
            }

            if isCandidate {
                self.setTarget(
                    callsign: caller,
                    grid: decode.grid,
                    deltaHz: decode.deltaFrequencyHz,
                    mode: decode.mode,
                    interlocutor: decode.targetCallsign,
                    snr: decode.snr,
                    rawDecode: decode
                )
                self.logEvent("⚡️ Candidate auto-acquired: \(caller) (\(reason))")
                return
            }
        }
    }

    private func evaluateActiveTarget(_ target: PounceTarget, in decodes: [WSJTXLiveDecode]) {
        // Find decodes where target is transmitting
        let targetTxDecodes = decodes.filter { $0.callerCallsign == target.callsign }

        if let tx = targetTxDecodes.first {
            // Target is actively transmitting this cycle!
            var updated = target
            updated.snr = tx.snr
            updated.deltaFrequencyHz = tx.deltaFrequencyHz
            updated.lastSeen = Date()
            updated.rawDecode = tx
            if !tx.targetCallsign.isEmpty {
                updated.interlocutor = tx.targetCallsign
            }
            self.activeTarget = updated

            let msg = tx.message.uppercased()

            // A. Target sent RR73, 73, or is calling CQ -> IMMEDIATE ARMED TRIGGER!
            if isQSOCompletionMessage(msg) || tx.isCQ {
                armForPounce(target: updated, rawDecode: tx, triggerReason: tx.isCQ ? "CQ Call" : "Sent RR73 / 73")
                return
            }

            // B. Target is in the middle of a QSO exchanging reports
            let interlocutor = updated.interlocutor.isEmpty ? "DX Station" : updated.interlocutor
            let stage = msg.contains("R-") || msg.contains("R+") ? "Report with R" : "Initial Report"
            self.status = .tracking(target: updated.callsign, interlocutor: interlocutor, stage: stage, snr: tx.snr, deltaHz: tx.deltaFrequencyHz)
            self.logEvent("👀 Tracking \(updated.callsign) in QSO with \(interlocutor) (\(stage), \(tx.snr) dB)")
            return
        }

        // Target didn't transmit in this slot. Did someone transmit TO our target?
        let callingTargetDecodes = decodes.filter { $0.targetCallsign == target.callsign }
        if let calling = callingTargetDecodes.first {
            var updated = target
            updated.interlocutor = calling.callerCallsign
            self.activeTarget = updated

            let msg = calling.message.uppercased()
            if msg.contains("73") || msg.contains("RR73") {
                // Partner sent 73 to target! Target will send RR73 or listen in the following slot!
                self.status = .tracking(target: target.callsign, interlocutor: calling.callerCallsign, stage: "Partner Sent 73", snr: target.snr, deltaHz: target.deltaFrequencyHz)
                self.logEvent("⏳ Partner \(calling.callerCallsign) sent 73 to \(target.callsign) — expecting target wrap-up")
            } else {
                self.status = .tracking(target: target.callsign, interlocutor: calling.callerCallsign, stage: "Partner Calling", snr: target.snr, deltaHz: target.deltaFrequencyHz)
            }
        }
    }

    private func isQSOCompletionMessage(_ msg: String) -> Bool {
        let tokens = msg.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for token in tokens {
            let u = token.uppercased()
            if u == "RR73" || u == "73" || u == "RRR" {
                return true
            }
        }
        return false
    }

    // MARK: - Arming & Pounce Execution

    private func armForPounce(target: PounceTarget, rawDecode: WSJTXLiveDecode, triggerReason: String) {
        guard isEnabled else { return }

        self.targetArmScheduled = true
        let deltaHz = calculateTxFrequency(for: target)
        self.status = .armed(target: target.callsign, deltaHz: deltaHz, secondsRemaining: secondsRemainingInCycle)
        self.logEvent("⚡️ ARMED TO POUNCE on \(target.callsign) (\(triggerReason)) on \(deltaHz) Hz!")

        if voiceAnnouncementsEnabled {
            DigitalAudioAlertEngine.shared.announceWaitAndPounceArmed(callsign: target.callsign, band: activeBand)
        }
    }

    private func calculateTxFrequency(for target: PounceTarget) -> UInt32 {
        switch frequencyMode {
        case .simplex:
            return target.deltaFrequencyHz
        case .holdTxFreq:
            let statusTx = WSJTXListener.sharedLastTxDF()
            return statusTx > 0 ? statusTx : UInt32(splitAudioOffsetHz)
        case .autoClearSplit:
            return findClearAudioPassbandOffset(near: UInt32(splitAudioOffsetHz), excluding: target.deltaFrequencyHz)
        }
    }

    private func findClearAudioPassbandOffset(near preferred: UInt32, excluding targetHz: UInt32) -> UInt32 {
        // Look for a 100 Hz clear slot between 600 Hz and 2600 Hz
        let candidates: [UInt32] = [
            preferred,
            2100, 2250, 2400, 1950, 1800, 1650, 2550, 1350, 1100, 850
        ]

        for cand in candidates {
            if abs(Int(cand) - Int(targetHz)) < 60 { continue }
            // Check if cand is at least 60 Hz away from any active signal
            let hasCollision = recentOccupiedBins.contains { bin in
                abs(Int(bin) - Int(cand)) < 55
            }
            if !hasCollision {
                return cand
            }
        }

        return preferred
    }

    // MARK: - Precision 15-Second Slot Synchronization

    private func startPrecisionCycleTimer() {
        cycleTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            let now = Date().timeIntervalSince1970
            let period = 15.0 // FT8 cycle
            let remainder = now.truncatingRemainder(dividingBy: period)
            let remaining = period - remainder
            let progress = remainder / period

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.secondsRemainingInCycle = remaining
                self.cycleProgressPercentage = progress

                // Update countdown in armed state
                if case .armed(let tgt, let hz, _) = self.status {
                    self.status = .armed(target: tgt, deltaHz: hz, secondsRemaining: remaining)
                }

                // Fire dispatch 250ms prior to the next slot (:00, :15, :30, :45)
                if remaining <= 0.30 && remaining >= 0.12 && self.targetArmScheduled {
                    self.executePounceDispatch()
                }
            }
        }
        timer.resume()
        self.cycleTimer = timer
    }

    private func executePounceDispatch() {
        guard let target = activeTarget, isEnabled else {
            self.targetArmScheduled = false
            return
        }

        self.targetArmScheduled = false
        self.currentAttempt += 1

        let txHz = calculateTxFrequency(for: target)
        self.status = .pouncing(target: target.callsign, attempt: currentAttempt, maxAttempts: maxAttempts, deltaHz: txHz)
        self.logEvent("🚀 DISPATCHED POUNCE to \(target.callsign) [Try \(currentAttempt)/\(maxAttempts)] on \(txHz) Hz")

        // 1. Dispatch WSJT-X / SDR-Control Reply packet
        if let raw = target.rawDecode {
            sendReplyPacket(for: target, decode: raw, overrideDeltaHz: txHz)
        } else {
            // Synthetic reply
            let synthetic = WSJTXLiveDecode(
                sourceID: "WSJT-X",
                isNew: true,
                timeMillis: UInt32(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) * 1000),
                snr: target.snr,
                deltaTimeSec: 0.1,
                deltaFrequencyHz: target.deltaFrequencyHz,
                mode: target.mode,
                message: "CQ \(target.callsign) \(target.grid)",
                lowConfidence: false,
                offAir: false,
                callerCallsign: target.callsign,
                targetCallsign: "",
                grid: target.grid,
                report: ""
            )
            sendReplyPacket(for: target, decode: synthetic, overrideDeltaHz: txHz)
        }

        // 2. Also trigger internal FT8 modem if active
        NotificationCenter.default.post(
            name: .init("WaitAndPounceDidTriggerPounce"),
            object: nil,
            userInfo: [
                "callsign": target.callsign,
                "grid": target.grid,
                "deltaHz": txHz,
                "mode": target.mode
            ]
        )

        // 3. Check retry limit after the cycle finishes
        DispatchQueue.main.asyncAfter(deadline: .now() + 14.5) { [weak self] in
            guard let self = self else { return }
            if case .pouncing(let tCall, let att, let maxAtt, _) = self.status, tCall == target.callsign {
                if att >= maxAtt {
                    self.status = .cooldown(target: target.callsign, reason: "Max attempts (\(maxAtt)) reached")
                    self.logEvent("⚠️ Max attempts reached for \(target.callsign). Entering cooldown.")
                    if self.voiceAnnouncementsEnabled {
                        DigitalAudioAlertEngine.shared.announceWaitAndPounceExhausted(callsign: target.callsign)
                    }
                } else {
                    self.status = .tracking(target: target.callsign, interlocutor: target.interlocutor, stage: "Awaiting Reply", snr: target.snr, deltaHz: txHz)
                }
            }
        }
    }

    private func sendReplyPacket(for target: PounceTarget, decode: WSJTXLiveDecode, overrideDeltaHz: UInt32? = nil) {
        var modifiedDecode = decode
        if let customHz = overrideDeltaHz {
            modifiedDecode = WSJTXLiveDecode(
                id: decode.id,
                sourceID: decode.sourceID,
                isNew: decode.isNew,
                timeMillis: decode.timeMillis,
                snr: decode.snr,
                deltaTimeSec: decode.deltaTimeSec,
                deltaFrequencyHz: customHz,
                mode: decode.mode,
                message: decode.message,
                lowConfidence: decode.lowConfidence,
                offAir: decode.offAir,
                receivedAt: decode.receivedAt,
                callerCallsign: decode.callerCallsign,
                targetCallsign: decode.targetCallsign,
                grid: decode.grid,
                report: decode.report,
                port: decode.port,
                sliceLabel: decode.sliceLabel
            )
        }

        // Dispatch via WSJTXListener
        NotificationCenter.default.post(
            name: .init("WaitAndPounceSendWSJTXReply"),
            object: nil,
            userInfo: ["decode": modifiedDecode]
        )
    }

    // MARK: - Safety & Emergency Halt

    public func haltAndDisarm() {
        self.targetArmScheduled = false
        self.status = .idle
        self.logEvent("🛑 EMERGENCY HALT: Transmission disarmed")

        // Halt WSJT-X
        NotificationCenter.default.post(name: .init("WaitAndPounceHaltTx"), object: nil)
    }

    private func logEvent(_ msg: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let full = "[\(timestamp)] \(msg)"
        self.lastEventMessage = msg
        self.eventLog.insert(full, at: 0)
        if self.eventLog.count > 50 {
            self.eventLog = Array(self.eventLog.prefix(50))
        }
    }
}

// MARK: - Helper Extension for Status Tx DF

extension WSJTXListener {
    fileprivate static func sharedLastTxDF() -> UInt32 {
        // Default to standard passband offset
        return 2100
    }
}
