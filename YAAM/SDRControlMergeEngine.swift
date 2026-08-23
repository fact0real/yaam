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
        incomingFields: [[String: String]]
    ) -> SDRControlMergeResult {
        var records: [QSORecordModel] = []
        records.reserveCapacity(localRecords.count + incomingFields.count)
        var indexByUniqueKey: [String: Int] = [:]
        indexByUniqueKey.reserveCapacity(localRecords.count + incomingFields.count)

        var removedDuplicates = 0
        for record in localRecords {
            let key = record.uniqueKey
            guard !key.isEmpty else {
                records.append(record)
                continue
            }

            if let existingIndex = indexByUniqueKey[key] {
                records[existingIndex].fields = richestMergedFields(
                    records[existingIndex].fields,
                    record.fields
                )
                removedDuplicates += 1
            } else {
                indexByUniqueKey[key] = records.count
                records.append(record)
            }
        }

        var added = 0
        var updated = 0
        var skipped = 0

        for fields in incomingFields {
            let incoming = QSORecordModel(index: records.count + 1, fields: fields)
            let incomingKey = incoming.uniqueKey
            guard !incomingKey.isEmpty else {
                skipped += 1
                continue
            }
            if let existingIndex = indexByUniqueKey[incomingKey] {
                let merged = richestMergedFields(
                    records[existingIndex].fields,
                    incoming.fields
                )
                if merged == records[existingIndex].fields {
                    skipped += 1
                } else {
                    records[existingIndex].fields = merged
                    updated += 1
                }
                continue
            }

            indexByUniqueKey[incomingKey] = records.count
            records.append(incoming)
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
        _ rhs: [String: String]
    ) -> [String: String] {
        if richnessScore(rhs) > richnessScore(lhs) {
            return ImportReviewAnalyzer.mergeUpdate(incoming: lhs, into: rhs)
        }
        return ImportReviewAnalyzer.mergeUpdate(incoming: rhs, into: lhs)
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
