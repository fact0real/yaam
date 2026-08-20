//
//  AppStatePersistence.swift
//  YAAM
//

import Foundation

enum YAAMPersistenceError: LocalizedError {
    case databaseUnavailable
    case noActiveStation
    case workspaceNotLoaded
    case cannotDeleteActiveStation
    case importUnavailable

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable: return "The protected YAAM database is unavailable."
        case .noActiveStation: return "Choose an active station profile first."
        case .workspaceNotLoaded: return "The active logbook has not finished loading, so YAAM refused to overwrite its saved QSOs."
        case .cannotDeleteActiveStation: return "Activate another profile before deleting this station."
        case .importUnavailable: return "The selected file could not be read as an ADIF or SmartSDR log."
        }
    }
}

extension AppState {
    var activeStationProfile: StationProfile? {
        guard let activeStationProfileID else { return nil }
        return stationProfiles.first { $0.id == activeStationProfileID }
    }

    var activeQRZAPIKey: String {
        if let profileID = activeStationProfileID {
            let profileKey = CredentialVault.stationQRZAPIKey(profileID: profileID)
            if !profileKey.isEmpty { return profileKey }
        }
        return CredentialVault.value(for: .qrzAPIKey)
    }

    var protectedDatabaseURL: URL? {
        logbookDatabase?.databaseURL
    }

    func configurePersistentStorage() {
        do {
            let database = try LogbookDatabase()
            logbookDatabase = database

            var profiles = try database.loadStationProfiles()
            if profiles.isEmpty {
                let profile = legacyStationProfile()
                try database.saveStationProfile(profile)
                profiles = [profile]
            }

            stationProfiles = profiles
            let savedID = UserDefaults.standard.string(forKey: "activeStationProfileID").flatMap(UUID.init(uuidString:))
            let legacyCall = legacyCallsign()
            activeStationProfileID = profiles.first(where: { $0.id == savedID })?.id
                ?? profiles.first(where: { $0.normalizedCallsign == legacyCall })?.id
                ?? profiles.first?.id

            if let profile = activeStationProfile {
                UserDefaults.standard.set(profile.id.uuidString, forKey: "activeStationProfileID")
                syncLegacyStationDefaults(with: profile)
            }

            try migrateLegacyMasterLogsIfNeeded(using: database)
            stationProfiles = try database.loadStationProfiles()
            if !stationProfiles.contains(where: { $0.id == activeStationProfileID }) {
                activeStationProfileID = stationProfiles.first?.id
            }
            if activeStationProfile?.normalizedCallsign == "NOCALL",
               let activeID = activeStationProfileID,
               (try? database.qsoCount(profileID: activeID)) == 0,
               let populatedProfile = stationProfiles.first(where: {
                   ((try? database.qsoCount(profileID: $0.id)) ?? 0) > 0
               }) {
                activeStationProfileID = populatedProfile.id
                UserDefaults.standard.set(populatedProfile.id.uuidString, forKey: "activeStationProfileID")
            }
            if let profile = activeStationProfile {
                syncLegacyStationDefaults(with: profile)
            }

            createDailyBackupIfNeeded(using: database)
            refreshDatabaseSafetyState()
            databaseStatus = "Protected database ready"
        } catch {
            databaseStatus = error.localizedDescription
            appendLog("Protected database setup failed: \(error.localizedDescription)")
        }
    }

    func persistCurrentWorkspace(reason: String) throws {
        guard let database = logbookDatabase else { throw YAAMPersistenceError.databaseUnavailable }
        guard let profileID = activeStationProfileID else { throw YAAMPersistenceError.noActiveStation }
        guard loadedWorkspaceProfileID == profileID else { throw YAAMPersistenceError.workspaceNotLoaded }
        let records = qsoRecords.map { PersistedQSO(id: $0.id, index: $0.index, fields: $0.fields) }
        try workspaceSaveQueue.sync {
            try database.saveWorkspace(profileID: profileID, headers: tableHeaders, records: records)
        }
        try database.recordAudit(action: "workspace-saved", detail: "\(reason): \(records.count) QSOs", profileID: profileID)
        databaseStatus = "Saved \(records.count) QSOs"
    }

