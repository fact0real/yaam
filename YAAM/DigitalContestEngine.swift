//
//  DigitalContestEngine.swift
//  YAAM
//
//  Gold Standard Digital Contest Engine for FT8 & FT4 on macOS.
//  Implements official rules, real-time multiplier detection, distance-based scoring,
//  rate meter (QSOs/hr), and dupe prevention for CQ WW Digi and ARRL Digi contests.
//

import Combine
import Foundation
import SwiftUI
#if canImport(FT8808Engine)
import FT8808Engine
#else
public enum SlotParity: Int, Sendable, CaseIterable {
    case even = 0
    case odd = 1

    public var toggled: SlotParity {
        self == .even ? .odd : .even
    }
}
#endif

// MARK: - Digital Slot Clock (FT8 15.0s / FT4 7.5s)

public enum DigitalSlotClock {
    public static func slotIndex(at time: Date, slotSeconds: Double = 15.0) -> Int {
        Int((time.timeIntervalSince1970 / slotSeconds).rounded(.down))
    }

    public static func parity(at time: Date, slotSeconds: Double = 15.0) -> SlotParity {
        slotIndex(at: time, slotSeconds: slotSeconds).isMultiple(of: 2) ? .even : .odd
    }

    public static func nextSlotStart(parity: SlotParity, after time: Date, slotSeconds: Double = 15.0) -> Date {
        var idx = slotIndex(at: time, slotSeconds: slotSeconds) + 1
        while idx % 2 != parity.rawValue { idx += 1 }
        return Date(timeIntervalSince1970: Double(idx) * slotSeconds)
    }

    public static func secondsUntilNextSlot(parity: SlotParity, after time: Date, slotSeconds: Double = 15.0) -> Double {
        nextSlotStart(parity: parity, after: time, slotSeconds: slotSeconds).timeIntervalSince(time)
    }
}

// MARK: - Maidenhead Grid Distance Calculation

public nonisolated func calculateMaidenheadDistanceKm(grid1: String, grid2: String) -> Double? {
    func parseGrid(_ grid: String) -> (lat: Double, lon: Double)? {
        let clean = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 4 else { return nil }
        let chars = Array(clean)
        guard chars[0] >= "A" && chars[0] <= "R",
              chars[1] >= "A" && chars[1] <= "R",
              chars[2] >= "0" && chars[2] <= "9",
              chars[3] >= "0" && chars[3] <= "9" else { return nil }
        let lonField = Double(chars[0].asciiValue! - Character("A").asciiValue!) * 20.0 - 180.0
        let latField = Double(chars[1].asciiValue! - Character("A").asciiValue!) * 10.0 - 90.0
        let lonSquare = Double(chars[2].asciiValue! - Character("0").asciiValue!) * 2.0
        let latSquare = Double(chars[3].asciiValue! - Character("0").asciiValue!) * 1.0
        var lon = lonField + lonSquare + 1.0
        var lat = latField + latSquare + 0.5
        if clean.count >= 6, chars[4] >= "A" && chars[4] <= "X", chars[5] >= "A" && chars[5] <= "X" {
            let lonSub = Double(chars[4].asciiValue! - Character("A").asciiValue!) * (5.0 / 60.0)
            let latSub = Double(chars[5].asciiValue! - Character("A").asciiValue!) * (2.5 / 60.0)
            lon = lonField + lonSquare + lonSub + (2.5 / 60.0)
            lat = latField + latSquare + latSub + (1.25 / 60.0)
        }
        return (lat, lon)
    }

    guard let c1 = parseGrid(grid1), let c2 = parseGrid(grid2) else { return nil }
    let earthRadiusKm = 6371.0
    let dLat = (c2.lat - c1.lat) * .pi / 180.0
    let dLon = (c2.lon - c1.lon) * .pi / 180.0
    let lat1Rad = c1.lat * .pi / 180.0
    let lat2Rad = c2.lat * .pi / 180.0
    let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earthRadiusKm * c
}

// MARK: - Contest Types

public enum DigitalContestType: String, CaseIterable, Identifiable, Sendable, Codable {
    case cqWWDigi = "CQ WW Digi DX Contest"
    case arrlRoundup = "ARRL Digi / RTTY Roundup"
    case generalContest = "General Digital Contest"

    public var id: String { rawValue }

