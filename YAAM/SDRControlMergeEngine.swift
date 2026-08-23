//
//  SDRControlMergeEngine.swift
//  YAAM
//

import Foundation

nonisolated struct SDRControlMergeResult: Sendable {
    let records: [QSORecordModel]
    let summary: MergeSummary
}

/// Performs the potentially expensive SDR-Control merge without publishing an
/// intermediate array for every QSO. The caller can apply the finished array in
/// one UI update.
nonisolated enum SDRControlMergeEngine {
    static func merge(
        localRecords: [QSORecordModel],
        incomingFields: [[String: String]]
    ) -> SDRControlMergeResult {
        var records = localRecords
        var indexByUniqueKey: [String: Int] = [:]
        indexByUniqueKey.reserveCapacity(localRecords.count + incomingFields.count)

        for (index, record) in records.enumerated() where indexByUniqueKey[record.uniqueKey] == nil {
            indexByUniqueKey[record.uniqueKey] = index
        }

        var added = 0
        var updated = 0
        var skipped = 0

        for fields in incomingFields {
            let incoming = QSORecordModel(index: records.count + 1, fields: fields)
            if let existingIndex = indexByUniqueKey[incoming.uniqueKey] {
                let merged = ImportReviewAnalyzer.mergeUpdate(
                    incoming: incoming.fields,
                    into: records[existingIndex].fields
                )
                if merged == records[existingIndex].fields {
                    skipped += 1
                } else {
                    records[existingIndex].fields = merged
                    updated += 1
                }
                continue
            }

            indexByUniqueKey[incoming.uniqueKey] = records.count
            records.append(incoming)
            added += 1
        }

        for index in records.indices {
            records[index].index = index + 1
        }

        return SDRControlMergeResult(
            records: records,
            summary: MergeSummary(added: added, updated: updated, skipped: skipped)
        )
    }
}