    func saveStationProfile(_ proposedProfile: StationProfile, qrzAPIKey: String? = nil) throws {
        guard let database = logbookDatabase else { throw YAAMPersistenceError.databaseUnavailable }
        var profile = proposedProfile
        profile.normalize()
        if let message = profile.validationMessage() {
            throw LogbookDatabaseError.unavailable(message)
        }

        try database.saveStationProfile(profile)
        if let qrzAPIKey {
            _ = CredentialVault.setStationQRZAPIKey(qrzAPIKey, profileID: profile.id)
        }
        stationProfiles = try database.loadStationProfiles()

        if activeStationProfileID == profile.id {
            syncLegacyStationDefaults(with: profile)
        }
        refreshDatabaseSafetyState()
    }

    func makeNewStationProfile() -> StationProfile {
        StationProfile(
            name: "New Station",
            callsign: activeStationProfile?.normalizedCallsign ?? "",
            country: activeStationProfile?.country ?? "",
            radioModel: activeStationProfile?.radioModel ?? "",
            powerWatts: activeStationProfile?.powerWatts ?? 100,
            antennaDescription: activeStationProfile?.antennaDescription ?? "",
            antennaHeightMeters: activeStationProfile?.antennaHeightMeters ?? 10
        )
    }

    func duplicateStationProfile(_ source: StationProfile) throws -> StationProfile {
        var copy = source
        copy.id = UUID()
        copy.name = "\(source.name) Copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        try saveStationProfile(copy)
        return copy
    }

    func activateStationProfile(_ profile: StationProfile) throws {
        guard stationProfiles.contains(where: { $0.id == profile.id }) else {
            throw YAAMPersistenceError.noActiveStation
        }
        if activeStationProfileID == profile.id { return }

        if logbookDatabase != nil, activeStationProfileID != nil {
            try persistCurrentWorkspace(reason: "Station switch")
        }
        activeStationProfileID = profile.id
        UserDefaults.standard.set(profile.id.uuidString, forKey: "activeStationProfileID")
        syncLegacyStationDefaults(with: profile)
        try logbookDatabase?.recordAudit(action: "station-profile-activated", detail: profile.displayTitle, profileID: profile.id)
        loadMasterLogbook()
        loadQSLHubState()
        updateMobileCompanionSnapshot()
        refreshDatabaseSafetyState()
    }

    func deleteStationProfile(_ profile: StationProfile) throws {
        guard activeStationProfileID != profile.id else {
            throw YAAMPersistenceError.cannotDeleteActiveStation
        }
        guard let database = logbookDatabase else { throw YAAMPersistenceError.databaseUnavailable }
        try database.deleteStationProfile(id: profile.id)
        _ = CredentialVault.deleteStationCredentials(profileID: profile.id)
        stationProfiles = try database.loadStationProfiles()
        refreshDatabaseSafetyState()
    }

    func setActiveStationQRZAPIKey(_ value: String) {
        guard let profileID = activeStationProfileID else {
            _ = CredentialVault.set(value, for: .qrzAPIKey)
            return
        }
        _ = CredentialVault.setStationQRZAPIKey(value, profileID: profileID)
    }

    func prepareImportReview(from url: URL) {
        if !isMasterMode {
            loadMasterLogbook()
        }
        let destinationProfileID = activeStationProfileID
        let existingRecords = qsoRecords
        isLoading = true
        appendLog("Reading \(url.lastPathComponent) for import review...")

        Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let parsed = try LogFileReader.loadWithSecurityScopedAccess(from: url)
                    let review = ImportReviewAnalyzer.analyze(
                        sourceName: url.lastPathComponent,
                        sourceURL: url,
                        sourceFormat: parsed.format,
                        destinationProfileID: destinationProfileID,
                        headers: parsed.headers,
                        incoming: parsed.records,
                        existing: existingRecords
                    )
                    return (parsed, review)
                }.value

                guard activeStationProfileID == destinationProfileID else {
                    throw LogbookDatabaseError.unavailable(
                        "The active station changed while the source log was being read. Choose the file again for the current station."
                    )
                }

