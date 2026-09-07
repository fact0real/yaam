//
//  DigitalCallRosterEngine.swift
//  YAAM
//
//  High-Performance Real-Time Triage & Scoring Engine for Digital Mode Decodes.
//  Compares each decode against the user's master log in SQLite to dynamically
//  detect All-Time New DXCCs, New Bands, New Grids, CQs, and directed calls.
//

import AppKit
import Combine
import CoreLocation
import Foundation
import SwiftUI

public enum RosterTriageStatus: String, CaseIterable, Identifiable, Sendable {
    case callingMe = "CALLING ME"
    case newDXCC = "NEW DXCC"
    case newBand = "NEW BAND"
    case newGrid = "NEW GRID"
    case newMode = "NEW MODE"
    case worked = "WORKED"
    case confirmed = "CONFIRMED"

    public var id: String { rawValue }

    public var isNeeded: Bool {
        self == .newDXCC || self == .newBand || self == .newGrid || self == .newMode || self == .callingMe
    }

    public var priorityOrder: Int {
        switch self {
        case .callingMe: return 0
        case .newDXCC: return 1
        case .newBand: return 2
        case .newGrid: return 3
        case .newMode: return 4
        case .worked: return 5
        case .confirmed: return 6
        }
    }

    public var badgeColor: Color {
        switch self {
        case .callingMe: return .orange
        case .newDXCC: return .purple
        case .newBand: return .blue
        case .newGrid: return .green
        case .newMode: return .teal
        case .worked: return .gray
        case .confirmed: return Color.secondary.opacity(0.6)
        }
    }

    public var badgeIcon: String {
        switch self {
        case .callingMe: return "bell.badge.fill"
        case .newDXCC: return "star.fill"
        case .newBand: return "target"
        case .newGrid: return "square.grid.2x2.fill"
        case .newMode: return "waveform"
        case .worked: return "checkmark"
        case .confirmed: return "checkmark.seal.fill"
        }
    }
}

public struct DigitalRosterEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let callsign: String
    public let targetCallsign: String
    public let grid: String
    public let snr: Int32
    public let deltaFrequencyHz: UInt32
    public let message: String
    public let mode: String
    public let band: String
    public let dialFrequencyHz: UInt64
    public let countryInfo: DXCCEntityInfo
    public let distanceKm: Double?
    public let bearingDeg: Int?
    public let status: RosterTriageStatus
    public let isCQ: Bool
    public let isToMe: Bool
    public let receivedAt: Date
    public let rawDecode: WSJTXLiveDecode?

    public var snrFormatted: String {
        snr >= 0 ? "+\(snr) dB" : "\(snr) dB"
    }

    public var deltaFrequencyFormatted: String {
        "\(deltaFrequencyHz) Hz"
    }

    public var snrColor: Color {
        switch snr {
        case 0...: return Color.green
        case -10 ..< 0: return Color.yellow
        case -18 ..< -10: return Color.orange
        default: return Color.red
        }
    }
}

@MainActor
public final class DigitalCallRosterEngine: ObservableObject {
    public static let shared = DigitalCallRosterEngine()

    // MARK: - Published Outputs
    @Published public private(set) var entries: [DigitalRosterEntry] = []
    @Published public private(set) var totalDecodesCount: Int = 0
    @Published public private(set) var neededCount: Int = 0
    @Published public private(set) var cqCount: Int = 0
    @Published public private(set) var lastProcessedCycle: Date?

    // MARK: - Internal Cache
    private var workedCountries = Set<String>()
    private var confirmedCountries = Set<String>()
    private var workedCountryBands = Set<String>()     // e.g. "FRANCE_20M"
    private var confirmedCountryBands = Set<String>()
    private var workedGrids = Set<String>()            // e.g. "JN18_20M"
    private var workedCallsigns = Set<String>()        // e.g. "JA1ABC_20M"
    private var confirmedCallsigns = Set<String>()
    private var lastRecordsRevision: Int = -1

    private var myCallsign: String = ""
    private var myGrid: String = ""
    private var myHomeCoord: GeoCoordinate?
    private var maxRetainedEntries: Int = 200

    public init() {}

    // MARK: - Cache Invalidation & Building

    public func updateStationContext(callsign: String, grid: String) {
        let cleanCall = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanGrid = grid.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.myCallsign = cleanCall
        self.myGrid = cleanGrid
        if !cleanGrid.isEmpty, let box = MaidenheadGridEngine.boundingBox(for: cleanGrid) {
            self.myHomeCoord = box.center
        } else {
            self.myHomeCoord = nil
        }
    }

