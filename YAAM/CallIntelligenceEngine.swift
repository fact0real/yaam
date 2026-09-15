//
//  CallIntelligenceEngine.swift
//  YAAM
//
//  Real-Time Call Intelligence, Award Need Impact & Tactical Propagation Engine.
//  Instantly computes ATNO, DXCC status, Band/Mode slots, LoTW activity,
//  antenna headings, solar illumination, and cluster radar for incoming callsigns.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Award Need Badges

struct AwardNeedBadge: Identifiable, Equatable, Hashable, Sendable {
    var id: String { "\(type.rawValue)-\(title)" }

    enum BadgeType: String, Sendable {
        case atno = "ATNO"
        case newDXCC = "NEW_DXCC"
        case unconfirmedDXCC = "NEED_QSL"
        case newBand = "NEW_BAND"
        case newMode = "NEW_MODE"
        case newSlot = "NEW_SLOT"
        case newGrid = "NEW_GRID"
        case wasNeed = "WAS_NEED"
        case wazNeed = "WAZ_NEED"
        case special = "SPECIAL"
    }

    let type: BadgeType
    let title: String
    let detail: String
    let icon: String
    let colorName: String

    init(type: BadgeType, title: String, detail: String, icon: String, colorName: String) {
        self.type = type
        self.title = title
        self.detail = detail
        self.icon = icon
        self.colorName = colorName
    }

    var badgeColor: Color {
        switch colorName {
        case "amber": return .orange
        case "yellow": return .yellow
        case "cyan": return .cyan
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "red": return .red
        case "indigo": return .indigo
        default: return .blue
        }
    }
}

// MARK: - Band / Mode Slot Status

enum BandSlotStatus: String, Sendable {
    case unworked = "Needed"
    case worked = "Worked"
    case confirmed = "Confirmed"
    case currentDraft = "Current"

    var color: Color {
        switch self {
        case .unworked: return .secondary.opacity(0.3)
        case .worked: return .orange
        case .confirmed: return .green
        case .currentDraft: return .blue
        }
    }
}

struct BandMatrixRow: Identifiable, Equatable, Hashable, Sendable {
    var id: String { band }
    let band: String
    let isCurrent: Bool
    let workedCount: Int
    let confirmedCount: Int
    let cwStatus: BandSlotStatus
    let ssbStatus: BandSlotStatus
    let digiStatus: BandSlotStatus

    var isWorked: Bool { workedCount > 0 }
    var isConfirmed: Bool { confirmedCount > 0 }
}

// MARK: - QSL & LoTW Intelligence Models

enum QSLLikelihood: String, Sendable {
    case veryHigh = "Very High (LoTW Active)"
    case high = "High"
    case moderate = "Moderate"
    case low = "Low / Paper Only"

    var color: Color {
        switch self {
        case .veryHigh: return .green
        case .high: return .blue
        case .moderate: return .orange
        case .low: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .veryHigh: return "checkmark.seal.fill"
        case .high: return "checkmark.circle.fill"
        case .moderate: return "questionmark.circle.fill"
        case .low: return "envelope.fill"
        }
    }
}

// MARK: - Comprehensive Call Intelligence Report

struct CallIntelligenceReport: Identifiable, Sendable {
    var id: String { callsign }

    // MARK: Identity & Location
    let callsign: String
    let baseCallsign: String
    let dxcc: DXCCEntityInfo
    let ctyMatch: CTYLookupResult?
    let lookupData: CallsignLookupResult?
    let operatorName: String
    let qth: String
    let grid: String
    let cqZone: Int
    let ituZone: Int
    let continent: String
    let scpMatch: SuperCheckPartialMatch?
    let clubMemberships: [ClubMembershipMatch]

