//
//  DuplicateReview.swift
//  YAAM
//

import Foundation

nonisolated struct DuplicateQSOGroup: Identifiable, Sendable {
    let id: String
    let recordIDs: [UUID]
    let keeperID: UUID
    let keeperRow: Int
    let callsign: String
    let date: String
    let time: String
    let band: String
    let mode: String

    var copyCount: Int { recordIDs.count }
    var removableCount: Int { max(0, copyCount - 1) }
}

nonisolated struct DuplicateReview: Identifiable, Sendable {
    let id = UUID()
    let stationProfileID: UUID?
    let groups: [DuplicateQSOGroup]
    var selectedGroupIDs: Set<String>

    var selectedGroups: [DuplicateQSOGroup] {
        groups.filter { selectedGroupIDs.contains($0.id) }
    }

    var selectedRemovalCount: Int {
        selectedGroups.reduce(0) { $0 + $1.removableCount }
    }

    var totalRemovalCount: Int {
        groups.reduce(0) { $0 + $1.removableCount }
    }
}

nonisolated struct DuplicateCleanupResult: Sendable {
    let records: [QSORecordModel]
    let removedCount: Int
    let mergedGroupCount: Int
}

nonisolated enum DuplicateQSOAnalyzer {
    static func analyze(records: [QSORecordModel], stationProfileID: UUID?) -> DuplicateReview {
        let validRecords = records.filter { !identityKey($0.fields).isEmpty }
        let grouped = Dictionary(grouping: validRecords, by: { identityKey($0.fields) })
        let groups = grouped.compactMap { key, copies -> DuplicateQSOGroup? in
            guard copies.count > 1, let keeper = copies.max(by: { keeperScore($0) < keeperScore($1) }) else {
                return nil
            }
            return DuplicateQSOGroup(
                id: key,
                recordIDs: copies.map(\.id),
                keeperID: keeper.id,
                keeperRow: keeper.index,
                callsign: clean(keeper["CALL"]),
                date: cleanDigits(keeper["QSO_DATE"]),
                time: normalizeTime(keeper["TIME_ON"].isEmpty ? keeper["TIME_OFF"] : keeper["TIME_ON"]),
                band: resolvedBand(keeper.fields),
                mode: effectiveMode(keeper.fields)
            )
        }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.time != $1.time { return $0.time > $1.time }
            return $0.callsign < $1.callsign
        }

        return DuplicateReview(
            stationProfileID: stationProfileID,
            groups: groups,
            selectedGroupIDs: Set(groups.map(\.id))
        )
    }

    static func clean(records: [QSORecordModel], review: DuplicateReview) -> DuplicateCleanupResult {
        let selected = review.selectedGroups
        guard !selected.isEmpty else {
            return DuplicateCleanupResult(records: records, removedCount: 0, mergedGroupCount: 0)
        }

        var output = records
        var indexByID = Dictionary(uniqueKeysWithValues: output.indices.map { (output[$0].id, $0) })
        var removalIDs = Set<UUID>()
        var mergedGroupCount = 0

        for group in selected {
            guard let keeperIndex = indexByID[group.keeperID] else { continue }
            var mergedFields = output[keeperIndex].fields
            var didFindDuplicate = false

            for duplicateID in group.recordIDs where duplicateID != group.keeperID {
                guard let duplicateIndex = indexByID[duplicateID] else { continue }
                mergedFields = ImportReviewAnalyzer.mergeUpdate(
                    incoming: output[duplicateIndex].fields,
                    into: mergedFields
                )
                removalIDs.insert(duplicateID)
                didFindDuplicate = true
            }

            if didFindDuplicate {
                output[keeperIndex].fields = mergedFields
                mergedGroupCount += 1
            }
        }

        output.removeAll { removalIDs.contains($0.id) }
        for index in output.indices { output[index].index = index + 1 }
        indexByID.removeAll(keepingCapacity: false)
        return DuplicateCleanupResult(
            records: output,
            removedCount: removalIDs.count,
            mergedGroupCount: mergedGroupCount
        )
    }

    private static func identityKey(_ fields: [String: String]) -> String {
        let call = clean(fields["CALL"] ?? "")
        let date = cleanDigits(fields["QSO_DATE"] ?? "")
        let time = normalizeTime(fields["TIME_ON"] ?? fields["TIME_OFF"] ?? "")
        guard !call.isEmpty, date.count == 8, time.count == 6 else { return "" }
        let station = clean(fields["STATION_CALLSIGN"] ?? fields["OPERATOR"] ?? "")
        return "\(station)|\(call)|\(date)|\(time)|\(resolvedBand(fields))|\(effectiveMode(fields))"
    }

    private static func keeperScore(_ record: QSORecordModel) -> Int {
        let populatedFields = record.fields.values.reduce(0) {
            $0 + ($1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
        }
        return (record.isConfirmed ? 100_000 : 0) + populatedFields * 100 - record.index
    }

    private static func resolvedBand(_ fields: [String: String]) -> String {
        ADIFConversionFilter.resolvedBand(for: fields).uppercased()
    }

    private static func effectiveMode(_ fields: [String: String]) -> String {
        let submode = clean(fields["SUBMODE"] ?? "")
        return submode.isEmpty ? clean(fields["MODE"] ?? "") : submode
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func cleanDigits(_ value: String) -> String {
        String(value.filter(\.isNumber))
    }
}

extension AppState {
    func prepareDuplicateReview() {
        guard !qsoRecords.isEmpty, !isAnalyzingDuplicates else { return }
        let records = qsoRecords
        let profileID = activeStationProfileID
        isAnalyzingDuplicates = true
        appendLog("Scanning the active station log for exact duplicate QSOs...")

        Task { @MainActor [weak self] in
            let review = await Task.detached(priority: .userInitiated) {
                DuplicateQSOAnalyzer.analyze(records: records, stationProfileID: profileID)
            }.value
            guard let self else { return }
            self.isAnalyzingDuplicates = false
            guard self.activeStationProfileID == profileID else { return }

            if review.groups.isEmpty {
                self.alertTitle = "No Duplicates Found"
                self.alertMessage = "The active station log has no exact duplicate QSOs."
                self.showAlert = true
                self.playActivitySound(.success)
            } else {
                self.duplicateReview = review
                self.showDuplicateReviewSheet = true
                self.appendLog("Duplicate review found \(review.groups.count) group(s) containing \(review.totalRemovalCount) extra QSO row(s).")
            }
        }
    }

    func setDuplicateGroupSelection(groupID: String, selected: Bool) {
        guard var review = duplicateReview else { return }
        if selected {
            review.selectedGroupIDs.insert(groupID)
        } else {
            review.selectedGroupIDs.remove(groupID)
        }
        duplicateReview = review
    }

    func selectAllDuplicateGroups(_ selected: Bool) {
        guard var review = duplicateReview else { return }
        review.selectedGroupIDs = selected ? Set(review.groups.map(\.id)) : []
        duplicateReview = review
    }

    func cancelDuplicateReview() {
        duplicateReview = nil
        showDuplicateReviewSheet = false
    }

    func commitDuplicateCleanup() {
        guard let review = duplicateReview,
              review.stationProfileID == activeStationProfileID,
              review.selectedRemovalCount > 0 else { return }
        guard createDestructiveCheckpointIfNeeded(reason: "Before removing duplicate QSOs") else { return }

        let result = DuplicateQSOAnalyzer.clean(records: qsoRecords, review: review)
        guard result.removedCount > 0 else { return }
        qsoRecords = result.records
        selectedRecordIDs.subtract(Set(review.selectedGroups.flatMap(\.recordIDs)))
        autoSaveActiveWorkspace()
        refreshAwardProgress()
        updateMobileCompanionSnapshot()
        duplicateReview = nil
        showDuplicateReviewSheet = false
        refreshDatabaseSafetyState()
        alertTitle = "Duplicates Removed"
        alertMessage = "Removed \(result.removedCount) extra QSO row(s) from \(result.mergedGroupCount) duplicate group(s). Missing and confirmation fields were merged into the retained records, and a restore point was created first."
        showAlert = true
        appendLog("Duplicate cleanup removed \(result.removedCount) extra QSO row(s) after merging the retained records.")
        playActivitySound(.success)
    }
}