    public var shortCode: String {
        switch self {
        case .cqWWDigi: return "CQ-WW-DIGI"
        case .arrlRoundup: return "ARRL-DIGI"
        case .generalContest: return "DIGI-TEST"
        }
    }

    public var exchangeDescription: String {
        switch self {
        case .cqWWDigi: return "4-char Grid (e.g. KM32)"
        case .arrlRoundup: return "Serial / State (e.g. 001 or CA)"
        case .generalContest: return "Serial / Grid / Zone"
        }
    }

    public var bandsSupported: [String] {
        ["160m", "80m", "40m", "20m", "15m", "10m", "6m"]
    }
}

// MARK: - Decoded Contest Status

public enum DecodedContestStatus: Equatable, Sendable {
    case none
    case newMultiplier(badge: String, points: Int, description: String)
    case newQSO(points: Int)
    case dupe

    public var isMultiplier: Bool {
        if case .newMultiplier = self { return true }
        return false
    }

    public var isDupe: Bool {
        self == .dupe
    }

    public var points: Int {
        switch self {
        case .newMultiplier(_, let pts, _): return pts
        case .newQSO(let pts): return pts
        case .dupe, .none: return 0
        }
    }

    public var badgeLabel: String {
        switch self {
        case .newMultiplier(let badge, _, _): return badge
        case .newQSO(let pts): return "+\(pts) PTS"
        case .dupe: return "DUPE"
        case .none: return ""
        }
    }

    public var badgeColor: Color {
        switch self {
        case .newMultiplier: return Color(red: 1.0, green: 0.72, blue: 0.15) // Vibrant Amber/Gold
        case .newQSO: return Color(red: 0.18, green: 0.82, blue: 0.45) // Emerald Green
        case .dupe: return Color.secondary.opacity(0.4) // Dimmed Slate
        case .none: return Color.clear
        }
    }
}

// MARK: - Contest QSO Record

public struct ContestQSOEntry: Identifiable, Sendable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let callsign: String
    public let band: String
    public let mode: String // "FT8" or "FT4"
    public let frequencyHz: UInt64
    public let sentReport: String
    public let rcvdReport: String
    public let sentExchange: String
    public let rcvdExchange: String
    public let grid: String?
    public let dxccEntity: String
    public let countryName: String
    public let countryFlag: String
    public let points: Int
    public let isGridMultiplier: Bool
    public let isDXCCMultiplier: Bool
    public let multiplierName: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        callsign: String,
        band: String,
        mode: String,
        frequencyHz: UInt64,
        sentReport: String,
        rcvdReport: String,
        sentExchange: String,
        rcvdExchange: String,
        grid: String?,
        dxccEntity: String,
        countryName: String,
        countryFlag: String,
        points: Int,
        isGridMultiplier: Bool,
        isDXCCMultiplier: Bool,
        multiplierName: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.callsign = callsign
        self.band = band
        self.mode = mode
        self.frequencyHz = frequencyHz
        self.sentReport = sentReport
        self.rcvdReport = rcvdReport
        self.sentExchange = sentExchange
        self.rcvdExchange = rcvdExchange
        self.grid = grid
        self.dxccEntity = dxccEntity
        self.countryName = countryName
        self.countryFlag = countryFlag
        self.points = points
        self.isGridMultiplier = isGridMultiplier
        self.isDXCCMultiplier = isDXCCMultiplier
        self.multiplierName = multiplierName
    }
}

// MARK: - Band Breakdown Summary

public struct ContestBandBreakdown: Identifiable, Sendable {
    public let band: String
    public let qsoCount: Int
    public let qsoPoints: Int
    public let gridFields: Set<String>
    public let dxccEntities: Set<String>
    public let otherMults: Set<String>

    public var id: String { band }
    public var gridMultCount: Int { gridFields.count }
    public var dxccMultCount: Int { dxccEntities.count }
    public var totalMults: Int { gridMultCount + dxccMultCount + otherMults.count }
}

// MARK: - Digital Contest Engine (Observable)

@MainActor
public final class DigitalContestEngine: ObservableObject {
    public static let shared = DigitalContestEngine()

    // Configuration
    @Published public var contestType: DigitalContestType = .cqWWDigi
    @Published public var isContestActive: Bool = false
    @Published public var contestTitle: String = "CQ WW Digi DX Contest"
    @Published public var myStationCall: String = ""
    @Published public var myStationGrid: String = ""
    @Published public var currentSerial: Int = 1