    // MARK: Award & Need Intelligence
    let isATNO: Bool
    let isNewDXCC: Bool
    let isDXCCUnconfirmed: Bool
    let isDXCCConfirmed: Bool
    let isNewOnBand: Bool
    let isBandConfirmed: Bool
    let isNewOnMode: Bool
    let isModeConfirmed: Bool
    let isSlotNeeded: Bool
    let isNewGridAllTime: Bool
    let isNewGridOnBand: Bool
    let isStateNeededForWAS: Bool
    let stateCode: String?
    let isZoneNeededForWAZ: Bool
    let badges: [AwardNeedBadge]

    // MARK: Band Matrix
    let bandRows: [BandMatrixRow]

    // MARK: QSL & LoTW
    let isLoTWUser: Bool
    let lastLoTWUpload: Date?
    let lotwSummaryText: String
    let historicalConfirmationRate: Double?
    let qslLikelihood: QSLLikelihood
    let recommendedQSLRoute: String

    // MARK: Solar, Direction & Bearing
    let homeCoordinate: GeoCoordinate?
    let targetCoordinate: GeoCoordinate?
    let shortPathBearingDeg: Double?
    let longPathBearingDeg: Double?
    let distanceKm: Double?
    let distanceMiles: Double?
    let cardinalDirection: String
    let targetIllumination: SolarEphemeris.IlluminationState?
    let sunriseUTC: String?
    let sunsetUTC: String?
    let isGreylineOpportunity: Bool

    // MARK: Live Radar & Cluster
    let liveClusterSpots: [DXSpot]
    let recentArchivedSpots: [ArchivedSpotRecord]

    // MARK: Live HF Propagation & MUF Radar
    let propagationPrediction: PathPropagationPrediction?

    // MARK: Pileup Sniper & Split QSX
    let pileupSniper: PileupSniperSolution?

    // MARK: History
    let totalWorkedCount: Int
    let totalConfirmedCount: Int
    let sameBandCount: Int
    let sameBandModeCount: Int
    let lastWorkedDate: Date?
    let matchingPreviousQSOs: [QSORecordModel]

    // MARK: - QRZ & HAMQTH Rich Profile Helpers
    var qslManager: String? {
        let mgr = lookupData?.qslManager.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return mgr.isEmpty ? nil : mgr
    }
    var imageURL: String? {
        let img = lookupData?.imageURL.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return img.isEmpty ? nil : img
    }
    var licenseClass: String? {
        let lic = lookupData?.licenseClass.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return lic.isEmpty ? nil : lic
    }
    var usState: String? {
        let s = lookupData?.state.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }
    var usCounty: String? {
        let c = lookupData?.county.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return c.isEmpty ? nil : c
    }
    var iotaReference: String? {
        let i = lookupData?.iota.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return i.isEmpty ? nil : i
    }
    var profileViews: Int {
        lookupData?.profileViews ?? 0
    }
    var birthYear: String? {
        let b = lookupData?.birthYear.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return b.isEmpty ? nil : b
    }
}

// MARK: - Engine Class

@MainActor
final class CallIntelligenceEngine: ObservableObject {
    static let shared = CallIntelligenceEngine()

    @Published private(set) var activeReport: CallIntelligenceReport?
    @Published private(set) var isAnalyzing: Bool = false

    private var currentTask: Task<Void, Never>?
    private var cachedReports: [String: CallIntelligenceReport] = [:]

    private init() {}

    // MARK: - Public API

