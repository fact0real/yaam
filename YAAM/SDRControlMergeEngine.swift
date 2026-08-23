//
//  SDRControlMergeEngine.swift
//  YAAM
//

import Foundation

nonisolated struct SDRControlMergeResult: Sendable {
    let records: [QSORecordModel]
    let summary: MergeSummary
    let removedDuplicates: Int
}

/// Performs the potentially expensive SDR-Control merge without publishing an
/// intermediate array for every QSO. The caller can apply the finished array in
/// one UI update.
nonisolated enum SDRControlMergeEngine {
    static func merge(
        localRecords: [QSORecordModel],
        incomingFields: [[String: String]],
        allowRoundedSDRMatches: Bool = false
    ) -> SDRControlMergeResult {
        var records: [QSORecordModel] = []
        records.reserveCapacity(localRecords.count + incomingFields.count)
        var indexByUniqueKey: [String: Int] = [:]
        indexByUniqueKey.reserveCapacity(localRecords.count + incomingFields.count)
        var indexesByRelaxedKey: [String: [Int]] = [:]
        indexesByRelaxedKey.reserveCapacity(localRecords.count + incomingFields.count)

        var removedDuplicates = 0
        for record in localRecords {
            let key = QSOIdentity.exactKey(fields: record.fields)
            guard !key.isEmpty else {
                records.append(record)
                continue
            }

            if let existingIndex = duplicateIndex(
                for: record.fields,
                records: records,
                indexByUniqueKey: indexByUniqueKey,
                indexesByRelaxedKey: indexesByRelaxedKey,
                allowRoundedSDRMatches: allowRoundedSDRMatches
            ) {
                records[existingIndex].fields = richestMergedFields(
                    records[existingIndex].fields,
                    record.fields,
                    preferSDRCanonical: allowRoundedSDRMatches
                )
                register(
                    records[existingIndex].fields,
                    at: existingIndex,
                    indexByUniqueKey: &indexByUniqueKey,
                    indexesByRelaxedKey: &indexesByRelaxedKey
                )
                removedDuplicates += 1
            } else {
                let index = records.count
                records.append(record)
                register(
                    record.fields,
                    at: index,
                    indexByUniqueKey: &indexByUniqueKey,
                    indexesByRelaxedKey: &indexesByRelaxedKey
                )
            }
        }

        var added = 0
        var updated = 0
        var skipped = 0

        for fields in incomingFields {
            let incoming = QSORecordModel(index: records.count + 1, fields: fields)
            let incomingKey = QSOIdentity.exactKey(fields: incoming.fields)
            guard !incomingKey.isEmpty else {
                skipped += 1
                continue
            }
            if let existingIndex = duplicateIndex(
                for: incoming.fields,
                records: records,
                indexByUniqueKey: indexByUniqueKey,
                indexesByRelaxedKey: indexesByRelaxedKey,
                allowRoundedSDRMatches: allowRoundedSDRMatches
            ) {
                let merged = richestMergedFields(
                    records[existingIndex].fields,
                    incoming.fields,
                    preferSDRCanonical: allowRoundedSDRMatches
                )
                if merged == records[existingIndex].fields {
                    skipped += 1
                } else {
                    records[existingIndex].fields = merged
                    register(
                        merged,
                        at: existingIndex,
                        indexByUniqueKey: &indexByUniqueKey,
                        indexesByRelaxedKey: &indexesByRelaxedKey
                    )
                    updated += 1
                }
                continue
            }

            let index = records.count
            records.append(incoming)
            register(
                incoming.fields,
                at: index,
                indexByUniqueKey: &indexByUniqueKey,
                indexesByRelaxedKey: &indexesByRelaxedKey
            )
            added += 1
        }

        for index in records.indices {
            records[index].index = index + 1
        }

        return SDRControlMergeResult(
            records: records,
            summary: MergeSummary(added: added, updated: updated, skipped: skipped),
            removedDuplicates: removedDuplicates
        )
    }

    /// Keeps the most complete record as the conflict winner, then fills every
    /// missing field from its duplicate. The caller retains the original row ID.
    private static func richestMergedFields(
        _ lhs: [String: String],
        _ rhs: [String: String],
        preferSDRCanonical: Bool
    ) -> [String: String] {
        if preferSDRCanonical {
            if prefersSDRIdentity(rhs, over: lhs) {
                return ImportReviewAnalyzer.mergeUpdate(incoming: lhs, into: rhs)
            }
            return ImportReviewAnalyzer.mergeUpdate(incoming: rhs, into: lhs)
        }

        if richnessScore(rhs) > richnessScore(lhs) {
            return ImportReviewAnalyzer.mergeUpdate(incoming: lhs, into: rhs)
        }
        return ImportReviewAnalyzer.mergeUpdate(incoming: rhs, into: lhs)
    }

    private static func duplicateIndex(
        for fields: [String: String],
        records: [QSORecordModel],
        indexByUniqueKey: [String: Int],
        indexesByRelaxedKey: [String: [Int]],
        allowRoundedSDRMatches: Bool
    ) -> Int? {
        let exactKey = QSOIdentity.exactKey(fields: fields)
        if let exactIndex = indexByUniqueKey[exactKey] {
            return exactIndex
        }
        guard allowRoundedSDRMatches else { return nil }

        let relaxedKey = QSOIdentity.relaxedKey(fields: fields)
        guard !relaxedKey.isEmpty,
              let candidates = indexesByRelaxedKey[relaxedKey] else {
            return nil
        }
        return candidates.first { index in
            records.indices.contains(index)
                && isRoundedSDRDuplicate(records[index].fields, fields)
        }
    }

    private static func register(
        _ fields: [String: String],
        at index: Int,
        indexByUniqueKey: inout [String: Int],
        indexesByRelaxedKey: inout [String: [Int]]
    ) {
        let exactKey = QSOIdentity.exactKey(fields: fields)
        if !exactKey.isEmpty {
            indexByUniqueKey[exactKey] = index
        }

        let relaxedKey = QSOIdentity.relaxedKey(fields: fields)
        guard !relaxedKey.isEmpty else { return }
        if !(indexesByRelaxedKey[relaxedKey] ?? []).contains(index) {
            indexesByRelaxedKey[relaxedKey, default: []].append(index)
        }
    }

    /// SDR-Control occasionally stores one rounded shadow row at `:00` and a
    /// second, more precise row in the same minute. Only that narrow pattern is
    /// accepted here so two genuine QSOs in a busy minute remain independent.
    private static func isRoundedSDRDuplicate(
        _ lhs: [String: String],
        _ rhs: [String: String]
    ) -> Bool {
        guard QSOIdentity.relaxedKey(fields: lhs) == QSOIdentity.relaxedKey(fields: rhs),
              let lhsTime = QSOIdentity.secondsFromMidnight(lhs),
              let rhsTime = QSOIdentity.secondsFromMidnight(rhs),
              lhsTime / 60 == rhsTime / 60 else {
            return false
        }

        let lhsSecond = lhsTime % 60
        let rhsSecond = rhsTime % 60
        guard (lhsSecond == 0) != (rhsSecond == 0),
              let lhsFrequency = frequencyMHz(lhs["FREQ"] ?? ""),
              let rhsFrequency = frequencyMHz(rhs["FREQ"] ?? "") else {
            return false
        }
        return abs(lhsFrequency - rhsFrequency) <= 0.001
    }

    private static func prefersSDRIdentity(
        _ candidate: [String: String],
        over current: [String: String]
    ) -> Bool {
        let candidateHasPreciseTime = hasNonZeroSeconds(candidate)
        let currentHasPreciseTime = hasNonZeroSeconds(current)
        if candidateHasPreciseTime != currentHasPreciseTime {
            return candidateHasPreciseTime
        }

        let candidateFrequencyPrecision = frequencyDecimalPrecision(candidate["FREQ"] ?? "")
        let currentFrequencyPrecision = frequencyDecimalPrecision(current["FREQ"] ?? "")
        if candidateFrequencyPrecision != currentFrequencyPrecision {
            return candidateFrequencyPrecision > currentFrequencyPrecision
        }
        return richnessScore(candidate) > richnessScore(current)
    }

    private static func hasNonZeroSeconds(_ fields: [String: String]) -> Bool {
        guard let seconds = QSOIdentity.secondsFromMidnight(fields) else { return false }
        return seconds % 60 != 0
    }

    private static func frequencyDecimalPrecision(_ rawValue: String) -> Int {
        let normalized = rawValue.replacingOccurrences(of: ",", with: ".")
        guard let decimal = normalized.firstIndex(of: ".") else { return 0 }
        return normalized[normalized.index(after: decimal)...].prefix(while: \.isNumber).count
    }

    private static func frequencyMHz(_ rawValue: String) -> Double? {
        let upper = rawValue.uppercased()
        let numeric = rawValue
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard var value = Double(numeric), value > 0 else { return nil }
        if upper.contains("GHZ") {
            value *= 1_000
        } else if upper.contains("KHZ") {
            value /= 1_000
        } else if (upper.contains("HZ") && !upper.contains("MHZ")) || value >= 1_000_000 {
            value /= 1_000_000
        }
        return value
    }

    private static func richnessScore(_ fields: [String: String]) -> Int {
        let normalized = fields.reduce(into: [String: String]()) { values, field in
            let key = field.key.uppercased()
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if (values[key] ?? "").isEmpty || !value.isEmpty {
                values[key] = value
            }
        }
        let populatedCount = normalized.values.reduce(into: 0) { count, value in
            if !value.isEmpty { count += 1 }
        }
        let confirmationFields = [
            "QSL_RCVD", "LOTW_QSL_RCVD", "QRZLOG_QSL_RCVD", "EQSL_QSL_RCVD"
        ]
        let confirmedCount = confirmationFields.reduce(into: 0) { count, key in
            if isAffirmative(normalized[key] ?? "") { count += 1 }
        }
        let highValueFields = [
            "NAME", "EMAIL", "COUNTRY", "DXCC", "GRIDSQUARE", "LAT", "LON",
            "CQZ", "ITUZ", "QSL_RCVD_DATE", "LOTW_QSLRDATE", "QRZLOG_QSLRDATE",
            "EQSL_QSLRDATE", "APP_QRZLOG_LOGID", "APP_LOTW_QSO_TIMESTAMP"
        ]
        let highValueCount = highValueFields.reduce(into: 0) { count, key in
            if !(normalized[key] ?? "").isEmpty { count += 1 }
        }
        return confirmedCount * 100_000 + highValueCount * 1_000 + populatedCount
    }

    private static func isAffirmative(_ value: String) -> Bool {
        ["Y", "YES", "TRUE", "1", "C", "CONFIRMED", "RECEIVED"].contains(value.uppercased())
    }
}
