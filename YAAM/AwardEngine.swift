//
//  AwardEngine.swift
//  YAAM
//

import Foundation

nonisolated enum AwardLifecycleStage: String, CaseIterable, Codable, Identifiable, Sendable {
    case worked
    case confirmed
    case credited
    case submitted
    case granted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .worked: return "Worked"
        case .confirmed: return "Confirmed"
        case .credited: return "Credited"
        case .submitted: return "Submitted"
        case .granted: return "Granted"
        }
    }

    var rank: Int {
        switch self {
        case .worked: return 0
        case .confirmed: return 1
        case .credited: return 2
        case .submitted: return 3
        case .granted: return 4
        }
    }
}

nonisolated struct AwardClaim: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var stationProfileID: UUID
    var awardID: String
    var stage: AwardLifecycleStage
    var submittedAt: Date?
    var grantedAt: Date?
    var note: String
    var updatedAt: Date

    init(
        stationProfileID: UUID,
        awardID: String,
        stage: AwardLifecycleStage,
        submittedAt: Date? = nil,
        grantedAt: Date? = nil,
        note: String = "",
        updatedAt: Date = Date()
    ) {
        id = "\(stationProfileID.uuidString.lowercased())|\(awardID)"
        self.stationProfileID = stationProfileID
        self.awardID = awardID
        self.stage = stage
        self.submittedAt = submittedAt
        self.grantedAt = grantedAt
        self.note = note
        self.updatedAt = updatedAt
    }
}

nonisolated struct AwardProgress: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var family: String
    var icon: String
    var worked: Int
    var confirmed: Int
    var credited: Int
    var target: Int?
    var administrativeStage: AwardLifecycleStage?
    var detail: String
    var sourceNote: String

    var percent: Double? {
        guard let target, target > 0 else { return nil }
        return min(100, Double(confirmed) / Double(target) * 100)
    }

    var remaining: Int? {
        guard let target else { return nil }
        return max(0, target - confirmed)
    }

    var earnedLocally: Bool {
        guard let target else { return false }
        return confirmed >= target
    }

    var effectiveStage: AwardLifecycleStage {
        if let administrativeStage { return administrativeStage }
        if let target, credited >= target { return .credited }
        if earnedLocally { return .confirmed }
        if confirmed > 0 { return .confirmed }
        return .worked
    }
}

