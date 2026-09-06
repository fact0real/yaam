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
        var indexBySDRID: [String: Int] = [:]
        indexBySDRID.reserveCapacity(localRecords.count + incomingFields.count)
        var indexesByBaseKey: [String: [Int]] = [:]
        indexesByBaseKey.reserveCapacity(localRecords.count + incomingFields.count)
        var indexesByCallDateBand: [String: [Int]] = [:]
        indexesByCallDateBand.reserveCapacity(localRecords.count + incomingFields.count)

        var removedDuplicates = 0
        for record in localRecords {
            let key = QSOIdentity.exactKey(fields: record.fields)
            let baseKey = QSOIdentity.baseKey(fields: record.fields)
            guard !key.isEmpty || !baseKey.isEmpty else {
                records.append(record)
                continue
            }

            if let existingIndex = duplicateIndex(
                for: record.fields,
                records: records,
                indexByUniqueKey: indexByUniqueKey,
                indexBySDRID: indexBySDRID,
                indexesByBaseKey: indexesByBaseKey,
                indexesByCallDateBand: indexesByCallDateBand,
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
                    indexBySDRID: &indexBySDRID,
                    indexesByBaseKey: &indexesByBaseKey,
                    indexesByCallDateBand: &indexesByCallDateBand
                )
                removedDuplicates += 1
            } else {
                let index = records.count
                records.append(record)
                register(
                    record.fields,
                    at: index,
                    indexByUniqueKey: &indexByUniqueKey,
                    indexBySDRID: &indexBySDRID,
                    indexesByBaseKey: &indexesByBaseKey,
                    indexesByCallDateBand: &indexesByCallDateBand
                )
            }
        }

        var added = 0
        var updated = 0
        var skipped = 0

        for fields in incomingFields {
            let incoming = QSORecordModel(index: records.count + 1, fields: fields)
            let incomingKey = QSOIdentity.exactKey(fields: incoming.fields)
            let incomingBaseKey = QSOIdentity.baseKey(fields: incoming.fields)
            guard !incomingKey.isEmpty || !incomingBaseKey.isEmpty else {
                skipped += 1
                continue
            }
            if let existingIndex = duplicateIndex(
                for: incoming.fields,
                records: records,
                indexByUniqueKey: indexByUniqueKey,
                indexBySDRID: indexBySDRID,
                indexesByBaseKey: indexesByBaseKey,
                indexesByCallDateBand: indexesByCallDateBand,
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
                        indexBySDRID: &indexBySDRID,
                        indexesByBaseKey: &indexesByBaseKey,
                        indexesByCallDateBand: &indexesByCallDateBand
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
                indexBySDRID: &indexBySDRID,
                indexesByBaseKey: &indexesByBaseKey,
                indexesByCallDateBand: &indexesByCallDateBand
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
        let winner: [String: String]
        let loser: [String: String]

        if preferSDRCanonical && prefersSDRIdentity(rhs, over: lhs) {
            winner = rhs
            loser = lhs
        } else if preferSDRCanonical && prefersSDRIdentity(lhs, over: rhs) {
            winner = lhs
            loser = rhs
        } else if richnessScore(rhs) > richnessScore(lhs) {
            winner = rhs
            loser = lhs
        } else {
            winner = lhs
            loser = rhs
        }

        var merged = ImportReviewAnalyzer.mergeUpdate(incoming: loser, into: winner)
        if (merged["MODE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let fallbackMode = loser["MODE"], !fallbackMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged["MODE"] = fallbackMode
            }
        }
        return merged
    }

    private static func duplicateIndex(
        for fields: [String: String],
        records: [QSORecordModel],
        indexByUniqueKey: [String: Int],
        indexBySDRID: [String: Int],
        indexesByBaseKey: [String: [Int]],
        indexesByCallDateBand: [String: [Int]],
        allowRoundedSDRMatches: Bool
    ) -> Int? {
        // 1. Match by APP_SDR_CONTROL_ID
        let sdrID = (fields["APP_SDR_CONTROL_ID"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !sdrID.isEmpty, let idx = indexBySDRID[sdrID] {
            return idx
        }

        // 2. Exact match with same mode
        let exactKey = QSOIdentity.exactKey(fields: fields)
        if !exactKey.isEmpty, let exactIndex = indexByUniqueKey[exactKey] {
            return exactIndex
        }

        // 3. Match by Base Key (CALL|DATE|TIME|BAND) where modes are compatible
        let baseKey = QSOIdentity.baseKey(fields: fields)
        if !baseKey.isEmpty, let candidates = indexesByBaseKey[baseKey] {
            let mode = QSOIdentity.effectiveMode(fields)
            if let match = candidates.first(where: { index in
                records.indices.contains(index) &&
                QSOIdentity.areModesCompatible(mode, QSOIdentity.effectiveMode(records[index].fields))
            }) {
                return match
            }
        }

        // 4. Relaxed / Rounded SDR matches (within 300s or rounded :00 minute)
        if allowRoundedSDRMatches {
            let callDateBand = QSOIdentity.callDateBandKey(fields: fields)
            if !callDateBand.isEmpty, let candidates = indexesByCallDateBand[callDateBand] {
                if let match = candidates.first(where: { index in
                    records.indices.contains(index) &&
                    (isRoundedSDRDuplicate(records[index].fields, fields) ||
                     QSOIdentity.isSameQSO(lhs: records[index].fields, rhs: fields, timeToleranceSeconds: 300))
                }) {
                    return match
                }
            }
        }

        return nil
    }

    private static func register(
        _ fields: [String: String],
        at index: Int,
        indexByUniqueKey: inout [String: Int],
        indexBySDRID: inout [String: Int],
        indexesByBaseKey: inout [String: [Int]],
        indexesByCallDateBand: inout [String: [Int]]
    ) {
        let sdrID = (fields["APP_SDR_CONTROL_ID"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !sdrID.isEmpty {
            indexBySDRID[sdrID] = index
        }

        let exactKey = QSOIdentity.exactKey(fields: fields)
        if !exactKey.isEmpty {
            indexByUniqueKey[exactKey] = index
        }

        let baseKey = QSOIdentity.baseKey(fields: fields)
        if !baseKey.isEmpty {
            if !(indexesByBaseKey[baseKey] ?? []).contains(index) {
                indexesByBaseKey[baseKey, default: []].append(index)
            }
        }

        let callDateBand = QSOIdentity.callDateBandKey(fields: fields)
        if !callDateBand.isEmpty {
            if !(indexesByCallDateBand[callDateBand] ?? []).contains(index) {
                indexesByCallDateBand[callDateBand, default: []].append(index)
            }
        }
    }

    /// SDR-Control occasionally stores one rounded shadow row at `:00` and a
    /// second, more precise row in the same minute. Only that narrow pattern is
    /// accepted here so two genuine QSOs in a busy minute remain independent.
    private static func isRoundedSDRDuplicate(
        _ lhs: [String: String],
        _ rhs: [String: String]
    ) -> Bool {
        guard QSOIdentity.callDateBandKey(fields: lhs) == QSOIdentity.callDateBandKey(fields: rhs),
              QSOIdentity.areModesCompatible(QSOIdentity.effectiveMode(lhs), QSOIdentity.effectiveMode(rhs)),
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