    func update(
        callsign rawCallsign: String,
        band: String,
        mode: String,
        records: [QSORecordModel],
        homeCoordinate: GeoCoordinate?,
        lookupResult: CallsignLookupResult?,
        clusterSpots: [DXSpot] = []
    ) {
        let clean = rawCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else {
            activeReport = nil
            currentTask?.cancel()
            isAnalyzing = false
            return
        }

        currentTask?.cancel()
        isAnalyzing = true

        let homeKey = homeCoordinate.map { "\(String(format: "%.2f", $0.latitude)),\(String(format: "%.2f", $0.longitude))" } ?? "nil"
        let cacheKey = "\(clean)|\(band)|\(mode)|\(records.count)|\(lookupResult?.grid ?? "")|\(clusterSpots.count)|\(homeKey)"
        if let cached = cachedReports[cacheKey] {
            self.activeReport = cached
            self.isAnalyzing = false
            return
        }

        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let report = Self.analyze(
                callsign: clean,
                band: band,
                mode: mode,
                records: records,
                homeCoordinate: homeCoordinate,
                lookupResult: lookupResult,
                clusterSpots: clusterSpots
            )

            guard !Task.isCancelled else { return }
            self.cachedReports[cacheKey] = report
            if self.cachedReports.count > 100 {
                self.cachedReports.removeAll(keepingCapacity: true)
            }
            self.activeReport = report
            self.isAnalyzing = false
        }
    }

    func clear() {
        currentTask?.cancel()
        activeReport = nil
        isAnalyzing = false
    }

    // MARK: - Pure Analysis

    @MainActor
    static func analyze(
        callsign: String,
        band: String,
        mode: String,
        records: [QSORecordModel],
        homeCoordinate: GeoCoordinate?,
        lookupResult: CallsignLookupResult?,
        clusterSpots: [DXSpot] = []
    ) -> CallIntelligenceReport {
        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let activeBand = band.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let activeMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // 1. Identity & Database Resolution
        let dxcc = DXCCDatabase.resolve(callsign: cleanCall)
        let cty = CTYDatabaseManager.shared.lookup(callsign: cleanCall)

        let baseParts = cleanCall.components(separatedBy: "/")
        let baseCall = baseParts.first { $0.count >= 3 && !$0.allSatisfy(\.isNumber) } ?? cleanCall

        let scpMatches = SuperCheckPartialEngine.shared.findMatches(for: cleanCall, maxResults: 1)
        let scpMatch = scpMatches.first { $0.callsign.uppercased() == cleanCall } ?? scpMatches.first

        let clubMatches = ClubMembershipEngine.shared.lookupMemberships(for: cleanCall)

        let name = lookupResult?.name.isEmpty == false ? (lookupResult?.name ?? "") : ""
        let qth = lookupResult?.qth.isEmpty == false ? (lookupResult?.qth ?? "") : ""
        let grid = lookupResult?.grid.isEmpty == false ? (lookupResult?.grid ?? "") : ""
        let cqZ = (lookupResult?.cqZone.isEmpty == false ? Int(lookupResult?.cqZone ?? "") : nil) ?? cty?.cqZone ?? dxcc.cqZone
        let ituZ = (lookupResult?.ituZone.isEmpty == false ? Int(lookupResult?.ituZone ?? "") : nil) ?? cty?.ituZone ?? dxcc.ituZone
        let continent = cty?.entity.continent.isEmpty == false ? (cty?.entity.continent ?? dxcc.continent) : dxcc.continent

        // 2. Log History & Award Needs
        var totalWorked = 0
        var totalConfirmed = 0
        var sameBandCount = 0
        var sameBandModeCount = 0
        var lastWorkedDate: Date? = nil
        var matchingQSOs: [QSORecordModel] = []

        // DXCC entity tracking
        var dxccWorkedTotal = 0
        var dxccConfirmedTotal = 0
        var dxccBandWorked = 0
        var dxccBandConfirmed = 0
        var dxccModeWorked = 0
        var dxccModeConfirmed = 0
        var dxccSlotWorked = 0

        // Grids tracking
        var gridWorkedAllTime = false
        var gridWorkedOnBand = false

        // States tracking (US / Canada)
        var stateCode: String? = nil
        if dxcc.countryCode == "US" || dxcc.countryCode == "CA" {
            if let lookupState = lookupResult?.qth.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines), lookupState.count == 2 {
                stateCode = lookupState.uppercased()
            }
        }

        // Zone tracking
        var cqZoneWorked = false
        var cqZoneConfirmed = false

        let cleanTargetGrid = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let targetGrid4 = String(cleanTargetGrid.prefix(4))

        for rec in records {
            let recCall = rec["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let recBand = rec["BAND"].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let recMode = rec["MODE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let isConf = rec.isConfirmed

            // Exact call matching
            if recCall == cleanCall || recCall == baseCall {
                totalWorked += 1
                if isConf { totalConfirmed += 1 }
                if recBand == activeBand { sameBandCount += 1 }
                if recBand == activeBand && recMode == activeMode { sameBandModeCount += 1 }

                matchingQSOs.append(rec)

                if let d = parseQSODate(rec) {
                    if lastWorkedDate == nil || d > lastWorkedDate! {
                        lastWorkedDate = d
                    }
                }
            }

            // DXCC matching
            let recDXCC = DXCCDatabase.resolve(callsign: recCall)
            if recDXCC.countryCode == dxcc.countryCode || recDXCC.entityName == dxcc.entityName {
                dxccWorkedTotal += 1
                if isConf { dxccConfirmedTotal += 1 }
                if recBand == activeBand {
                    dxccBandWorked += 1
                    if isConf { dxccBandConfirmed += 1 }
                }
                if recMode == activeMode {
                    dxccModeWorked += 1
                    if isConf { dxccModeConfirmed += 1 }
                }
                if recBand == activeBand && recMode == activeMode {
                    dxccSlotWorked += 1
                }
            }

            // Grid matching
            if !targetGrid4.isEmpty {
                let recGrid = (rec["GRIDSQUARE"].isEmpty ? rec["GRID"] : rec["GRIDSQUARE"]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if recGrid.hasPrefix(targetGrid4) {
                    gridWorkedAllTime = true
                    if recBand == activeBand {
                        gridWorkedOnBand = true
                    }
                }
            }

            // CQ Zone matching
            let recCQ = Int(rec["CQZ"]) ?? recDXCC.cqZone
            if recCQ == cqZ {
                cqZoneWorked = true
                if isConf { cqZoneConfirmed = true }
            }
        }

        let isATNO = (totalWorked == 0)
        let isNewDXCC = (dxccWorkedTotal == 0)
        let isDXCCUnconfirmed = (dxccWorkedTotal > 0 && dxccConfirmedTotal == 0)
        let isDXCCConfirmed = (dxccConfirmedTotal > 0)
        let isNewOnBand = (dxccBandWorked == 0)
        let isBandConfirmed = (dxccBandConfirmed > 0)
        let isNewOnMode = (dxccModeWorked == 0)
        let isModeConfirmed = (dxccModeConfirmed > 0)
        let isSlotNeeded = (dxccSlotWorked == 0)
        let isNewGridAllTime = (!targetGrid4.isEmpty && !gridWorkedAllTime)
        let isNewGridOnBand = (!targetGrid4.isEmpty && !gridWorkedOnBand)
        let isZoneNeededForWAZ = !cqZoneConfirmed

        var isStateNeededForWAS = false
        if let state = stateCode {
            let stateMatches = records.filter {
                $0["STATE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == state
            }
            isStateNeededForWAS = !stateMatches.contains(where: \.isConfirmed)
        }

        // 3. Badges Composition
        var badges: [AwardNeedBadge] = []

        if isNewDXCC {
            badges.append(AwardNeedBadge(
                type: .newDXCC,
                title: "NEW DXCC",
                detail: "Never worked \(dxcc.entityName) anywhere!",
                icon: "sparkles",
                colorName: "amber"
            ))
        } else if isDXCCUnconfirmed {
            badges.append(AwardNeedBadge(
                type: .unconfirmedDXCC,
                title: "UNCONFIRMED DXCC",
                detail: "\(dxcc.entityName) worked (\(dxccWorkedTotal) QSOs) but not yet confirmed!",
                icon: "exclamationmark.circle.fill",
                colorName: "yellow"
            ))
        }

        if isATNO && !isNewDXCC {
            badges.append(AwardNeedBadge(
                type: .atno,
                title: "ATNO CALL",
                detail: "All-Time New One for this specific callsign",
                icon: "star.circle.fill",
                colorName: "cyan"
            ))
        }

        if isNewOnBand && !activeBand.isEmpty {
            badges.append(AwardNeedBadge(
                type: .newBand,
                title: "NEW BAND · \(activeBand.uppercased())",
                detail: "\(dxcc.entityName) never worked on \(activeBand.uppercased())",
                icon: "bolt.horizontal.fill",
                colorName: "blue"
            ))
        }

        if isNewOnMode && !activeMode.isEmpty {
            badges.append(AwardNeedBadge(
                type: .newMode,
                title: "NEW MODE · \(activeMode)",
                detail: "\(dxcc.entityName) never worked in \(activeMode)",
                icon: "waveform.badge.plus",
                colorName: "purple"
            ))
        }

        if isNewGridOnBand && !targetGrid4.isEmpty {
            badges.append(AwardNeedBadge(
                type: .newGrid,
                title: "NEW GRID · \(targetGrid4)",
                detail: "Grid \(targetGrid4) never worked on \(activeBand.uppercased())",
                icon: "square.grid.3x3.fill",
                colorName: "green"
            ))
        }

        if isStateNeededForWAS, let state = stateCode {
            badges.append(AwardNeedBadge(
                type: .wasNeed,
                title: "WAS NEED · \(state)",
                detail: "State \(state) needed / unconfirmed for WAS",
                icon: "map.fill",
                colorName: "indigo"
            ))
        }

        if isZoneNeededForWAZ && cqZ > 0 {
            badges.append(AwardNeedBadge(
                type: .wazNeed,
                title: cqZoneWorked ? "WAZ NEED · ZONE \(cqZ)" : "NEW WAZ ZONE · \(cqZ)",
                detail: cqZoneWorked ? "CQ Zone \(cqZ) worked but unconfirmed for WAZ" : "CQ Zone \(cqZ) never worked in station log",
                icon: "globe",
                colorName: "blue"
            ))
        }

        // 4. Band Matrix Computation
        let commonBands = AmateurBandSettings.shared.orderedActiveBands()
        var bandRows: [BandMatrixRow] = []

        for b in commonBands {
            let bLower = b.lowercased()
            let bandQSOs = records.filter {
                let recCall = $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let matchCall = (recCall == cleanCall || recCall == baseCall)
                let recDXCC = DXCCDatabase.resolve(callsign: recCall)
                let matchDXCC = (recDXCC.countryCode == dxcc.countryCode)
                return (matchCall || matchDXCC) && $0["BAND"].lowercased() == bLower
            }

            let cwQSOs = bandQSOs.filter { $0["MODE"].uppercased() == "CW" }
            let ssbQSOs = bandQSOs.filter { ["SSB", "USB", "LSB", "AM", "FM"].contains($0["MODE"].uppercased()) }
            let digiQSOs = bandQSOs.filter { ["FT8", "FT4", "RTTY", "PSK", "JS8", "DATA", "DIGI"].contains($0["MODE"].uppercased()) }

            let cwStatus: BandSlotStatus = cwQSOs.contains(where: \.isConfirmed) ? .confirmed : (!cwQSOs.isEmpty ? .worked : .unworked)
            let ssbStatus: BandSlotStatus = ssbQSOs.contains(where: \.isConfirmed) ? .confirmed : (!ssbQSOs.isEmpty ? .worked : .unworked)
            let digiStatus: BandSlotStatus = digiQSOs.contains(where: \.isConfirmed) ? .confirmed : (!digiQSOs.isEmpty ? .worked : .unworked)

            bandRows.append(BandMatrixRow(
                band: b,
                isCurrent: (bLower == activeBand),
                workedCount: bandQSOs.count,
                confirmedCount: bandQSOs.filter(\.isConfirmed).count,
                cwStatus: cwStatus,
                ssbStatus: ssbStatus,
                digiStatus: digiStatus
            ))
        }

        // 5. QSL & LoTW Intelligence
        let isLoTWUser = LoTWActivityDatabase.shared.isUserActive(cleanCall, withinDays: 365)
        let lastUpload = LoTWActivityDatabase.shared.lastUploadDate(for: cleanCall)
        let lotwSummary = LoTWActivityDatabase.shared.lastUploadDescription(for: cleanCall)

        let histRate: Double?
        if totalWorked > 0 {
            histRate = Double(totalConfirmed) / Double(totalWorked)
        } else if dxccWorkedTotal > 0 {
            histRate = Double(dxccConfirmedTotal) / Double(dxccWorkedTotal)
        } else {
            histRate = nil
        }

        let qslLikelihood: QSLLikelihood
        let recommendedRoute: String

        let explicitMgr = lookupResult?.qslManager.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitMgr.isEmpty {
            qslLikelihood = isLoTWUser ? .veryHigh : .high
            recommendedRoute = "QSL via \(explicitMgr)" + (isLoTWUser ? " · LoTW Active" : "")
        } else if isLoTWUser {
            qslLikelihood = .veryHigh
            recommendedRoute = "LoTW (Fastest & Electronic)"
        } else if lastUpload != nil {
            qslLikelihood = .moderate
            recommendedRoute = "LoTW (>1 yr old) or Direct QSL"
        } else if let rate = histRate, rate >= 0.6 {
            qslLikelihood = .high
            recommendedRoute = "Direct QSL with SASE or Bureau"
        } else {
            qslLikelihood = .low
            recommendedRoute = "Direct Mail or ClubLog OQRS"
        }

        // 6. Solar, Bearing & Coordinates
        var targetCoord: GeoCoordinate? = nil
        if !grid.isEmpty, let coords = SpotterDistanceEngine.coordinates(forGrid: grid) {
            targetCoord = GeoCoordinate(latitude: coords.lat, longitude: coords.lon)
        } else if let ctyLat = cty?.latitude, let ctyLon = cty?.longitude, (ctyLat != 0 || ctyLon != 0) {
            targetCoord = GeoCoordinate(latitude: ctyLat, longitude: ctyLon)
        }

        var spBearing: Double? = nil
        var lpBearing: Double? = nil
        var distKm: Double? = nil
        var distMi: Double? = nil
        var cardinal = "--"

        if let home = homeCoordinate, let target = targetCoord {
            let sp = GeodesicMath.initialBearing(from: home, to: target)
            let lp = GeodesicMath.longPathBearing(from: home, to: target)
            let km = GeodesicMath.distanceKm(from: home, to: target)
            spBearing = sp
            lpBearing = lp
            distKm = km
            distMi = km * GeodesicMath.kmToMiles
            cardinal = SpotterDistanceEngine.cardinalDirection(for: sp)
        }

        let targetIllumination: SolarEphemeris.IlluminationState?
        let sunriseUTC: String?
        let sunsetUTC: String?
        let isGreylineOpp: Bool

        if let target = targetCoord {
            targetIllumination = SolarEphemeris.illuminationState(for: target)
            let sunTimes = SolarEphemeris.sunriseSunset(for: target)
            sunriseUTC = sunTimes.sunrise
            sunsetUTC = sunTimes.sunset

            let homeIllumination = homeCoordinate.flatMap { SolarEphemeris.illuminationState(for: $0) }
            let isTargetGreyline = (targetIllumination == .greylineCivil || targetIllumination == .greylineNautical)
            let isHomeGreyline = (homeIllumination == .greylineCivil || homeIllumination == .greylineNautical)
            isGreylineOpp = isTargetGreyline || isHomeGreyline
        } else {
            targetIllumination = nil
            sunriseUTC = nil
            sunsetUTC = nil
            isGreylineOpp = false
        }

        // 7. Live Spots & Radar
        let matchingClusterSpots = clusterSpots.filter {
            $0.callsign.uppercased() == cleanCall || $0.callsign.uppercased() == baseCall
        }
        let archivedSpots = SpotArchiveDatabase.shared.searchArchive(callsign: cleanCall, sinceHours: 48, limit: 10)

        // 8. Live HF Propagation & MUF Radar
        let propPrediction: PathPropagationPrediction?
        if let home = homeCoordinate, let target = targetCoord {
            propPrediction = HFPointToPointPropagationEngine.predictPath(
                de: home,
                dx: target,
                band: activeBand.isEmpty ? "20m" : activeBand,
                date: Date()
            )
        } else {
            propPrediction = nil
        }

        // 9. Pileup Sniper & Split QSX Analysis
        let dxBaseFreqKHz = matchingClusterSpots.first?.frequencyKHz
            ?? archivedSpots.first?.frequencyKHz
            ?? (HFPointToPointPropagationEngine.frequency(for: activeBand) * 1000.0)

        let sniper = PileupSniperEngine.analyze(
            dxCallsign: cleanCall,
            dxRxFrequencyKHz: dxBaseFreqKHz,
            clusterSpots: matchingClusterSpots,
            archivedSpots: archivedSpots
        )

        return CallIntelligenceReport(
            callsign: cleanCall,
            baseCallsign: baseCall,
            dxcc: dxcc,
            ctyMatch: cty,
            lookupData: lookupResult,
            operatorName: name,
            qth: qth,
            grid: grid,
            cqZone: cqZ,
            ituZone: ituZ,
            continent: continent,
            scpMatch: scpMatch,
            clubMemberships: clubMatches,
            isATNO: isATNO,
            isNewDXCC: isNewDXCC,
            isDXCCUnconfirmed: isDXCCUnconfirmed,
            isDXCCConfirmed: isDXCCConfirmed,
            isNewOnBand: isNewOnBand,
            isBandConfirmed: isBandConfirmed,
            isNewOnMode: isNewOnMode,
            isModeConfirmed: isModeConfirmed,
            isSlotNeeded: isSlotNeeded,
            isNewGridAllTime: isNewGridAllTime,
            isNewGridOnBand: isNewGridOnBand,
            isStateNeededForWAS: isStateNeededForWAS,
            stateCode: stateCode,
            isZoneNeededForWAZ: isZoneNeededForWAZ,
            badges: badges,
            bandRows: bandRows,
            isLoTWUser: isLoTWUser,
            lastLoTWUpload: lastUpload,
            lotwSummaryText: lotwSummary,
            historicalConfirmationRate: histRate,
            qslLikelihood: qslLikelihood,
            recommendedQSLRoute: recommendedRoute,
            homeCoordinate: homeCoordinate,
            targetCoordinate: targetCoord,
            shortPathBearingDeg: spBearing,
            longPathBearingDeg: lpBearing,
            distanceKm: distKm,
            distanceMiles: distMi,
            cardinalDirection: cardinal,
            targetIllumination: targetIllumination,
            sunriseUTC: sunriseUTC,
            sunsetUTC: sunsetUTC,
            isGreylineOpportunity: isGreylineOpp,
            liveClusterSpots: matchingClusterSpots,
            recentArchivedSpots: archivedSpots,
            propagationPrediction: propPrediction,
            pileupSniper: sniper,
            totalWorkedCount: totalWorked,
            totalConfirmedCount: totalConfirmed,
            sameBandCount: sameBandCount,
            sameBandModeCount: sameBandModeCount,
            lastWorkedDate: lastWorkedDate,
            matchingPreviousQSOs: Array(matchingQSOs.suffix(15).reversed())
        )
    }

    private static func parseQSODate(_ record: QSORecordModel) -> Date? {
        let dateStr = record["QSO_DATE"].filter(\.isNumber)
        var timeStr = record["TIME_ON"].filter(\.isNumber)
        while timeStr.count < 6 { timeStr.append("0") }
        guard dateStr.count == 8, timeStr.count >= 4 else { return nil }

        let full = dateStr + String(timeStr.prefix(6))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: full)
    }
}
