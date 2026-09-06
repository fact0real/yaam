//
//  BandmapEngine.swift
//  YAAM
//
//  Interactive Radio Bandmap Engine
//  Aggregates live DX spots, WSJT-X decodes, and DX Advisor alerts onto frequency spectrums.
//  Classifies spots by logbook award status (New DXCC, New Band, Unconfirmed, Worked) and
//  provides amateur band plan boundaries for 160M through 2M.
//

import Combine
import Foundation
import SwiftUI

public enum BandmapSpotStatus: String, CaseIterable, Identifiable, Sendable {
    case newDXCC = "New DXCC"
    case newBand = "New Band"
    case unconfirmed = "Unconfirmed"
    case worked = "Worked"

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .newDXCC: return .green
        case .newBand: return .blue
        case .unconfirmed: return .orange
        case .worked: return .secondary
        }
    }

    public var icon: String {
        switch self {
        case .newDXCC: return "star.circle.fill"
        case .newBand: return "bookmark.circle.fill"
        case .unconfirmed: return "questionmark.circle.fill"
        case .worked: return "checkmark.circle"
        }
    }
}

// MARK: - IARU Administrative Region
public enum IARURegion: String, CaseIterable, Identifiable, Sendable {
    case region1 = "Region 1 (EU / AF / ME)"
    case region2 = "Region 2 (Americas)"
    case region3 = "Region 3 (Asia / Pacific)"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .region1: return "IARU R1 (EP/EU)"
        case .region2: return "IARU R2 (US/AM)"
        case .region3: return "IARU R3 (JA/VK)"
        }
    }
}

// MARK: - Amateur Radio License Class
public enum LicenseClass: String, CaseIterable, Identifiable, Sendable {
    case extra = "Amateur Extra / CEPT Class 1"
    case general = "General / Intermediate"
    case technician = "Technician / Entry"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .extra: return "Extra / Full"
        case .general: return "General"
        case .technician: return "Technician"
        }
    }

    public var level: Int {
        switch self {
        case .extra: return 3
        case .general: return 2
        case .technician: return 1
        }
    }
}

public struct BandmapSpot: Identifiable, Sendable {
    public let id: UUID
    public let callsign: String
    public let frequencyKHz: Double
    public let band: String
    public let mode: String
    public let timestamp: Date
    public let dxccPrefix: String
    public let status: BandmapSpotStatus
    public let comment: String
    public let source: String
    public let snr: Int?

    public init(
        id: UUID = UUID(),
        callsign: String,
        frequencyKHz: Double,
        band: String,
        mode: String,
        timestamp: Date = Date(),
        dxccPrefix: String = "",
        status: BandmapSpotStatus = .newBand,
        comment: String = "",
        source: String = "DX Cluster",
        snr: Int? = nil
    ) {
        self.id = id
        self.callsign = callsign.uppercased()
        self.frequencyKHz = frequencyKHz
        self.band = band.uppercased()
        self.mode = mode.uppercased()
        self.timestamp = timestamp
        self.dxccPrefix = dxccPrefix
        self.status = status
        self.comment = comment
        self.source = source
        self.snr = snr
    }

    public var ageSeconds: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }

    public var ageMinutes: Int {
        max(0, Int(ageSeconds / 60.0))
    }

    public var isFresh: Bool {
        ageSeconds < 120.0
    }

    public var opacity: Double {
        if ageSeconds < 120.0 {
            return 1.0
        } else if ageSeconds < 600.0 {
            return 0.85
        } else if ageSeconds < 1200.0 {
            return 0.55
        } else if ageSeconds < 1800.0 {
            return 0.30
        } else {
            return 0.12
        }
    }
}

public struct BandPlanSegment: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let startKHz: Double
    public let endKHz: Double
    public let color: Color
    public let allowedModes: String
    public let minLicenseClass: LicenseClass
    public let region: IARURegion?

    public init(
        name: String,
        startKHz: Double,
        endKHz: Double,
        color: Color,
        allowedModes: String = "ALL",
        minLicenseClass: LicenseClass = .technician,
        region: IARURegion? = nil
    ) {
        self.name = name
        self.startKHz = startKHz
        self.endKHz = endKHz
        self.color = color
        self.allowedModes = allowedModes
        self.minLicenseClass = minLicenseClass
        self.region = region
    }

    public func isPermitted(for license: LicenseClass) -> Bool {
        return license.level >= minLicenseClass.level
    }
}