nonisolated enum AwardEngine {
    static func evaluate(records: [QSORecordModel], claims: [AwardClaim]) -> [AwardProgress] {
        let claimsByAward = Dictionary(uniqueKeysWithValues: claims.map { ($0.awardID, $0) })
        var dxccWorked = Set<String>()
        var dxccConfirmed = Set<String>()
        var dxccCredited = Set<String>()
        var continentWorked = Set<String>()
        var continentConfirmed = Set<String>()
        var statesWorked = Set<String>()
        var statesConfirmed = Set<String>()
        var gridsWorkedByBand: [String: Set<String>] = [:]
        var gridsConfirmedByBand: [String: Set<String>] = [:]
        var iotaWorked = Set<String>()
        var iotaConfirmed = Set<String>()
        var potaHunterWorked = Set<String>()
        var potaHunterConfirmed = Set<String>()
        var sotaHunterWorked = Set<String>()
        var sotaHunterConfirmed = Set<String>()
        var potaActivationCounts: [String: Int] = [:]
        var sotaActivationQSOs = Set<String>()

        for record in records {
            let confirmed = record.isConfirmed
            let credit = record["CREDIT_GRANTED"].uppercased()
            let dxcc = cleanEntity(record["DXCC"])
            if let dxcc {
                dxccWorked.insert(dxcc)
                if confirmed { dxccConfirmed.insert(dxcc) }
                if credit.contains("DXCC") { dxccCredited.insert(dxcc) }
            }

            let continent = record["CONT"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if validContinents.contains(continent) {
                continentWorked.insert(continent)
                if confirmed { continentConfirmed.insert(continent) }
            }

            let state = record["STATE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if validUSStates.contains(state) {
                statesWorked.insert(state)
                if confirmed { statesConfirmed.insert(state) }
            }

            let band = record["BAND"].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            for grid in fourCharacterGrids(record) {
                gridsWorkedByBand[band, default: []].insert(grid)
                if confirmed { gridsConfirmedByBand[band, default: []].insert(grid) }
            }

            for reference in references(record["IOTA"]) {
                iotaWorked.insert(reference)
                if confirmed { iotaConfirmed.insert(reference) }
            }
            for reference in references(record["POTA_REF"], fallback: signalReference(record, program: "POTA", mine: false)) {
                potaHunterWorked.insert(reference)
                if confirmed { potaHunterConfirmed.insert(reference) }
            }
            for reference in references(record["SOTA_REF"], fallback: signalReference(record, program: "SOTA", mine: false)) {
                sotaHunterWorked.insert(reference)
                if confirmed { sotaHunterConfirmed.insert(reference) }
            }

            let date = record["QSO_DATE"]
            for reference in references(record["MY_POTA_REF"], fallback: signalReference(record, program: "POTA", mine: true)) {
                let key = "\(reference)|\(date)"
                potaActivationCounts[key, default: 0] += 1
            }
            for reference in references(record["MY_SOTA_REF"], fallback: signalReference(record, program: "SOTA", mine: true)) {
                sotaActivationQSOs.insert("\(reference)|\(date)|\(record.uniqueKey)")
            }
        }

        let completedPOTAActivations = potaActivationCounts.values.filter { $0 >= 10 }.count
        let uniquePOTAParksActivated = Set(potaActivationCounts.keys.map { $0.components(separatedBy: "|").first ?? "" }).filter { !$0.isEmpty }.count
        let uniqueSOTASummitsActivated = Set(sotaActivationQSOs.compactMap { $0.components(separatedBy: "|").first }).count

        let definitions: [AwardProgress] = [
            progress("dxcc-mixed", "DXCC Mixed", "DXCC", "globe.americas.fill", dxccWorked.count, dxccConfirmed.count, dxccCredited.count, 100, claimsByAward, "Unique DXCC entities", "Local estimate; ARRL determines accepted credits and grant status."),
            progress("wac-mixed", "Worked All Continents", "WAC", "globe", continentWorked.count, continentConfirmed.count, 0, 6, claimsByAward, "Six populated continents", "Confirmation rules depend on the issuing organization."),
            progress("was-mixed", "Worked All States", "WAS", "map.fill", statesWorked.count, statesConfirmed.count, 0, 50, claimsByAward, "US states", "State codes are read from ADIF STATE; award credit remains authoritative at ARRL."),
            progress("vucc-6m", "VUCC 6 m", "VUCC", "square.grid.3x3.fill", gridsWorkedByBand["6m"]?.count ?? 0, gridsConfirmedByBand["6m"]?.count ?? 0, 0, 100, claimsByAward, "Four-character Maidenhead grids", "Local 6 m estimate using confirmed grid fields."),
            progress("vucc-2m", "VUCC 2 m", "VUCC", "square.grid.3x3", gridsWorkedByBand["2m"]?.count ?? 0, gridsConfirmedByBand["2m"]?.count ?? 0, 0, 100, claimsByAward, "Four-character Maidenhead grids", "Local 2 m estimate using confirmed grid fields."),
            progress("vucc-70cm", "VUCC 70 cm", "VUCC", "circle.grid.cross", gridsWorkedByBand["70cm"]?.count ?? 0, gridsConfirmedByBand["70cm"]?.count ?? 0, 0, 50, claimsByAward, "Four-character Maidenhead grids", "Local 70 cm estimate; ARRL checks boundary and credit rules."),
            progress("iota-100", "IOTA 100", "IOTA", "water.waves", iotaWorked.count, iotaConfirmed.count, 0, 100, claimsByAward, "Unique IOTA groups", "Local milestone tracker, not an RSGB credit decision."),
            progress("pota-hunter-100", "POTA Hunter 100", "POTA", "tree.fill", potaHunterWorked.count, potaHunterConfirmed.count, 0, 100, claimsByAward, "Unique park references", "A planning milestone; POTA award rules and server records remain authoritative."),
            progress("pota-activations", "POTA Activations", "POTA", "figure.hiking", uniquePOTAParksActivated, completedPOTAActivations, 0, nil, claimsByAward, "\(completedPOTAActivations) qualifying park-days (10+ QSOs)", "Counts qualifying UTC park-days locally; POTA validates official activations."),
            progress("sota-chaser-100", "SOTA Chaser 100", "SOTA", "mountain.2.fill", sotaHunterWorked.count, sotaHunterConfirmed.count, 0, 100, claimsByAward, "Unique summit references", "Reference milestone only; SOTA points require the official summit database."),
            progress("sota-activations", "SOTA Activations", "SOTA", "mountain.2", uniqueSOTASummitsActivated, uniqueSOTASummitsActivated, 0, nil, claimsByAward, "Unique activated summits", "QSO-based activity summary; official SOTA validation and points are external.")
        ]
        return definitions.sorted {
            if $0.effectiveStage.rank != $1.effectiveStage.rank { return $0.effectiveStage.rank > $1.effectiveStage.rank }
            return ($0.percent ?? -1) > ($1.percent ?? -1)
        }
    }

    private static func progress(
        _ id: String,
        _ title: String,
        _ family: String,
        _ icon: String,
        _ worked: Int,
        _ confirmed: Int,
        _ credited: Int,
        _ target: Int?,
        _ claims: [String: AwardClaim],
        _ detail: String,
        _ sourceNote: String
    ) -> AwardProgress {
        AwardProgress(
            id: id,
            title: title,
            family: family,
            icon: icon,
            worked: worked,
            confirmed: confirmed,
            credited: credited,
            target: target,
            administrativeStage: claims[id]?.stage,
            detail: detail,
            sourceNote: sourceNote
        )
    }

    private static func cleanEntity(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty, clean != "0", clean != "UNKNOWN" else { return nil }
        return clean
    }

    private static func references(_ value: String, fallback: String = "") -> Set<String> {
        let source = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value
        return Set(source
            .uppercased()
            .components(separatedBy: CharacterSet(charactersIn: ",; "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    private static func signalReference(_ record: QSORecordModel, program: String, mine: Bool) -> String {
        let sig = record[mine ? "MY_SIG" : "SIG"].uppercased()
        return sig == program ? record[mine ? "MY_SIG_INFO" : "SIG_INFO"] : ""
    }

    static func fourCharacterGrids(_ record: QSORecordModel) -> Set<String> {
        var values = references(record["VUCC_GRIDS"])
        if values.isEmpty { values = references(record["GRIDSQUARE"]) }
        var grids = Set(values.compactMap(GridLocator.fourCharacterGrid(from:)))
        if grids.isEmpty,
           let derived = GridLocator.fourCharacterGrid(
                latitude: record["LAT"].isEmpty ? record["LATITUDE"] : record["LAT"],
                longitude: record["LON"].isEmpty ? record["LONGITUDE"] : record["LON"]
           ) {
            grids.insert(derived)
        }
        return grids
    }

    private static let validContinents: Set<String> = ["AF", "AS", "EU", "NA", "OC", "SA"]
    private static let validUSStates: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS",
        "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY",
        "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV",
        "WI", "WY"
    ]
}