    func rebuildLogCache(records: [QSORecordModel], force: Bool = false) {
        var wCountries = Set<String>()
        var cCountries = Set<String>()
        var wCountryBands = Set<String>()
        var cCountryBands = Set<String>()
        var wGrids = Set<String>()
        var wCalls = Set<String>()
        var cCalls = Set<String>()

        for record in records {
            let r = record.fields
            let country = (r["COUNTRY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let band = (r["BAND"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let call = (r["CALL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let grid = (r["GRIDSQUARE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let isConfirmed = record.isConfirmed

            if !country.isEmpty && country != "Unknown" {
                wCountries.insert(country)
                if !band.isEmpty {
                    wCountryBands.insert("\(country)_\(band)")
                }
                if isConfirmed {
                    cCountries.insert(country)
                    if !band.isEmpty {
                        cCountryBands.insert("\(country)_\(band)")
                    }
                }
            }

            if !grid.isEmpty && grid.count >= 4 {
                let grid4 = String(grid.prefix(4))
                if !band.isEmpty {
                    wGrids.insert("\(grid4)_\(band)")
                }
            }

            if !call.isEmpty {
                if !band.isEmpty {
                    wCalls.insert("\(call)_\(band)")
                    if isConfirmed {
                        cCalls.insert("\(call)_\(band)")
                    }
                }
            }
        }

        self.workedCountries = wCountries
        self.confirmedCountries = cCountries
        self.workedCountryBands = wCountryBands
        self.confirmedCountryBands = cCountryBands
        self.workedGrids = wGrids
        self.workedCallsigns = wCalls
        self.confirmedCallsigns = cCalls
    }

    // MARK: - Ingestion & Triage Processing

    public func processDecodes(_ rawDecodes: [WSJTXLiveDecode], activeBand: String) {
        guard !rawDecodes.isEmpty else { return }

        var newRosterEntries: [DigitalRosterEntry] = []
        let audio = DigitalAudioAlertEngine.shared

        for decode in rawDecodes {
            let caller = decode.callerCallsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !caller.isEmpty else { continue }

            let target = decode.targetCallsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let grid = decode.grid.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let bandKey = activeBand.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let band = bandKey.isEmpty ? "20M" : bandKey

            let countryInfo = DXCCDatabase.resolve(callsign: caller)
            let countryName = countryInfo.entityName

            let isToMe = !myCallsign.isEmpty && (target == myCallsign || decode.message.contains(myCallsign))
            let isCQ = decode.isCQ

            // Calculate Distance & Bearing
            var distanceKm: Double? = nil
            var bearingDeg: Int? = nil
            if let home = myHomeCoord, !grid.isEmpty, let targetBox = MaidenheadGridEngine.boundingBox(for: grid) {
                let dist = GeodesicMath.distanceKm(from: home, to: targetBox.center)
                let bearing = GeodesicMath.initialBearing(from: home, to: targetBox.center)
                distanceKm = dist
                bearingDeg = Int(bearing.rounded())
            }

            // Triage Classification
            let status: RosterTriageStatus
            let gridKey = grid.count >= 4 ? "\(String(grid.prefix(4)))_\(band)" : ""

            if isToMe {
                status = .callingMe
                audio.announceDirectedToMe(caller: caller, snr: decode.snr, band: band)
            } else if !countryName.isEmpty && countryName != "Unknown" && !workedCountries.contains(countryName) {
                status = .newDXCC
                audio.announceNewDXCC(callsign: caller, country: countryName, band: band)
            } else if !countryName.isEmpty && countryName != "Unknown" && !workedCountryBands.contains("\(countryName)_\(band)") {
                status = .newBand
                audio.announceNewBand(callsign: caller, country: countryName, band: band)
            } else if !gridKey.isEmpty && !workedGrids.contains(gridKey) {
                status = .newGrid
                audio.announceNewGrid(callsign: caller, grid: grid, band: band)
            } else if confirmedCallsigns.contains("\(caller)_\(band)") {
                status = .confirmed
            } else {
                status = .worked
            }

            let entry = DigitalRosterEntry(
                id: decode.id,
                callsign: caller,
                targetCallsign: target,
                grid: grid,
                snr: decode.snr,
                deltaFrequencyHz: decode.deltaFrequencyHz,
                message: decode.message,
                mode: decode.mode,
                band: band,
                dialFrequencyHz: 0,
                countryInfo: countryInfo,
                distanceKm: distanceKm,
                bearingDeg: bearingDeg,
                status: status,
                isCQ: isCQ,
                isToMe: isToMe,
                receivedAt: decode.receivedAt,
                rawDecode: decode
            )

            newRosterEntries.append(entry)
        }

        // Deduplicate against existing list (keep freshest decode per caller within the cycle)
        var existingMap: [String: DigitalRosterEntry] = [:]
        for entry in self.entries {
            existingMap[entry.callsign] = entry
        }
        for newEntry in newRosterEntries {
            existingMap[newEntry.callsign] = newEntry
        }

        // Sort: Priority first, then SNR descending
        let sorted = existingMap.values.sorted {
            if $0.status.priorityOrder != $1.status.priorityOrder {
                return $0.status.priorityOrder < $1.status.priorityOrder
            }
            return $0.snr > $1.snr
        }

        self.entries = Array(sorted.prefix(maxRetainedEntries))
        self.totalDecodesCount = self.entries.count
        self.neededCount = self.entries.filter { $0.status.isNeeded }.count
        self.cqCount = self.entries.filter { $0.isCQ }.count
        self.lastProcessedCycle = Date()
    }

    public func clearRoster() {
        entries.removeAll()
        totalDecodesCount = 0
        neededCount = 0
        cqCount = 0
    }
}
