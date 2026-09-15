//
//  ContestRateMatrixEngine.swift
//  YAAM
//
//  Contest Rate Acceleration & Multiplier 2D Matrix Engine.
//  Computes rolling 10-min and 60-min QSO rates, peak hourly rate, consecutive streaks,
//  operating vs. break time, and band-by-band multiplier distribution.
//

import Combine
import Foundation

public struct BandMultiplierSummary: Identifiable, Sendable, Equatable {
    public var id: String { band }
    public let band: String
    public var qsoCount: Int
    public var dxccCount: Int
    public var zoneCount: Int
    public var points: Int

    public init(
        band: String,
        qsoCount: Int = 0,
        dxccCount: Int = 0,
        zoneCount: Int = 0,
        points: Int = 0
    ) {
        self.band = band
        self.qsoCount = qsoCount
        self.dxccCount = dxccCount
        self.zoneCount = zoneCount
        self.points = points
    }
}

@MainActor
public final class ContestRateMatrixEngine: ObservableObject {
    public static let shared = ContestRateMatrixEngine()

    // Published Metrics
    @Published public var rolling10MinRate: Int = 0
    @Published public var rolling60MinRate: Int = 0
    @Published public var peakHourlyRate: Int = 0
    @Published public var totalQSOs: Int = 0
    @Published public var totalDXCCMultipliers: Int = 0
    @Published public var totalZoneMultipliers: Int = 0
    @Published public var projected24hScore: Int = 0
    @Published public var currentStreak: Int = 0
    @Published public var totalOperatingMinutes: Int = 0
    @Published public var bandSummaries: [BandMultiplierSummary] = []

    public var totalPoints: Int {
        bandSummaries.reduce(0) { $0 + $1.points }
    }

    public var totalMultipliers: Int {
        totalDXCCMultipliers + totalZoneMultipliers
    }

    public var currentCabrilloScore: Int {
        totalPoints * max(1, totalMultipliers)
    }

    public static let supportedBands = ["160M", "80M", "40M", "20M", "15M", "10M", "6M"]

    private static let adifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd HHmmss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private init() {
        reset()
    }

    public func reset() {
        rolling10MinRate = 0
        rolling60MinRate = 0
        peakHourlyRate = 0
        totalQSOs = 0
        totalDXCCMultipliers = 0
        totalZoneMultipliers = 0
        projected24hScore = 0
        currentStreak = 0
        totalOperatingMinutes = 0
        bandSummaries = Self.supportedBands.map { BandMultiplierSummary(band: $0) }
    }

    /// Primary analysis method computing all contest rate and multiplier metrics.
    func recalculate(qsoRecords: [QSORecordModel], contestStartTime: Date? = nil) {
        guard !qsoRecords.isEmpty else {
            reset()
            return
        }

        self.totalQSOs = qsoRecords.count

        // Parse and sort timestamps
        let now = Date()
        var timestamps: [Date] = []
        timestamps.reserveCapacity(qsoRecords.count)

        for q in qsoRecords {
            if let dateStr = q.fields["QSO_DATE"], let rawTime = q.fields["TIME_ON"] {
                let cleanTime = rawTime.count == 4 ? rawTime + "00" : rawTime
                if let d = Self.adifDateFormatter.date(from: "\(dateStr) \(cleanTime)") {
                    timestamps.append(d)
                    continue
                }
            }
            // Fallback to now if no explicit date fields
            timestamps.append(now)
        }
        timestamps.sort()

        // 1. Rolling 10-Min and 60-Min Rates
        let tenMinAgo = now.addingTimeInterval(-600)
        let sixtyMinAgo = now.addingTimeInterval(-3600)

        let last10MinQSOs = timestamps.filter { $0 >= tenMinAgo }.count
        let last60MinQSOs = timestamps.filter { $0 >= sixtyMinAgo }.count

        self.rolling10MinRate = last10MinQSOs * 6
        self.rolling60MinRate = last60MinQSOs

        if self.rolling60MinRate > self.peakHourlyRate {
            self.peakHourlyRate = self.rolling60MinRate
        }

        // 2. Consecutive Streak (QSOs within 10 min gaps)
        var streak = 0
        if let last = timestamps.last {
            if now.timeIntervalSince(last) <= 900 { // Active within 15 mins
                streak = 1
                for i in stride(from: timestamps.count - 1, through: 1, by: -1) {
                    let diff = timestamps[i].timeIntervalSince(timestamps[i - 1])
                    if diff <= 600 {
                        streak += 1
                    } else {
                        break
                    }
                }
            }
        }
        self.currentStreak = streak

        // 3. Operating Time calculation (sum of intervals <= 30 min)
        var operatingSecs: TimeInterval = 0
        for i in 1..<timestamps.count {
            let diff = timestamps[i].timeIntervalSince(timestamps[i - 1])
            if diff <= 1800 { // Max 30 min between QSOs counts as on-air time
                operatingSecs += diff
            }
        }
        self.totalOperatingMinutes = max(1, Int(operatingSecs / 60.0))

        // 4. Band x Multiplier Breakdown
        var bandMap: [String: (qsos: Int, dxcc: Set<String>, zones: Set<Int>, points: Int)] = [:]
        for b in Self.supportedBands {
            bandMap[b] = (0, Set<String>(), Set<Int>(), 0)
        }

        var globalDXCC = Set<String>()
        var globalZones = Set<Int>()

        for q in qsoRecords {
            let band = (q.fields["BAND"] ?? "20M").uppercased()
            let call = q.fields["CALL"] ?? ""
            let dxcc = DXCCDatabase.resolve(callsign: call)
            let zone = Int(q.fields["CQZ"] ?? "") ?? dxcc.cqZone

            if !dxcc.entityName.isEmpty && dxcc.entityName != "Unknown" {
                globalDXCC.insert(dxcc.entityName)
            }
            if zone > 0 {
                globalZones.insert(zone)
            }

            if var current = bandMap[band] {
                current.qsos += 1
                if !dxcc.entityName.isEmpty && dxcc.entityName != "Unknown" {
                    current.dxcc.insert(dxcc.entityName)
                }
                if zone > 0 {
                    current.zones.insert(zone)
                }
                current.points += 3 // Default 3 pts per CW QSO
                bandMap[band] = current
            }
        }

        self.totalDXCCMultipliers = globalDXCC.count
        self.totalZoneMultipliers = globalZones.count

        self.bandSummaries = Self.supportedBands.map { b in
            let data = bandMap[b] ?? (0, Set<String>(), Set<Int>(), 0)
            return BandMultiplierSummary(
                band: b,
                qsoCount: data.qsos,
                dxccCount: data.dxcc.count,
                zoneCount: data.zones.count,
                points: data.points
            )
        }

        // 5. Projected 24h score
        let totalMults = max(1, self.totalDXCCMultipliers + self.totalZoneMultipliers)
        let totalPts = self.bandSummaries.reduce(0) { $0 + $1.points }
        let rawScore = totalPts * totalMults
        let elapsedHours = max(0.1, Double(self.totalOperatingMinutes) / 60.0)
        let projected = Double(rawScore) * (24.0 / max(1.0, elapsedHours))
        self.projected24hScore = Int(min(Double(Int.max), projected))
    }
}