                pendingImportReview = result.1
                showImportReviewSheet = true
                isLoading = false
                var details = "Import review prepared for \(result.0.records.count) \(result.0.format.title) record(s)"
                if result.0.ignoredDeletedRecordCount > 0 {
                    details += "; \(result.0.ignoredDeletedRecordCount) deleted record(s) ignored"
                }
                if result.0.validationIssueCount > 0 {
                    details += "; \(result.0.validationIssueCount) record(s) need validation"
                }
                appendLog(details + ".")
            } catch {
                isLoading = false
                presentPersistenceError(error)
            }
        }
    }

    func setImportReviewSelection(itemID: UUID, selected: Bool) {
        guard var review = pendingImportReview,
              let index = review.items.firstIndex(where: { $0.id == itemID }) else { return }
        review.items[index].isSelected = selected
        pendingImportReview = review
    }

    func selectImportReviewItems(kind: ImportReviewKind, selected: Bool) {
        guard var review = pendingImportReview else { return }
        for index in review.items.indices where review.items[index].kind == kind {
            if kind != .duplicate && kind != .invalid {
                review.items[index].isSelected = selected
            }
        }
        pendingImportReview = review
    }

    func cancelPendingImport() {
        pendingImportReview = nil
        showImportReviewSheet = false
    }

    func commitPendingImport() {
        guard let review = pendingImportReview else { return }
        guard review.destinationProfileID == activeStationProfileID else {
            presentPersistenceError(LogbookDatabaseError.unavailable("The active station changed after this review was prepared. Reopen the source log for the current station."))
            return
        }
        let selected = review.items.filter(\.isSelected)
        guard !selected.isEmpty else {
            presentPersistenceError(LogbookDatabaseError.unavailable("Select at least one new or updated QSO."))
            return
        }

        do {
            if let database = logbookDatabase {
                _ = try database.createBackup(reason: "Before importing \(review.sourceName)")
            }

            var added = 0
            var updated = 0
            for item in selected {
                switch item.kind {
                case .newQSO, .potentialConflict:
                    let fields = stationTaggedFields(item.incomingFields)
                    qsoRecords.append(QSORecordModel(index: qsoRecords.count + 1, fields: fields))
                    added += 1
                case .confirmationUpdate:
                    guard let targetID = item.matchingRecordID,
                          let index = qsoRecords.firstIndex(where: { $0.id == targetID }) else { continue }
                    qsoRecords[index].fields = ImportReviewAnalyzer.mergeUpdate(
                        incoming: item.incomingFields,
                        into: qsoRecords[index].fields
                    )
                    updated += 1
                case .duplicate, .invalid:
                    continue
                }
            }

            for index in qsoRecords.indices { qsoRecords[index].index = index + 1 }
            let importedHeaders = review.headers + selected.flatMap { Array($0.incomingFields.keys) }
            for header in importedHeaders where !tableHeaders.contains(header) {
                tableHeaders.append(header)
            }

            try persistCurrentWorkspace(reason: "Imported \(review.sourceName)")
            refreshAwardProgress()
            updateMobileCompanionSnapshot()
            try logbookDatabase?.recordAudit(
                action: "log-imported",
                detail: "\(review.sourceName): \(added) added, \(updated) updated",
                profileID: activeStationProfileID
            )
            pendingImportReview = nil
            showImportReviewSheet = false
            refreshDatabaseSafetyState()
            alertTitle = "Import Complete"
            alertMessage = "Added \(added) new QSO(s) and updated \(updated) existing confirmation(s). A restore point was created first."
            showAlert = true
            playActivitySound(.success)
        } catch {
            presentPersistenceError(error)
        }
    }

    func refreshDatabaseSafetyState() {
        guard let database = logbookDatabase else { return }
        backupSnapshots = database.listBackups()
        recentDatabaseAuditEvents = (try? database.recentAuditEvents(limit: 40)) ?? []
    }

    func createManualDatabaseBackup() {
        guard let database = logbookDatabase else {
            presentPersistenceError(YAAMPersistenceError.databaseUnavailable)
            return
        }
        do {
            try persistCurrentWorkspace(reason: "Before manual backup")
            _ = try database.createBackup(reason: "Manual restore point")
            refreshDatabaseSafetyState()
            databaseStatus = "Restore point created"
            playActivitySound(.success)
        } catch {
            presentPersistenceError(error)
        }
    }

    func restoreDatabaseBackup(_ snapshot: BackupSnapshot) {
        guard let database = logbookDatabase else {
            presentPersistenceError(YAAMPersistenceError.databaseUnavailable)
            return
        }
        do {
            try persistCurrentWorkspace(reason: "Before restore")
            _ = try database.createBackup(reason: "Automatic rollback before restore")
            try database.restoreBackup(snapshot)
            stationProfiles = try database.loadStationProfiles()
            if !stationProfiles.contains(where: { $0.id == activeStationProfileID }) {
                activeStationProfileID = stationProfiles.first?.id
            }
            if let profile = activeStationProfile {
                UserDefaults.standard.set(profile.id.uuidString, forKey: "activeStationProfileID")
                syncLegacyStationDefaults(with: profile)
            }
            loadMasterLogbook()
            loadQSLHubState()
            updateMobileCompanionSnapshot()
            refreshDatabaseSafetyState()
            databaseStatus = "Restored \(snapshot.reason)"
            alertTitle = "Restore Complete"
            alertMessage = "The protected logbook was restored to \(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))."
            showAlert = true
            playActivitySound(.success)
        } catch {
            presentPersistenceError(error)
        }
    }

    func checkDatabaseIntegrity() {
        guard let database = logbookDatabase else {
            presentPersistenceError(YAAMPersistenceError.databaseUnavailable)
            return
        }
        do {
            let result = try database.integrityCheck()
            databaseStatus = result.lowercased() == "ok" ? "Integrity check passed" : result
            playActivitySound(result.lowercased() == "ok" ? .success : .failure)
        } catch {
            presentPersistenceError(error)
        }
    }

    func createDestructiveCheckpointIfNeeded(reason: String) -> Bool {
        guard isMasterMode else { return true }
        guard let database = logbookDatabase else {
            presentPersistenceError(YAAMPersistenceError.databaseUnavailable)
            return false
        }
        if let lastDestructiveCheckpointDate,
           Date().timeIntervalSince(lastDestructiveCheckpointDate) < 60 {
            return true
        }
        do {
            try persistCurrentWorkspace(reason: reason)
            _ = try database.createBackup(reason: reason)
            lastDestructiveCheckpointDate = Date()
            refreshDatabaseSafetyState()
            return true
        } catch {
            presentPersistenceError(error)
            return false
        }
    }

    private func legacyStationProfile() -> StationProfile {
        let defaults = UserDefaults.standard
        return StationProfile(
            name: "Primary Station",
            callsign: legacyCallsign(),
            grid: defaults.string(forKey: "stationGrid") ?? "",
            radioModel: defaults.string(forKey: "radioModel") ?? "",
            powerWatts: max(defaults.integer(forKey: "radioPowerWatts"), 1),
            antennaDescription: defaults.string(forKey: "antennaDescription") ?? "",
            antennaHeightMeters: max(defaults.integer(forKey: "antennaHeightMeters"), 0)
        )
    }

    private func legacyCallsign() -> String {
        let defaults = UserDefaults.standard
        let candidates = [
            defaults.string(forKey: "operatorCallsign"),
            defaults.string(forKey: "stationCallsign"),
            defaults.string(forKey: "qrzUsername")
        ]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .first(where: { !$0.isEmpty }) ?? "NOCALL"
    }

    private func syncLegacyStationDefaults(with profile: StationProfile) {
        let defaults = UserDefaults.standard
        defaults.set(profile.normalizedCallsign, forKey: "operatorCallsign")
        defaults.set(profile.normalizedCallsign, forKey: "stationCallsign")
        defaults.set(profile.normalizedGrid, forKey: "stationGrid")
        defaults.set(profile.radioModel, forKey: "radioModel")
        defaults.set(profile.powerWatts, forKey: "radioPowerWatts")
        defaults.set(profile.antennaDescription, forKey: "antennaDescription")
        defaults.set(profile.antennaHeightMeters, forKey: "antennaHeightMeters")
    }

    private func migrateLegacyMasterLogsIfNeeded(using database: LogbookDatabase) throws {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let directory = appSupport.appendingPathComponent("YAAM/MasterLogs", isDirectory: true)
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let legacyLogs = files.filter {
            $0.lastPathComponent.hasPrefix("MasterLogbook_") && ["adi", "adif"].contains($0.pathExtension.lowercased())
        }
        guard !legacyLogs.isEmpty else { return }

        var createdPreMigrationBackup = false
        for url in legacyLogs {
            let migrationKey = "migration.legacy-adif.\(url.lastPathComponent.lowercased())"

            let stem = url.deletingPathExtension().lastPathComponent
            let rawCallsign = String(stem.dropFirst("MasterLogbook_".count)).uppercased()
            let profile: StationProfile
            if let existing = stationProfiles.first(where: { $0.normalizedCallsign == rawCallsign }) {
                profile = existing
            } else {
                let imported = StationProfile(name: "Imported Station", callsign: rawCallsign.isEmpty ? "NOCALL" : rawCallsign)
                try database.saveStationProfile(imported)
                stationProfiles.append(imported)
                profile = imported
            }

            let existingCount = try database.qsoCount(profileID: profile.id)
            if existingCount > 0 {
                try database.setMetadata("1", for: migrationKey)
                continue
            }
            guard let content = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { continue }
            let parsed = parseADIF(content: content)
            guard !parsed.records.isEmpty else {
                try database.setMetadata("1", for: migrationKey)
                continue
            }

            if !createdPreMigrationBackup {
                _ = try database.createBackup(reason: "Before legacy ADIF migration")
                createdPreMigrationBackup = true
            }
            let records = parsed.records.enumerated().map { offset, fields in
                PersistedQSO(id: UUID(), index: offset + 1, fields: stationTaggedFields(fields, profile: profile))
            }
            try database.saveWorkspace(profileID: profile.id, headers: parsed.headers, records: records)
            try database.setMetadata("1", for: migrationKey)
            try database.recordAudit(
                action: "legacy-adif-migrated",
                detail: "\(url.lastPathComponent): \(records.count) QSOs",
                profileID: profile.id
            )
        }

        if createdPreMigrationBackup {
            _ = try database.createBackup(reason: "After legacy ADIF migration")
        }
    }

    private func createDailyBackupIfNeeded(using database: LogbookDatabase) {
        guard (try? database.qsoCount()) ?? 0 > 0 else { return }
        let latest = database.listBackups().first?.createdAt ?? .distantPast
        guard Date().timeIntervalSince(latest) >= 86_400 else { return }
        _ = try? database.createBackup(reason: "Automatic daily restore point")
    }

    func stationTaggedFields(_ fields: [String: String], profile explicitProfile: StationProfile? = nil) -> [String: String] {
        guard let profile = explicitProfile ?? activeStationProfile else { return fields }
        var tagged = fields
        tagged["APP_YAAM_STATION_PROFILE_ID"] = profile.id.uuidString
        if (tagged["STATION_CALLSIGN"] ?? "").isEmpty { tagged["STATION_CALLSIGN"] = profile.normalizedCallsign }
        if (tagged["MY_GRIDSQUARE"] ?? "").isEmpty, !profile.normalizedGrid.isEmpty { tagged["MY_GRIDSQUARE"] = profile.normalizedGrid }
        if (tagged["MY_LAT"] ?? "").isEmpty, !profile.latitude.isEmpty { tagged["MY_LAT"] = profile.latitude }
        if (tagged["MY_LON"] ?? "").isEmpty, !profile.longitude.isEmpty { tagged["MY_LON"] = profile.longitude }
        if (tagged["MY_DXCC"] ?? "").isEmpty, !profile.dxccCode.isEmpty { tagged["MY_DXCC"] = profile.dxccCode }
        if (tagged["MY_CQ_ZONE"] ?? "").isEmpty, !profile.cqZone.isEmpty { tagged["MY_CQ_ZONE"] = profile.cqZone }
        if (tagged["MY_ITU_ZONE"] ?? "").isEmpty, !profile.ituZone.isEmpty { tagged["MY_ITU_ZONE"] = profile.ituZone }
        return tagged
    }

    private func presentPersistenceError(_ error: Error) {
        databaseStatus = error.localizedDescription
        alertTitle = "Logbook Safety"
        alertMessage = error.localizedDescription
        showAlert = true
        appendLog("Logbook safety operation failed: \(error.localizedDescription)")
        playActivitySound(.failure)
    }
}