@MainActor
public final class BandmapEngine: ObservableObject {
    public static let shared = BandmapEngine()

    @Published public var spots: [BandmapSpot] = []
    @Published public var selectedBand: String = "20M"
    @Published public var spotLifetimeMinutes: Int = 30
    @Published public var filterNewOnly: Bool = false
    @Published public var searchText: String = ""
    @Published public var iaruRegion: IARURegion = .region1
    @Published public var licenseClass: LicenseClass = .extra

    // Dual VFO & Split Tracking
    @Published public var vfoAKHz: Double = 14074.0
    @Published public var vfoBKHz: Double = 14074.0
    @Published public var isSplitActive: Bool = false

    public var splitOffsetKHz: Double {
        vfoBKHz - vfoAKHz
    }

    public func setSplit(active: Bool, offsetKHz: Double = 2.0) {
        isSplitActive = active
        if active {
            vfoBKHz = vfoAKHz + offsetKHz
        }
    }

    private var cleanupTimer: Timer?

    public init() {
        populateDefaultSpots()
        startCleanupTimer()
    }

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pruneExpiredSpots()
            }
        }
    }

    // MARK: - Spot Ingestion

    func addSpot(
        callsign: String,
        frequencyKHz: Double,
        band: String,
        mode: String,
        comment: String = "",
        source: String = "DX Cluster",
        snr: Int? = nil,
        logRecords: [QSORecordModel] = []
    ) {
        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCall.isEmpty, frequencyKHz > 100.0 else { return }

        let resolvedBand = band.isEmpty ? (AmateurBandPlan.band(forMHz: frequencyKHz / 1000.0) ?? "20M") : band
        let status = classifyStatus(callsign: cleanCall, band: resolvedBand, mode: mode, logRecords: logRecords)
        let prefix = Self.extractPrefix(for: cleanCall)

        // Replace existing spot for same call on same band or add new
        spots.removeAll { $0.callsign == cleanCall && $0.band == resolvedBand }

        let newSpot = BandmapSpot(
            callsign: cleanCall,
            frequencyKHz: frequencyKHz,
            band: resolvedBand,
            mode: mode,
            timestamp: Date(),
            dxccPrefix: prefix,
            status: status,
            comment: comment,
            source: source,
            snr: snr
        )

        spots.insert(newSpot, at: 0)

        // Keep maximum 300 spots
        if spots.count > 300 {
            spots.removeLast(spots.count - 300)
        }
    }

    public func pruneExpiredSpots() {
        let maxAgeSec = Double(spotLifetimeMinutes * 60)
        spots.removeAll { $0.ageSeconds > maxAgeSec }
    }

    public func clearAllSpots() {
        spots.removeAll()
    }

    public func simulateDemoSpot(onBand band: String? = nil) {
        let targetBand = band ?? selectedBand
        let range = bandRangeKHz(for: targetBand)
        let span = range.upperBound - range.lowerBound
        let randomOffset = span > 0 ? Double.random(in: 0.1...0.9) * span : 50.0
        let freq = (range.lowerBound + randomOffset).rounded()

        let demoCalls = [
            ("TO7DL", "Mayotte DXpedition", "CW", BandmapSpotStatus.newDXCC),
            ("VU4N", "Andaman & Nicobar", "CW", BandmapSpotStatus.newDXCC),
            ("EP2LMA", "Tehran Calling CQ", "FT8", BandmapSpotStatus.newBand),
            ("K3LR", "Tim Contest HQ", "USB", BandmapSpotStatus.worked),
            ("JA3USA", "Kansai Club", "CW", BandmapSpotStatus.unconfirmed),
            ("E51AND", "South Cook Islands", "FT8", BandmapSpotStatus.newDXCC)
        ]
        let item = demoCalls.randomElement()!
        addSpot(
            callsign: item.0,
            frequencyKHz: freq,
            band: targetBand,
            mode: item.2,
            comment: item.1,
            source: "Manual Sim",
            snr: Int.random(in: -16...12)
        )
    }

    // MARK: - Callsign Prefix Helper

    public static func extractPrefix(for callsign: String) -> String {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return "" }
        let base = clean.components(separatedBy: "/").first { $0.count >= 3 } ?? clean
        var prefix = ""
        for ch in base {
            prefix.append(ch)
            if ch.isNumber { break }
        }
        return prefix.isEmpty ? String(base.prefix(2)) : prefix
    }

    // MARK: - Status Classification against Active Logbook

    func classifyStatus(
        callsign: String,
        band: String,
        mode: String,
        logRecords: [QSORecordModel]
    ) -> BandmapSpotStatus {
        guard !logRecords.isEmpty else { return .newDXCC }

        let prefix = Self.extractPrefix(for: callsign)
        let hasCountryWorked = logRecords.contains {
            let p = Self.extractPrefix(for: $0["CALL"])
            return p == prefix
        }

        if !hasCountryWorked {
            return .newDXCC
        }

        let hasBandSlotWorked = logRecords.contains {
            let p = Self.extractPrefix(for: $0["CALL"])
            return p == prefix && $0["BAND"].uppercased() == band.uppercased()
        }

        if !hasBandSlotWorked {
            return .newBand
        }

        let isConfirmed = logRecords.contains {
            let p = Self.extractPrefix(for: $0["CALL"])
            return p == prefix && $0["BAND"].uppercased() == band.uppercased() && $0.isConfirmed
        }

        return isConfirmed ? .worked : .unconfirmed
    }

    // MARK: - Band Plans with IARU Region & License Class Support

    public func bandRangeKHz(for band: String, region: IARURegion? = nil) -> ClosedRange<Double> {
        let activeRegion = region ?? iaruRegion
        switch band.uppercased() {
        case "160M":
            return 1800.0...2000.0
        case "80M":
            return activeRegion == .region2 ? 3500.0...4000.0 : 3500.0...3800.0
        case "60M":
            return 5351.5...5366.5
        case "40M":
            return activeRegion == .region2 ? 7000.0...7300.0 : 7000.0...7200.0
        case "30M":
            return 10100.0...10150.0
        case "20M":
            return 14000.0...14350.0
        case "17M":
            return 18068.0...18168.0
        case "15M":
            return 21000.0...21450.0
        case "12M":
            return 24890.0...24990.0
        case "10M":
            return 28000.0...29700.0
        case "6M":
            return 50000.0...54000.0
        case "2M":
            return 144000.0...148000.0
        default:
            return 14000.0...14350.0
        }
    }

    public func bandPlanSegments(for band: String, region: IARURegion? = nil, license: LicenseClass? = nil) -> [BandPlanSegment] {
        let activeRegion = region ?? iaruRegion

        switch band.uppercased() {
        case "20M":
            return [
                BandPlanSegment(name: "CW Exclusive", startKHz: 14000.0, endKHz: 14070.0, color: Color.orange.opacity(0.35), allowedModes: "CW", minLicenseClass: .general),
                BandPlanSegment(name: "DATA / FT8 / RTTY", startKHz: 14070.0, endKHz: 14099.0, color: Color.green.opacity(0.35), allowedModes: "DATA", minLicenseClass: .general),
                BandPlanSegment(name: "IBP BEACONS", startKHz: 14099.0, endKHz: 14101.0, color: Color.red.opacity(0.40), allowedModes: "BEACON", minLicenseClass: .extra),
                BandPlanSegment(name: activeRegion == .region2 ? "PHONE (Extra Exclusive)" : "PHONE (SSB DX Window)", startKHz: 14101.0, endKHz: 14225.0, color: Color.blue.opacity(0.35), allowedModes: "SSB", minLicenseClass: activeRegion == .region2 ? .extra : .general),
                BandPlanSegment(name: "PHONE (SSB / All Classes)", startKHz: 14225.0, endKHz: 14350.0, color: Color.blue.opacity(0.25), allowedModes: "SSB", minLicenseClass: .general)
            ]

        case "40M":
            if activeRegion == .region2 {
                return [
                    BandPlanSegment(name: "CW Exclusive", startKHz: 7000.0, endKHz: 7040.0, color: Color.orange.opacity(0.35), allowedModes: "CW", minLicenseClass: .general),
                    BandPlanSegment(name: "DATA / FT8 / RTTY", startKHz: 7040.0, endKHz: 7125.0, color: Color.green.opacity(0.35), allowedModes: "DATA", minLicenseClass: .general),
                    BandPlanSegment(name: "PHONE (Extra Exclusive)", startKHz: 7125.0, endKHz: 7175.0, color: Color.blue.opacity(0.35), allowedModes: "SSB", minLicenseClass: .extra),
                    BandPlanSegment(name: "PHONE (General / Extra)", startKHz: 7175.0, endKHz: 7300.0, color: Color.blue.opacity(0.25), allowedModes: "SSB", minLicenseClass: .general)
                ]
            } else {
                return [
                    BandPlanSegment(name: "CW Priority", startKHz: 7000.0, endKHz: 7040.0, color: Color.orange.opacity(0.35), allowedModes: "CW", minLicenseClass: .general),
                    BandPlanSegment(name: "DATA / FT8", startKHz: 7040.0, endKHz: 7060.0, color: Color.green.opacity(0.35), allowedModes: "DATA", minLicenseClass: .general),
                    BandPlanSegment(name: "PHONE (SSB / Contest Window)", startKHz: 7060.0, endKHz: 7200.0, color: Color.blue.opacity(0.30), allowedModes: "SSB", minLicenseClass: .general)
                ]
            }

        case "15M":
            return [
                BandPlanSegment(name: "CW Exclusive", startKHz: 21000.0, endKHz: 21070.0, color: Color.orange.opacity(0.35), allowedModes: "CW", minLicenseClass: .general),
                BandPlanSegment(name: "DATA / FT8 / RTTY", startKHz: 21070.0, endKHz: 21150.0, color: Color.green.opacity(0.35), allowedModes: "DATA", minLicenseClass: .general),
                BandPlanSegment(name: activeRegion == .region2 ? "PHONE (Extra Exclusive)" : "PHONE (SSB DX Window)", startKHz: 21150.0, endKHz: 21275.0, color: Color.blue.opacity(0.35), allowedModes: "SSB", minLicenseClass: activeRegion == .region2 ? .extra : .general),
                BandPlanSegment(name: "PHONE (General / Extra)", startKHz: 21275.0, endKHz: 21450.0, color: Color.blue.opacity(0.25), allowedModes: "SSB", minLicenseClass: .general)
            ]

        case "10M":
            return [
                BandPlanSegment(name: "CW Exclusive", startKHz: 28000.0, endKHz: 28070.0, color: Color.orange.opacity(0.35), allowedModes: "CW", minLicenseClass: .technician),
                BandPlanSegment(name: "DATA / FT8 / RTTY", startKHz: 28070.0, endKHz: 28190.0, color: Color.green.opacity(0.35), allowedModes: "DATA", minLicenseClass: .technician),
                BandPlanSegment(name: "IBP BEACONS", startKHz: 28190.0, endKHz: 28225.0, color: Color.red.opacity(0.40), allowedModes: "BEACON", minLicenseClass: .extra),
                BandPlanSegment(name: "PHONE / NOVICE & TECH", startKHz: 28300.0, endKHz: 28500.0, color: Color.cyan.opacity(0.35), allowedModes: "SSB", minLicenseClass: .technician),
                BandPlanSegment(name: "PHONE / GENERAL & EXTRA", startKHz: 28500.0, endKHz: 29700.0, color: Color.blue.opacity(0.25), allowedModes: "SSB/FM", minLicenseClass: .general)
            ]

        case "80M":
            let endMax = activeRegion == .region2 ? 4000.0 : 3800.0
            return [
                BandPlanSegment(name: "CW Exclusive", startKHz: 3500.0, endKHz: 3570.0, color: Color.orange.opacity(0.35), allowedModes: "CW", minLicenseClass: .general),
                BandPlanSegment(name: "DATA / FT8", startKHz: 3570.0, endKHz: 3600.0, color: Color.green.opacity(0.35), allowedModes: "DATA", minLicenseClass: .general),
                BandPlanSegment(name: "PHONE (SSB DX Window)", startKHz: 3600.0, endKHz: 3800.0, color: Color.blue.opacity(0.35), allowedModes: "SSB", minLicenseClass: activeRegion == .region2 ? .extra : .general),
                BandPlanSegment(name: "PHONE (75m General)", startKHz: 3800.0, endKHz: endMax, color: Color.blue.opacity(0.25), allowedModes: "SSB", minLicenseClass: .general)
            ]

        default:
            let r = bandRangeKHz(for: band, region: activeRegion)
            let mid = r.lowerBound + (r.upperBound - r.lowerBound) * 0.35
            return [
                BandPlanSegment(name: "CW / DATA", startKHz: r.lowerBound, endKHz: mid, color: Color.orange.opacity(0.35), allowedModes: "CW/DATA", minLicenseClass: .general),
                BandPlanSegment(name: "PHONE (SSB)", startKHz: mid, endKHz: r.upperBound, color: Color.blue.opacity(0.30), allowedModes: "SSB", minLicenseClass: .general)
            ]
        }
    }

    // MARK: - Activity Heatmap Density Engine

    public func activityDensity(band: String, stepKHz: Double = 25.0) -> [(freq: Double, density: Double)] {
        let range = bandRangeKHz(for: band)
        guard range.upperBound > range.lowerBound else { return [] }

        var bins: [Double: Double] = [:]
        for freq in stride(from: range.lowerBound, through: range.upperBound, by: stepKHz) {
            bins[freq] = 0.0
        }

        // Aggregate spots into bins with temporal weight
        for spot in spots where spot.band.uppercased() == band.uppercased() || range.contains(spot.frequencyKHz) {
            let bin = (spot.frequencyKHz / stepKHz).rounded(.down) * stepKHz
            let weight = spot.isFresh ? 3.0 : (spot.ageMinutes < 10 ? 2.0 : 1.0)
            bins[bin, default: 0.0] += weight
        }

        let maxVal = bins.values.max() ?? 1.0
        let normMax = max(1.0, maxVal)

        let sorted = bins.keys.sorted().map { freq in
            let density = (bins[freq] ?? 0.0) / normMax
            return (freq: freq, density: density)
        }
        return sorted
    }

    private func populateDefaultSpots() {
        spots = [
            BandmapSpot(callsign: "3Y0J", frequencyKHz: 14025.0, band: "20M", mode: "CW", status: .newDXCC, comment: "Bouvet Island DXpedition UP 2", source: "DX Cluster", snr: -4),
            BandmapSpot(callsign: "W1AW", frequencyKHz: 14074.0, band: "20M", mode: "FT8", status: .worked, comment: "ARRL HQ Station -08", source: "WSJT-X", snr: -8),
            BandmapSpot(callsign: "JA1ZLO", frequencyKHz: 14018.5, band: "20M", mode: "CW", status: .newBand, comment: "Tokyo Univ 599", source: "DX Cluster", snr: 5),
            BandmapSpot(callsign: "DP0GVN", frequencyKHz: 14195.0, band: "20M", mode: "USB", status: .newDXCC, comment: "Neumayer Station III Antarctica", source: "DX Advisor", snr: -12),
            BandmapSpot(callsign: "DL2026HAM", frequencyKHz: 14240.0, band: "20M", mode: "USB", status: .unconfirmed, comment: "Special Event Station Friedrichshafen", source: "DX Cluster", snr: 10),
            BandmapSpot(callsign: "VK9XY", frequencyKHz: 7015.0, band: "40M", mode: "CW", status: .newDXCC, comment: "Christmas Island UP 1.5", source: "DX Cluster", snr: -6),
            BandmapSpot(callsign: "ZL7/K6VVA", frequencyKHz: 21028.0, band: "15M", mode: "CW", status: .newDXCC, comment: "Chatham Island", source: "DX Cluster", snr: 2),
            BandmapSpot(callsign: "FR4NT", frequencyKHz: 28020.0, band: "10M", mode: "CW", status: .newDXCC, comment: "Reunion Island", source: "DX Cluster", snr: -10),
            BandmapSpot(callsign: "KH6/W6JKV", frequencyKHz: 50110.0, band: "6M", mode: "CW", status: .newDXCC, comment: "Hawaii Island 50MHz DX Window", source: "DX Cluster", snr: -3)
        ]
    }
}
