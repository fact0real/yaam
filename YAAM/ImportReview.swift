//
//  ImportReview.swift
//  YAAM
//

import Foundation

nonisolated enum ImportReviewKind: String, CaseIterable, Sendable {
    case newQSO
    case confirmationUpdate
    case duplicate
    case potentialConflict
    case invalid

    var title: String {
        switch self {
        case .newQSO: return "New"
        case .confirmationUpdate: return "Confirmation update"
        case .duplicate: return "Duplicate"
        case .potentialConflict: return "Needs review"
        case .invalid: return "Invalid"
        }
    }

    var systemImage: String {
        switch self {
        case .newQSO: return "plus.circle.fill"
        case .confirmationUpdate: return "arrow.triangle.2.circlepath.circle.fill"
        case .duplicate: return "doc.on.doc"
        case .potentialConflict: return "exclamationmark.triangle.fill"
        case .invalid: return "xmark.octagon.fill"
        }
    }
}

nonisolated struct ImportReviewItem: Identifiable, Sendable {
    let id: UUID
    let kind: ImportReviewKind
    let incomingFields: [String: String]
    let matchingRecordID: UUID?
    let note: String
    var isSelected: Bool

    var callsign: String { incomingFields["CALL"] ?? "" }
    var date: String { incomingFields["QSO_DATE"] ?? "" }
    var time: String { incomingFields["TIME_ON"] ?? incomingFields["TIME_OFF"] ?? "" }
    var band: String { incomingFields["BAND"] ?? "" }
    var mode: String { incomingFields["MODE"] ?? "" }
}

nonisolated struct PendingImportReview: Identifiable, Sendable {
    let id: UUID
    let sourceName: String
    let sourceURL: URL
    let sourceFormat: LogSourceFormat
    let destinationProfileID: UUID?
    let headers: [String]
    var items: [ImportReviewItem]

    func count(for kind: ImportReviewKind) -> Int {
        items.filter { $0.kind == kind }.count
    }

    var selectedCount: Int { items.filter(\.isSelected).count }
}

nonisolated enum ImportReviewAnalyzer {
    private static let confirmationFields = Set([
        "LOTW_QSL_RCVD", "QRZLOG_QSL_RCVD", "QSL_RCVD", "EQSL_QSL_RCVD"
    ])

    static func analyze(
        sourceName: String,
        sourceURL: URL,
        sourceFormat: LogSourceFormat,
        destinationProfileID: UUID?,
        headers: [String],
        incoming: [[String: String]],
        existing: [QSORecordModel]
    ) -> PendingImportReview {
        let exactLookup = Dictionary(grouping: existing, by: { normalizedUniqueKey($0.fields) })
        let relaxedLookup = Dictionary(grouping: existing, by: { relaxedKey($0.fields) })

        let items = incoming.map { rawFields -> ImportReviewItem in
            let fields = normalizedFields(rawFields)
            let call = fields["CALL"] ?? ""
            let date = cleanDigits(fields["QSO_DATE"] ?? "")

            guard !call.isEmpty, date.count == 8 else {
                return ImportReviewItem(
                    id: UUID(),
                    kind: .invalid,
                    incomingFields: fields,
                    matchingRecordID: nil,
                    note: "CALL and an 8-digit QSO_DATE are required.",
                    isSelected: false
                )
            }

            if let match = exactLookup[normalizedUniqueKey(fields)]?.first {
                let updates = meaningfulUpdates(incoming: fields, existing: match.fields)
                if updates.isEmpty {
                    return ImportReviewItem(
                        id: UUID(),
                        kind: .duplicate,
                        incomingFields: fields,
                        matchingRecordID: match.id,
                        note: "Already present in the active station log.",
                        isSelected: false
                    )
                }
                return ImportReviewItem(
                    id: UUID(),
                    kind: .confirmationUpdate,
                    incomingFields: fields,
                    matchingRecordID: match.id,
                    note: updates.sorted().joined(separator: ", "),
                    isSelected: true
                )
            }

            if let candidates = relaxedLookup[relaxedKey(fields)],
               let candidate = candidates.min(by: {
                   timeDistance($0.fields, fields) < timeDistance($1.fields, fields)
               }),
               timeDistance(candidate.fields, fields) <= 300 {
                return ImportReviewItem(
                    id: UUID(),
                    kind: .potentialConflict,
                    incomingFields: fields,
                    matchingRecordID: candidate.id,
                    note: "A similar QSO exists within five minutes. Select it only if both contacts are valid.",
                    isSelected: false
                )
            }

            return ImportReviewItem(
                id: UUID(),
                kind: .newQSO,
                incomingFields: fields,
                matchingRecordID: nil,
                note: "Ready to add to the active station log.",
                isSelected: true
            )
        }

        return PendingImportReview(
            id: UUID(),
            sourceName: sourceName,
            sourceURL: sourceURL,
            sourceFormat: sourceFormat,
            destinationProfileID: destinationProfileID,
            headers: headers,
            items: items
        )
    }

    static func mergeUpdate(incoming: [String: String], into existing: [String: String]) -> [String: String] {
        var merged = existing
        for (key, value) in incoming {
            let cleanKey = key.uppercased()
            let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanValue.isEmpty else { continue }

            if (merged[cleanKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged[cleanKey] = cleanValue
            } else if confirmationFields.contains(cleanKey), isAffirmative(cleanValue) {
                merged[cleanKey] = cleanValue
            }
        }
        return merged
    }

    private static func normalizedFields(_ fields: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map {
            ($0.key.uppercased(), $0.value.trimmingCharacters(in: .whitespacesAndNewlines))
        })
    }

    private static func meaningfulUpdates(incoming: [String: String], existing: [String: String]) -> [String] {
        incoming.compactMap { key, value in
            guard !value.isEmpty else { return nil }
            let oldValue = existing[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if oldValue.isEmpty { return key }
            if confirmationFields.contains(key), isAffirmative(value), !isAffirmative(oldValue) { return key }
            return nil
        }
    }

    private static func isAffirmative(_ value: String) -> Bool {
        ["Y", "V", "C", "CONFIRMED"].contains(value.uppercased())
    }

    private static func normalizedUniqueKey(_ fields: [String: String]) -> String {
        QSOIdentity.exactKey(fields: fields)
    }

    private static func relaxedKey(_ fields: [String: String]) -> String {
        QSOIdentity.relaxedKey(fields: fields)
    }

    private static func timeDistance(_ lhs: [String: String], _ rhs: [String: String]) -> Int {
        guard let lhsSeconds = seconds(lhs["TIME_ON"] ?? lhs["TIME_OFF"] ?? ""),
              let rhsSeconds = seconds(rhs["TIME_ON"] ?? rhs["TIME_OFF"] ?? "") else {
            return Int.max
        }
        return abs(lhsSeconds - rhsSeconds)
    }

    private static func seconds(_ raw: String) -> Int? {
        let clean = normalizedTime(raw)
        guard clean.count == 6 else { return nil }
        let hour = Int(clean.prefix(2)) ?? 0
        let minute = Int(clean.dropFirst(2).prefix(2)) ?? 0
        let second = Int(clean.dropFirst(4).prefix(2)) ?? 0
        guard hour < 24, minute < 60, second < 60 else { return nil }
        return hour * 3600 + minute * 60 + second
    }

    private static func normalizedTime(_ raw: String) -> String {
        let digits = cleanDigits(raw)
        if digits.count == 4 { return digits + "00" }
        return String(digits.prefix(6))
    }

    private static func cleanDigits(_ raw: String) -> String {
        String(raw.filter(\.isNumber))
    }
}
