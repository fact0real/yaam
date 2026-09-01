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
        source: String = "DX Cluster"
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
    }

    public var ageSeconds: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }

    public var ageMinutes: Int {
        max(0, Int(ageSeconds / 60.0))
    }

    public var opacity: Double {
        let maxAge: Double = 3600.0 // 60 minutes
        let factor = max(0.25, 1.0 - (ageSeconds / maxAge) * 0.75)
        return factor
    }
}

public struct BandPlanSegment: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let startKHz: Double
    public let endKHz: Double
    public let color: Color

    public init(name: String, startKHz: Double, endKHz: Double, color: Color) {
        self.name = name
        self.startKHz = startKHz
        self.endKHz = endKHz
        self.color = color
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
            source: source
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

    // MARK: - Band Plans (CW / DATA / SSB)

    public func bandRangeKHz(for band: String) -> ClosedRange<Double> {
        switch band.uppercased() {
        case "160M": return 1800.0...2000.0
        case "80M":  return 3500.0...3800.0
        case "40M":  return 7000.0...7300.0
        case "30M":  return 10100.0...10150.0
        case "20M":  return 14000.0...14350.0
        case "17M":  return 18068.0...18168.0
        case "15M":  return 21000.0...21450.0
        case "12M":  return 24890.0...24990.0
        case "10M":  return 28000.0...29700.0
        case "6M":   return 50000.0...54000.0
        case "2M":   return 144000.0...148000.0
        default:     return 14000.0...14350.0
        }
    }

    public func bandPlanSegments(for band: String) -> [BandPlanSegment] {
        switch band.uppercased() {
        case "20M":
            return [
                BandPlanSegment(name: "CW", startKHz: 14000.0, endKHz: 14070.0, color: .orange.opacity(0.2)),
                BandPlanSegment(name: "DATA / FT8", startKHz: 14070.0, endKHz: 14099.0, color: .green.opacity(0.2)),
                BandPlanSegment(name: "BEACONS", startKHz: 14099.0, endKHz: 14101.0, color: .red.opacity(0.2)),
                BandPlanSegment(name: "PHONE (SSB)", startKHz: 14101.0, endKHz: 14350.0, color: .blue.opacity(0.2))
            ]
        case "40M":
            return [
                BandPlanSegment(name: "CW", startKHz: 7000.0, endKHz: 7040.0, color: .orange.opacity(0.2)),
                BandPlanSegment(name: "DATA / FT8", startKHz: 7040.0, endKHz: 7060.0, color: .green.opacity(0.2)),
                BandPlanSegment(name: "PHONE (SSB)", startKHz: 7060.0, endKHz: 7300.0, color: .blue.opacity(0.2))
            ]
        case "15M":
            return [
                BandPlanSegment(name: "CW", startKHz: 21000.0, endKHz: 21070.0, color: .orange.opacity(0.2)),
                BandPlanSegment(name: "DATA / FT8", startKHz: 21070.0, endKHz: 21150.0, color: .green.opacity(0.2)),
                BandPlanSegment(name: "PHONE (SSB)", startKHz: 21150.0, endKHz: 21450.0, color: .blue.opacity(0.2))
            ]
        case "10M":
            return [
                BandPlanSegment(name: "CW", startKHz: 28000.0, endKHz: 28070.0, color: .orange.opacity(0.2)),
                BandPlanSegment(name: "DATA / FT8", startKHz: 28070.0, endKHz: 28190.0, color: .green.opacity(0.2)),
                BandPlanSegment(name: "BEACONS", startKHz: 28190.0, endKHz: 28225.0, color: .red.opacity(0.2)),
                BandPlanSegment(name: "PHONE (SSB)", startKHz: 28225.0, endKHz: 29700.0, color: .blue.opacity(0.2))
            ]
        default:
            let r = bandRangeKHz(for: band)
            let mid = r.lowerBound + (r.upperBound - r.lowerBound) * 0.3
            return [
                BandPlanSegment(name: "CW / DATA", startKHz: r.lowerBound, endKHz: mid, color: .orange.opacity(0.2)),
                BandPlanSegment(name: "PHONE / SSB", startKHz: mid, endKHz: r.upperBound, color: .blue.opacity(0.2))
            ]
        }
    }

    private func populateDefaultSpots() {
        spots = [
            BandmapSpot(callsign: "3Y0J", frequencyKHz: 14025.0, band: "20M", mode: "CW", status: .newDXCC, comment: "Bouvet Island DXpedition UP 2", source: "DX Cluster"),
            BandmapSpot(callsign: "W1AW", frequencyKHz: 14074.0, band: "20M", mode: "FT8", status: .worked, comment: "ARRL HQ Station -08", source: "WSJT-X"),
            BandmapSpot(callsign: "JA1ZLO", frequencyKHz: 14018.5, band: "20M", mode: "CW", status: .newBand, comment: "Tokyo Univ 599", source: "DX Cluster"),
            BandmapSpot(callsign: "DP0GVN", frequencyKHz: 14195.0, band: "20M", mode: "USB", status: .newDXCC, comment: "Neumayer Station III Antarctica", source: "DX Advisor"),
            BandmapSpot(callsign: "DL2026HAM", frequencyKHz: 14240.0, band: "20M", mode: "USB", status: .unconfirmed, comment: "Special Event Station Friedrichshafen", source: "DX Cluster"),
            BandmapSpot(callsign: "VK9XY", frequencyKHz: 7015.0, band: "40M", mode: "CW", status: .newDXCC, comment: "Christmas Island", source: "DX Cluster"),
            BandmapSpot(callsign: "ZL7/K6VVA", frequencyKHz: 21028.0, band: "15M", mode: "CW", status: .newDXCC, comment: "Chatham Island", source: "DX Cluster")
        ]
    }
}