    // Real-Time Contest Score & Multipliers State
    @Published public private(set) var qsoLog: [ContestQSOEntry] = []
    @Published public private(set) var totalQSOs: Int = 0
    @Published public private(set) var totalPoints: Int = 0
    @Published public private(set) var totalGridMultipliers: Int = 0
    @Published public private(set) var totalDXCCMultipliers: Int = 0
    @Published public private(set) var totalMultipliers: Int = 0
    @Published public private(set) var claimedScore: Int = 0

    // Rate Meter (QSOs/hour)
    @Published public private(set) var rate10Min: Int = 0
    @Published public private(set) var rate60Min: Int = 0
    @Published public private(set) var peakRate: Int = 0

    // Trackers: band -> Set of worked keys
    private var workedCallsByBand: [String: Set<String>] = [:]
    private var workedGridFieldsByBand: [String: Set<String>] = [:]
    private var workedDXCCByBand: [String: Set<String>] = [:]
    private var workedOtherMultsByBand: [String: Set<String>] = [:]

    // Rate calculation timer
    private var rateTimer: Timer?

    public init() {
        startRateTimer()
    }

    deinit {
        rateTimer?.invalidate()
    }

    private func startRateTimer() {
        rateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recalculateRates()
            }
        }
    }

    // MARK: - Setup & Reset

    public func configureContest(type: DigitalContestType, myCall: String, myGrid: String) {
        self.contestType = type
        self.contestTitle = type.rawValue
        self.myStationCall = myCall.uppercased()
        self.myStationGrid = myGrid.uppercased()
        recalculateScore()
    }

    public func resetContestSession() {
        qsoLog.removeAll()
        workedCallsByBand.removeAll()
        workedGridFieldsByBand.removeAll()
        workedDXCCByBand.removeAll()
        workedOtherMultsByBand.removeAll()
        totalQSOs = 0
        totalPoints = 0
        totalGridMultipliers = 0
        totalDXCCMultipliers = 0
        totalMultipliers = 0
        claimedScore = 0
        rate10Min = 0
        rate60Min = 0
        peakRate = 0
        currentSerial = 1
    }

    // MARK: - Dupe & Multiplier Analysis for Decoded Stations

    public func analyzeDecodedStation(
        callsign: String,
        grid: String?,
        band: String
    ) -> DecodedContestStatus {
        guard isContestActive else { return .none }
        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCall.isEmpty, cleanCall != myStationCall else { return .none }

        let bandKey = normalizeBand(band)

        // 1. Dupe Check: A station may only be worked once per band
        if let worked = workedCallsByBand[bandKey], worked.contains(cleanCall) {
            return .dupe
        }

        // 2. Calculate potential QSO Points
        let cleanGrid = grid?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pts = calculatePoints(callerCall: cleanCall, callerGrid: cleanGrid, band: bandKey)

        // 3. Multiplier Check
        switch contestType {
        case .cqWWDigi:
            // Multiplier 1: 2-character grid field (e.g. KM, FN, PM)
            if let g = cleanGrid, g.count >= 2 {
                let field = String(g.prefix(2))
                let workedFields = workedGridFieldsByBand[bandKey] ?? []
                if !workedFields.contains(field) {
                    return .newMultiplier(
                        badge: "MULT: \(field)",
                        points: pts,
                        description: "New Grid Field on \(bandKey): \(field)"
                    )
                }
            }

            // Multiplier 2: DXCC entity once per band
            let info = DXCCDatabase.resolve(callsign: cleanCall)
            let dxccKey = info.entityName.isEmpty ? cleanCall : info.entityName
            let workedDXCC = workedDXCCByBand[bandKey] ?? []
            if !workedDXCC.contains(dxccKey) && dxccKey != "Unknown" {
                return .newMultiplier(
                    badge: "MULT: \(info.flagEmoji) \(info.countryCode.isEmpty ? String(dxccKey.prefix(4)) : info.countryCode)",
                    points: pts,
                    description: "New DXCC on \(bandKey): \(dxccKey)"
                )
            }

            return .newQSO(points: pts)

        case .arrlRoundup:
            // US State / Canadian Province / DXCC entity
            let info = DXCCDatabase.resolve(callsign: cleanCall)
            let dxccKey = info.entityName
            let isWVE = info.countryCode == "USA" || info.countryCode == "CAN" || cleanCall.hasPrefix("K") || cleanCall.hasPrefix("W") || cleanCall.hasPrefix("N") || cleanCall.hasPrefix("AA") || cleanCall.hasPrefix("VE") || cleanCall.hasPrefix("VA")

            if !isWVE {
                let workedDXCC = workedDXCCByBand[bandKey] ?? []
                if !workedDXCC.contains(dxccKey) && !dxccKey.isEmpty && dxccKey != "Unknown" {
                    return .newMultiplier(
                        badge: "MULT: \(info.countryCode)",
                        points: pts,
                        description: "New DXCC Entity on \(bandKey): \(dxccKey)"
                    )
                }
            }
            return .newQSO(points: pts)

        case .generalContest:
            return .newQSO(points: pts)
        }
    }

    // MARK: - Point Calculation Engine

    public func calculatePoints(callerCall: String, callerGrid: String?, band: String) -> Int {
        switch contestType {
        case .cqWWDigi:
            // CQ WW Digi Rules:
            // Points are based on distance between the two 4-character Maidenhead grid locators
            guard let g1 = myStationGrid.nilIfEmpty, let g2 = callerGrid, g1.count >= 4, g2.count >= 4 else {
                // Fallback if grid missing: 1 pt
                return 1
            }

            if String(g1.prefix(4)) == String(g2.prefix(4)) {
                return 1
            }

            if let distKm = calculateMaidenheadDistanceKm(grid1: g1, grid2: g2) {
                switch distKm {
                case ..<1500: return 1
                case 1500..<3000: return 2
                case 3000..<4500: return 3
                case 4500..<6000: return 4
                case 6000..<7500: return 5
                default: return 6
                }
            }
            return 1

        case .arrlRoundup, .generalContest:
            return 1
        }
    }

    // MARK: - Commit Contest QSO

    @discardableResult
    public func logContestQSO(
        callsign: String,
        band: String,
        mode: String,
        frequencyHz: UInt64,
        sentReport: String,
        rcvdReport: String,
        sentExchange: String,
        rcvdExchange: String,
        grid: String?
    ) -> ContestQSOEntry? {
        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCall.isEmpty else { return nil }
        let bandKey = normalizeBand(band)

        // Dupe check
        var workedCalls = workedCallsByBand[bandKey] ?? []
        if workedCalls.contains(cleanCall) {
            // Dupe QSO in contest log counts as 0 points
            let entry = ContestQSOEntry(
                callsign: cleanCall,
                band: bandKey,
                mode: mode,
                frequencyHz: frequencyHz,
                sentReport: sentReport,
                rcvdReport: rcvdReport,
                sentExchange: sentExchange,
                rcvdExchange: rcvdExchange,
                grid: grid,
                dxccEntity: "",
                countryName: "Duplicate",
                countryFlag: "⚪️",
                points: 0,
                isGridMultiplier: false,
                isDXCCMultiplier: false,
                multiplierName: nil
            )
            qsoLog.insert(entry, at: 0)
            return entry
        }

        workedCalls.insert(cleanCall)
        workedCallsByBand[bandKey] = workedCalls

        let dxccInfo = DXCCDatabase.resolve(callsign: cleanCall)
        let pts = calculatePoints(callerCall: cleanCall, callerGrid: grid, band: bandKey)

        var isGridMult = false
        var isDxccMult = false
        var multName: String?

        let cleanGrid = grid?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if contestType == .cqWWDigi {
            // Check grid multiplier
            if let g = cleanGrid, g.count >= 2 {
                let field = String(g.prefix(2))
                var workedFields = workedGridFieldsByBand[bandKey] ?? []
                if !workedFields.contains(field) {
                    workedFields.insert(field)
                    workedGridFieldsByBand[bandKey] = workedFields
                    isGridMult = true
                    multName = "Field: \(field)"
                }
            }

            // Check DXCC multiplier
            let dxccKey = dxccInfo.entityName
            if !dxccKey.isEmpty && dxccKey != "Unknown" {
                var workedDX = workedDXCCByBand[bandKey] ?? []
                if !workedDX.contains(dxccKey) {
                    workedDX.insert(dxccKey)
                    workedDXCCByBand[bandKey] = workedDX
                    isDxccMult = true
                    multName = multName == nil ? "DXCC: \(dxccKey)" : "\(multName!) + DXCC: \(dxccKey)"
                }
            }
        } else if contestType == .arrlRoundup {
            let dxccKey = dxccInfo.entityName
            if !dxccKey.isEmpty && dxccKey != "Unknown" && dxccInfo.countryCode != "USA" && dxccInfo.countryCode != "CAN" {
                var workedDX = workedDXCCByBand[bandKey] ?? []
                if !workedDX.contains(dxccKey) {
                    workedDX.insert(dxccKey)
                    workedDXCCByBand[bandKey] = workedDX
                    isDxccMult = true
                    multName = "DXCC: \(dxccKey)"
                }
            }
        }

        let entry = ContestQSOEntry(
            callsign: cleanCall,
            band: bandKey,
            mode: mode,
            frequencyHz: frequencyHz,
            sentReport: sentReport,
            rcvdReport: rcvdReport,
            sentExchange: sentExchange,
            rcvdExchange: rcvdExchange,
            grid: cleanGrid,
            dxccEntity: dxccInfo.entityName,
            countryName: dxccInfo.entityName,
            countryFlag: dxccInfo.flagEmoji,
            points: pts,
            isGridMultiplier: isGridMult,
            isDXCCMultiplier: isDxccMult,
            multiplierName: multName
        )

        qsoLog.insert(entry, at: 0)
        currentSerial += 1
        recalculateScore()
        recalculateRates()

        return entry
    }

    // MARK: - Score Recalculation

    public func recalculateScore() {
        var qCount = 0
        var pCount = 0

        for q in qsoLog {
            qCount += 1
            pCount += q.points
        }

        totalQSOs = qCount
        totalPoints = pCount

        var gMults = 0
        for (_, fields) in workedGridFieldsByBand {
            gMults += fields.count
        }
        totalGridMultipliers = gMults

        var dMults = 0
        for (_, dxEntities) in workedDXCCByBand {
            dMults += dxEntities.count
        }
        totalDXCCMultipliers = dMults

        var oMults = 0
        for (_, others) in workedOtherMultsByBand {
            oMults += others.count
        }

        totalMultipliers = gMults + dMults + oMults

        // Official Contest Scoring
        claimedScore = totalPoints * max(1, totalMultipliers)
    }

    // MARK: - Rate Calculations

    public func recalculateRates() {
        guard !qsoLog.isEmpty else {
            rate10Min = 0
            rate60Min = 0
            return
        }

        let now = Date()
        let tenMinsAgo = now.addingTimeInterval(-600)
        let sixtyMinsAgo = now.addingTimeInterval(-3600)

        var tenMinCount = 0
        var sixtyMinCount = 0

        for q in qsoLog {
            if q.timestamp >= tenMinsAgo {
                tenMinCount += 1
            }
            if q.timestamp >= sixtyMinsAgo {
                sixtyMinCount += 1
            } else {
                // qsoLog is sorted newest first, so once we cross sixtyMinsAgo we can break
                break
            }
        }

        let current10mRate = tenMinCount * 6
        rate10Min = current10mRate
        rate60Min = sixtyMinCount

        if current10mRate > peakRate {
            peakRate = current10mRate
        }
    }

    // MARK: - Band Breakdowns for Checksheets

    public var bandBreakdowns: [ContestBandBreakdown] {
        contestType.bandsSupported.map { band in
            let bandKey = normalizeBand(band)
            let qsos = qsoLog.filter { normalizeBand($0.band) == bandKey && $0.points > 0 }
            let points = qsos.reduce(0) { $0 + $1.points }
            let gridFields = workedGridFieldsByBand[bandKey] ?? []
            let dxccEntities = workedDXCCByBand[bandKey] ?? []
            let others = workedOtherMultsByBand[bandKey] ?? []

            return ContestBandBreakdown(
                band: band,
                qsoCount: qsos.count,
                qsoPoints: points,
                gridFields: gridFields,
                dxccEntities: dxccEntities,
                otherMults: others
            )
        }
    }

    // MARK: - Helper

    private func normalizeBand(_ band: String) -> String {
        let b = band.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if b.hasSuffix("m") { return b }
        return "\(b)m"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
