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
    let matchDescription: String
    let mergedFieldCount: Int

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
    private static let nearDuplicateWindowSeconds = 300

    static func analyze(records: [QSORecordModel], stationProfileID: UUID?) -> DuplicateReview {
        let validRecords = records.filter { !identityKey($0.fields).isEmpty }
        let grouped = Dictionary(grouping: validRecords, by: { relaxedIdentityKey($0.fields) })
        let groups = grouped.flatMap { _, copies in
            duplicateClusters(from: copies).compactMap(makeGroup)
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

    private static func duplicateClusters(from records: [QSORecordModel]) -> [[QSORecordModel]] {
        let sorted = records.sorted {
            let left = seconds($0.fields) ?? 0
            let right = seconds($1.fields) ?? 0
            if left != right { return left < right }
            return $0.index < $1.index
        }

        var clusters: [[QSORecordModel]] = []
        var current: [QSORecordModel] = []
        var anchorSeconds: Int?

        for record in sorted {
            guard let recordSeconds = seconds(record.fields) else { continue }
            if let anchor = anchorSeconds, abs(recordSeconds - anchor) <= nearDuplicateWindowSeconds {
                current.append(record)
            } else {
                if current.count > 1 { clusters.append(current) }
                current = [record]
                anchorSeconds = recordSeconds
            }
        }
        if current.count > 1 { clusters.append(current) }
        return clusters
    }

    private static func makeGroup(_ copies: [QSORecordModel]) -> DuplicateQSOGroup? {
        guard copies.count > 1, let keeper = copies.max(by: { keeperScore($0) < keeperScore($1) }) else {
            return nil
        }

        let times = copies.compactMap { seconds($0.fields) }
        let spread = (times.max() ?? 0) - (times.min() ?? 0)
        let mergedFields = copies
            .filter { $0.id != keeper.id }
            .reduce(keeper.fields) { merged, duplicate in
                ImportReviewAnalyzer.mergeUpdate(incoming: duplicate.fields, into: merged)
            }
        let mergedFieldCount = mergedFields.filter { key, value in
            let oldValue = keeper.fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return oldValue.isEmpty && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count

        return DuplicateQSOGroup(
            id: "\(relaxedIdentityKey(keeper.fields))|\(times.min() ?? 0)-\(times.max() ?? 0)",
            recordIDs: copies.map(\.id),
            keeperID: keeper.id,
            keeperRow: keeper.index,
            callsign: clean(keeper["CALL"]),
            date: cleanDigits(keeper["QSO_DATE"]),
            time: normalizeTime(keeper["TIME_ON"].isEmpty ? keeper["TIME_OFF"] : keeper["TIME_ON"]),
            band: resolvedBand(keeper.fields),
            mode: effectiveMode(keeper.fields),
            matchDescription: spread == 0 ? "Exact UTC match" : "Within \(spread) seconds",
            mergedFieldCount: mergedFieldCount
        )
    }

    private static func identityKey(_ fields: [String: String]) -> String {
        let call = clean(fields["CALL"] ?? "")
        let date = cleanDigits(fields["QSO_DATE"] ?? "")
        let time = normalizeTime(fields["TIME_ON"] ?? fields["TIME_OFF"] ?? "")
        guard !call.isEmpty, date.count == 8, time.count == 6 else { return "" }
        return "\(relaxedIdentityKey(fields))|\(time)"
    }

    private static func relaxedIdentityKey(_ fields: [String: String]) -> String {
        let call = clean(fields["CALL"] ?? "")
        let date = cleanDigits(fields["QSO_DATE"] ?? "")
        let band = resolvedBand(fields)
        let mode = effectiveMode(fields)
        return "\(call)|\(date)|\(band)|\(mode)"
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

    private static func seconds(_ fields: [String: String]) -> Int? {
        let time = normalizeTime(fields["TIME_ON"] ?? fields["TIME_OFF"] ?? "")
        guard time.count == 6,
              let hour = Int(time.prefix(2)),
              let minute = Int(time.dropFirst(2).prefix(2)),
              let second = Int(time.dropFirst(4).prefix(2)),
              hour < 24,
              minute < 60,
              second < 60 else {
            return nil
        }
        return hour * 3600 + minute * 60 + second
    }
}

extension AppState {
    @discardableResult
    func reconcileDuplicateQSOsAfterImport(sourceName: String) -> DuplicateCleanupResult? {
        guard !qsoRecords.isEmpty else { return nil }
        let review = DuplicateQSOAnalyzer.analyze(records: qsoRecords, stationProfileID: activeStationProfileID)
        guard review.totalRemovalCount > 0 else { return nil }
        guard createDestructiveCheckpointIfNeeded(reason: "Before automatic duplicate cleanup after \(sourceName)") else {
            return nil
        }

        let result = DuplicateQSOAnalyzer.clean(records: qsoRecords, review: review)
        guard result.removedCount > 0 else { return nil }
        qsoRecords = result.records
        selectedRecordIDs.subtract(Set(review.selectedGroups.flatMap(\.recordIDs)))
        refreshAwardProgress()
        updateMobileCompanionSnapshot()
        refreshDatabaseSafetyState()
        appendLog("Automatic duplicate cleanup after \(sourceName): merged \(result.mergedGroupCount) group(s), removed \(result.removedCount) extra QSO row(s).")
        return result
    }

    func prepareDuplicateReview() {
        guard !qsoRecords.isEmpty, !isAnalyzingDuplicates else { return }
        let records = qsoRecords
        let profileID = activeStationProfileID
        isAnalyzingDuplicates = true
        appendLog("Scanning the active station log for duplicate and near-duplicate QSOs...")

        Task { @MainActor [weak self] in
            let review = await Task.detached(priority: .userInitiated) {
                DuplicateQSOAnalyzer.analyze(records: records, stationProfileID: profileID)
            }.value
            guard let self else { return }
            self.isAnalyzingDuplicates = false
            guard self.activeStationProfileID == profileID else { return }

            if review.groups.isEmpty {
                self.alertTitle = "No Duplicates Found"
                self.alertMessage = "The active station log has no duplicate or near-duplicate QSOs in the five-minute match window."
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
