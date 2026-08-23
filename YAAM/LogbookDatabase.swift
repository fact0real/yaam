//
//  LogbookDatabase.swift
//  YAAM
//

import Foundation
import SQLite3

nonisolated enum LogbookDatabaseError: LocalizedError {
    case unavailable(String)
    case sqlite(message: String)
    case invalidBackup
    case profileHasQSOs(Int)
    case corruptQSO(Int)
    case refusingEmptyOverwrite(Int)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .sqlite(let message): return "SQLite error: \(message)"
        case .invalidBackup: return "The selected backup is missing, outside YAAM's backup folder, or failed its integrity check."
        case .profileHasQSOs(let count): return "This station profile owns \(count) QSO(s). Move or export them before deleting the profile."
        case .corruptQSO(let order): return "QSO record #\(order) could not be decoded. The database was left unchanged."
        case .refusingEmptyOverwrite(let count): return "YAAM refused to replace \(count) saved QSO(s) with an empty workspace."
        }
    }
}

nonisolated struct QSORecoveryReport: Sendable {
    let recoveredCount: Int
    let skippedExistingCount: Int
    let skippedNonLegacyCount: Int
    let skippedUnknownProfileCount: Int
}

nonisolated final class LogbookDatabase: @unchecked Sendable {
    private struct BackupManifest: Codable {
        let createdAt: Date
        let reason: String
    }

    private struct RecoveryCandidate {
        let id: UUID
        let profileID: UUID
        let fields: [String: String]
        let uniqueKey: String
        let createdAt: TimeInterval
        let updatedAt: TimeInterval
    }

    private let queue = DispatchQueue(label: "app.yaam.logbook-database", qos: .userInitiated)
    private var db: OpaquePointer?

    let databaseURL: URL
    let backupDirectoryURL: URL

    init(baseDirectory: URL? = nil) throws {
        let fm = FileManager.default
        let root: URL
        if let baseDirectory {
            root = baseDirectory
        } else {
            guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw LogbookDatabaseError.unavailable("Application Support is unavailable.")
            }
            root = appSupport.appendingPathComponent("YAAM/Data", isDirectory: true)
        }

        databaseURL = root.appendingPathComponent("YAAM.sqlite")
        backupDirectoryURL = root.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)

        try openDatabase()
        try initializeSchema()
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    func loadStationProfiles() throws -> [StationProfile] {
        try queue.sync {
            let sql = """
            SELECT id, name, callsign, qth, grid, latitude, longitude, dxcc_code, country,
                   cq_zone, itu_zone, radio_model, power_watts, antenna_description,
                   antenna_height_meters, valid_from, valid_to, lotw_station_location,
                   eqsl_qth_nickname, created_at, updated_at
            FROM station_profiles
            ORDER BY name COLLATE NOCASE, callsign COLLATE NOCASE;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            var profiles: [StationProfile] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = UUID(uuidString: text(statement, 0)) else { continue }
                profiles.append(StationProfile(
                    id: id,
                    name: text(statement, 1),
                    callsign: text(statement, 2),
                    qth: text(statement, 3),
                    grid: text(statement, 4),
                    latitude: text(statement, 5),
                    longitude: text(statement, 6),
                    dxccCode: text(statement, 7),
                    country: text(statement, 8),
                    cqZone: text(statement, 9),
                    ituZone: text(statement, 10),
                    radioModel: text(statement, 11),
                    powerWatts: Int(sqlite3_column_int(statement, 12)),
                    antennaDescription: text(statement, 13),
                    antennaHeightMeters: Int(sqlite3_column_int(statement, 14)),
                    validFrom: optionalDate(statement, 15),
                    validTo: optionalDate(statement, 16),
                    lotwStationLocation: text(statement, 17),
                    eqslQTHNickname: text(statement, 18),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 19)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 20))
                ))
            }
            return profiles
        }
    }

    func saveStationProfile(_ profile: StationProfile) throws {
        try queue.sync {
            let sql = """
            INSERT INTO station_profiles (
                id, name, callsign, qth, grid, latitude, longitude, dxcc_code, country,
                cq_zone, itu_zone, radio_model, power_watts, antenna_description,
                antenna_height_meters, valid_from, valid_to, lotw_station_location,
                eqsl_qth_nickname, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                callsign = excluded.callsign,
                qth = excluded.qth,
                grid = excluded.grid,
                latitude = excluded.latitude,
                longitude = excluded.longitude,
                dxcc_code = excluded.dxcc_code,
                country = excluded.country,
                cq_zone = excluded.cq_zone,
                itu_zone = excluded.itu_zone,
                radio_model = excluded.radio_model,
                power_watts = excluded.power_watts,
                antenna_description = excluded.antenna_description,
                antenna_height_meters = excluded.antenna_height_meters,
                valid_from = excluded.valid_from,
                valid_to = excluded.valid_to,
                lotw_station_location = excluded.lotw_station_location,
                eqsl_qth_nickname = excluded.eqsl_qth_nickname,
                updated_at = excluded.updated_at;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            bind(profile.id.uuidString, to: 1, in: statement)
            bind(profile.name, to: 2, in: statement)
            bind(profile.normalizedCallsign, to: 3, in: statement)
            bind(profile.qth, to: 4, in: statement)
            bind(profile.normalizedGrid, to: 5, in: statement)
            bind(profile.latitude, to: 6, in: statement)
            bind(profile.longitude, to: 7, in: statement)
            bind(profile.dxccCode, to: 8, in: statement)
            bind(profile.country, to: 9, in: statement)
            bind(profile.cqZone, to: 10, in: statement)
            bind(profile.ituZone, to: 11, in: statement)
            bind(profile.radioModel, to: 12, in: statement)
            sqlite3_bind_int(statement, 13, Int32(profile.powerWatts))
            bind(profile.antennaDescription, to: 14, in: statement)
            sqlite3_bind_int(statement, 15, Int32(profile.antennaHeightMeters))
            bind(profile.validFrom, to: 16, in: statement)
            bind(profile.validTo, to: 17, in: statement)
            bind(profile.lotwStationLocation, to: 18, in: statement)
            bind(profile.eqslQTHNickname, to: 19, in: statement)
            sqlite3_bind_double(statement, 20, profile.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 21, profile.updatedAt.timeIntervalSince1970)

            try stepDone(statement)
            try insertAudit(action: "station-profile-saved", detail: profile.displayTitle, profileID: profile.id)
        }
    }

    func deleteStationProfile(id: UUID) throws {
        try queue.sync {
            let count = try qsoCountInternal(profileID: id)
            guard count == 0 else { throw LogbookDatabaseError.profileHasQSOs(count) }

            let statement = try prepare("DELETE FROM station_profiles WHERE id = ?;")
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, to: 1, in: statement)
            try stepDone(statement)
            try insertAudit(action: "station-profile-deleted", detail: id.uuidString, profileID: nil)
        }
    }

    func qsoCount(profileID: UUID? = nil) throws -> Int {
        try queue.sync { try qsoCountInternal(profileID: profileID) }
    }

    func metadata(for key: String) throws -> String? {
        try queue.sync { try metadataValue(for: key) }
    }

    func setMetadata(_ value: String, for key: String) throws {
        try queue.sync { try setMetadataValue(value, for: key) }
    }

    func loadWorkspace(profileID: UUID) throws -> (headers: [String], records: [PersistedQSO]) {
        try queue.sync {
            let headerKey = "headers.\(profileID.uuidString.lowercased())"
            let headers = try metadataValue(for: headerKey).flatMap { value -> [String]? in
                guard let data = value.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode([String].self, from: data)
            } ?? []

            let statement = try prepare("""
                SELECT id, sort_order, fields_json
                FROM qsos
                WHERE station_profile_id = ?
                ORDER BY sort_order ASC, qso_date ASC, time_on ASC;
                """)
            defer { sqlite3_finalize(statement) }
            bind(profileID.uuidString, to: 1, in: statement)

            var records: [PersistedQSO] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let order = Int(sqlite3_column_int(statement, 1))
                guard let id = UUID(uuidString: text(statement, 0)),
                      let jsonText = sqlite3_column_text(statement, 2) else {
                    throw LogbookDatabaseError.corruptQSO(order)
                }
                let data = Data(bytes: jsonText, count: Int(sqlite3_column_bytes(statement, 2)))
                guard let fields = try? JSONDecoder().decode([String: String].self, from: data) else {
                    throw LogbookDatabaseError.corruptQSO(order)
                }
                records.append(PersistedQSO(id: id, index: order, fields: fields))
            }
            return (headers, records)
        }
    }

    func saveWorkspace(
        profileID: UUID,
        headers: [String],
        records: [PersistedQSO],
        allowEmptyReplacement: Bool = false,
        replaceMissingRecords: Bool = true
    ) throws {
        try queue.sync {
            let savedCount = try qsoCountInternal(profileID: profileID)
            if replaceMissingRecords, records.isEmpty, savedCount > 0, !allowEmptyReplacement {
                throw LogbookDatabaseError.refusingEmptyOverwrite(savedCount)
            }
            try execute("BEGIN IMMEDIATE TRANSACTION;")
            do {
                if replaceMissingRecords {
                    let deleteStatement = try prepare("DELETE FROM qsos WHERE station_profile_id = ?;")
                    bind(profileID.uuidString, to: 1, in: deleteStatement)
                    try stepDone(deleteStatement)
                    sqlite3_finalize(deleteStatement)
                }

                let insertSQL = """
                INSERT INTO qsos (
                    id, station_profile_id, unique_key, call, qso_date, time_on, band, mode,
                    fields_json, sort_order, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    station_profile_id = excluded.station_profile_id,
                    unique_key = excluded.unique_key,
                    call = excluded.call,
                    qso_date = excluded.qso_date,
                    time_on = excluded.time_on,
                    band = excluded.band,
                    mode = excluded.mode,
                    fields_json = excluded.fields_json,
                    sort_order = excluded.sort_order,
                    updated_at = excluded.updated_at;
                """
                let insertStatement = try prepare(insertSQL)
                defer { sqlite3_finalize(insertStatement) }
                let now = Date().timeIntervalSince1970

                for record in records {
                    sqlite3_reset(insertStatement)
                    sqlite3_clear_bindings(insertStatement)
                    let fields = CountryNameNormalizer.normalizedFields(record.fields).fields
                    let uniqueKey = Self.uniqueKey(fields: fields)
                    let jsonData = try JSONEncoder().encode(fields)
                    guard let json = String(data: jsonData, encoding: .utf8) else { continue }

                    bind(record.id.uuidString, to: 1, in: insertStatement)
                    bind(profileID.uuidString, to: 2, in: insertStatement)
                    bind(uniqueKey, to: 3, in: insertStatement)
                    bind(fields["CALL"] ?? "", to: 4, in: insertStatement)
                    bind(fields["QSO_DATE"] ?? "", to: 5, in: insertStatement)
                    bind(fields["TIME_ON"] ?? fields["TIME_OFF"] ?? "", to: 6, in: insertStatement)
                    bind(fields["BAND"] ?? "", to: 7, in: insertStatement)
                    bind(fields["MODE"] ?? "", to: 8, in: insertStatement)
                    bind(json, to: 9, in: insertStatement)
                    sqlite3_bind_int(insertStatement, 10, Int32(record.index))
                    sqlite3_bind_double(insertStatement, 11, now)
                    sqlite3_bind_double(insertStatement, 12, now)
                    try stepDone(insertStatement)
                }

                try updateFieldCatalog(
                    profileID: profileID,
                    headers: headers,
                    records: records,
                    timestamp: now
                )

                let headerData = try JSONEncoder().encode(headers)
                let headerValue = String(data: headerData, encoding: .utf8) ?? "[]"
                try setMetadataValue(headerValue, for: "headers.\(profileID.uuidString.lowercased())")
                try execute("COMMIT;")
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
        }
    }

    func appendQSO(profileID: UUID, headers: [String], record: PersistedQSO) throws {
        try queue.sync {
            try execute("BEGIN IMMEDIATE TRANSACTION;")
            do {
                let fields = CountryNameNormalizer.normalizedFields(record.fields).fields
                let jsonData = try JSONEncoder().encode(fields)
                guard let json = String(data: jsonData, encoding: .utf8) else {
                    throw LogbookDatabaseError.unavailable("Unable to encode the new QSO.")
                }

                let statement = try prepare("""
                    INSERT INTO qsos (
                        id, station_profile_id, unique_key, call, qso_date, time_on, band, mode,
                        fields_json, sort_order, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """)
                defer { sqlite3_finalize(statement) }
                let now = Date().timeIntervalSince1970
                bind(record.id.uuidString, to: 1, in: statement)
                bind(profileID.uuidString, to: 2, in: statement)
                bind(Self.uniqueKey(fields: fields), to: 3, in: statement)
                bind(fields["CALL"] ?? "", to: 4, in: statement)
                bind(fields["QSO_DATE"] ?? "", to: 5, in: statement)
                bind(fields["TIME_ON"] ?? fields["TIME_OFF"] ?? "", to: 6, in: statement)
                bind(fields["BAND"] ?? "", to: 7, in: statement)
                bind(fields["MODE"] ?? "", to: 8, in: statement)
                bind(json, to: 9, in: statement)
                sqlite3_bind_int(statement, 10, Int32(record.index))
                sqlite3_bind_double(statement, 11, now)
                sqlite3_bind_double(statement, 12, now)
                try stepDone(statement)

                try updateFieldCatalog(
                    profileID: profileID,
                    headers: headers,
                    records: [record],
                    timestamp: now
                )

                let headerData = try JSONEncoder().encode(headers)
                let headerValue = String(data: headerData, encoding: .utf8) ?? "[]"
                try setMetadataValue(headerValue, for: "headers.\(profileID.uuidString.lowercased())")
                try insertAudit(
                    action: "quick-log",
                    detail: "Logged \(fields["CALL"] ?? "") on \(fields["BAND"] ?? "") \(fields["MODE"] ?? "")",
                    profileID: profileID
                )
                try execute("COMMIT;")
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
        }
    }

    func createBackup(reason: String, retainCount: Int = 30) throws -> BackupSnapshot {
        try queue.sync {
            let cleanReason = Self.fileSafeReason(reason)
            let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
            let url = backupDirectoryURL.appendingPathComponent("YAAM_\(timestamp)_\(cleanReason).sqlite")
            try backupDatabase(to: url)

            let manifest = BackupManifest(createdAt: Date(), reason: reason)
            let manifestURL = url.appendingPathExtension("json")
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: manifestURL, options: .atomic)
            try insertAudit(action: "backup-created", detail: reason, profileID: nil)
            try pruneBackups(retainCount: retainCount)
            return try backupSnapshot(for: url)
        }
    }

    func listBackups() -> [BackupSnapshot] {
        queue.sync {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: backupDirectoryURL,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            return files
                .filter { $0.pathExtension.lowercased() == "sqlite" }
                .compactMap { try? backupSnapshot(for: $0) }
                .sorted { $0.createdAt > $1.createdAt }
        }
    }

    func restoreBackup(_ snapshot: BackupSnapshot) throws {
        try queue.sync {
            let source = snapshot.url.standardizedFileURL
            let backupRoot = backupDirectoryURL.standardizedFileURL.path + "/"
            guard source.path.hasPrefix(backupRoot), FileManager.default.fileExists(atPath: source.path) else {
                throw LogbookDatabaseError.invalidBackup
            }
            try validateDatabase(at: source)

            let fm = FileManager.default
            let rollbackURL = databaseURL.appendingPathExtension("restore-rollback.sqlite")
            try? fm.removeItem(at: rollbackURL)
            try backupDatabase(to: rollbackURL)

            do {
                try restoreOpenDatabase(from: source)
                try initializeSchema()
                try validateOpenDatabase()
                try insertAudit(action: "backup-restored", detail: snapshot.reason, profileID: nil)
                try? fm.removeItem(at: rollbackURL)
            } catch {
                if fm.fileExists(atPath: rollbackURL.path) {
                    try? restoreOpenDatabase(from: rollbackURL)
                }
                try? initializeSchema()
                throw error
            }
        }
    }

    /// Restores only rows that match the signature of YAAM's retired five-minute
    /// duplicate cleanup. Exact duplicates and unrelated user deletions stay removed.
    func recoverQSOsRemovedByLegacyNearDuplicateCleanup(
        from snapshot: BackupSnapshot
    ) throws -> QSORecoveryReport {
        try queue.sync {
            let source = snapshot.url.standardizedFileURL
            let backupRoot = backupDirectoryURL.standardizedFileURL.path + "/"
            guard source.path.hasPrefix(backupRoot), FileManager.default.fileExists(atPath: source.path) else {
                throw LogbookDatabaseError.invalidBackup
            }
            try validateDatabase(at: source)

            var sourceDB: OpaquePointer?
            let openStatus = sqlite3_open_v2(
                source.path,
                &sourceDB,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
                nil
            )
            guard openStatus == SQLITE_OK, let sourceDB else {
                let message = sourceDB.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open recovery source."
                if let sourceDB { sqlite3_close_v2(sourceDB) }
                throw LogbookDatabaseError.sqlite(message: message)
            }
            defer { sqlite3_close_v2(sourceDB) }
            sqlite3_busy_timeout(sourceDB, 5_000)

            var knownProfiles = Set<String>()
            let profileStatement = try prepare("SELECT id FROM station_profiles; ")
            defer { sqlite3_finalize(profileStatement) }
            while sqlite3_step(profileStatement) == SQLITE_ROW {
                knownProfiles.insert(text(profileStatement, 0).lowercased())
            }

            var existingIDs = Set<String>()
            var existingExactKeys = Set<String>()
            var currentTimesByRelaxedKey: [String: [Int]] = [:]
            var nextSortOrderByProfile: [String: Int] = [:]
            let currentStatement = try prepare("""
                SELECT id, station_profile_id, fields_json, sort_order
                FROM qsos;
                """)
            defer { sqlite3_finalize(currentStatement) }
            while sqlite3_step(currentStatement) == SQLITE_ROW {
                let id = text(currentStatement, 0).lowercased()
                let profileID = text(currentStatement, 1).lowercased()
                let sortOrder = Int(sqlite3_column_int64(currentStatement, 3))
                existingIDs.insert(id)
                nextSortOrderByProfile[profileID] = max(nextSortOrderByProfile[profileID] ?? 0, sortOrder)

                guard let fields = decodedFields(currentStatement, column: 2) else { continue }
                let exactKey = QSOIdentity.exactKey(fields: fields)
                if !exactKey.isEmpty {
                    existingExactKeys.insert(scopedIdentity(profileID: profileID, key: exactKey))
                }
                let relaxedKey = QSOIdentity.relaxedKey(fields: fields)
                if !relaxedKey.isEmpty, let seconds = QSOIdentity.secondsFromMidnight(fields) {
                    currentTimesByRelaxedKey[scopedIdentity(profileID: profileID, key: relaxedKey), default: []]
                        .append(seconds)
                }
            }

            var candidates: [RecoveryCandidate] = []
            var skippedExisting = 0
            var skippedNonLegacy = 0
            var skippedUnknownProfile = 0
            let sourceStatement = try prepare(
                """
                SELECT id, station_profile_id, fields_json, created_at, updated_at
                FROM qsos
                ORDER BY station_profile_id, sort_order;
                """,
                in: sourceDB
            )
            defer { sqlite3_finalize(sourceStatement) }

            while sqlite3_step(sourceStatement) == SQLITE_ROW {
                let idText = text(sourceStatement, 0).lowercased()
                let profileIDString = text(sourceStatement, 1).lowercased()
                guard let id = UUID(uuidString: idText),
                      knownProfiles.contains(profileIDString),
                      let profileID = UUID(uuidString: profileIDString) else {
                    skippedUnknownProfile += 1
                    continue
                }
                guard !existingIDs.contains(idText) else {
                    skippedExisting += 1
                    continue
                }
                guard let rawFields = decodedFields(sourceStatement, column: 2) else {
                    skippedNonLegacy += 1
                    continue
                }
                let fields = CountryNameNormalizer.normalizedFields(rawFields).fields
                let exactKey = QSOIdentity.exactKey(fields: fields)
                let relaxedKey = QSOIdentity.relaxedKey(fields: fields)
                guard !exactKey.isEmpty,
                      !relaxedKey.isEmpty,
                      let seconds = QSOIdentity.secondsFromMidnight(fields) else {
                    skippedNonLegacy += 1
                    continue
                }

                let scopedExactKey = scopedIdentity(profileID: profileIDString, key: exactKey)
                guard !existingExactKeys.contains(scopedExactKey) else {
                    skippedExisting += 1
                    continue
                }
                let scopedRelaxedKey = scopedIdentity(profileID: profileIDString, key: relaxedKey)
                guard currentTimesByRelaxedKey[scopedRelaxedKey]?.contains(where: {
                    abs($0 - seconds) <= 300
                }) == true else {
                    skippedNonLegacy += 1
                    continue
                }

                candidates.append(RecoveryCandidate(
                    id: id,
                    profileID: profileID,
                    fields: fields,
                    uniqueKey: exactKey,
                    createdAt: sqlite3_column_double(sourceStatement, 3),
                    updatedAt: sqlite3_column_double(sourceStatement, 4)
                ))
                existingIDs.insert(idText)
                existingExactKeys.insert(scopedExactKey)
            }

            guard !candidates.isEmpty else {
                return QSORecoveryReport(
                    recoveredCount: 0,
                    skippedExistingCount: skippedExisting,
                    skippedNonLegacyCount: skippedNonLegacy,
                    skippedUnknownProfileCount: skippedUnknownProfile
                )
            }

            try execute("BEGIN IMMEDIATE TRANSACTION;")
            do {
                let insertStatement = try prepare("""
                    INSERT INTO qsos (
                        id, station_profile_id, unique_key, call, qso_date, time_on, band, mode,
                        fields_json, sort_order, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """)
                defer { sqlite3_finalize(insertStatement) }
                var recoveredByProfile: [UUID: [PersistedQSO]] = [:]

                for candidate in candidates {
                    let profileKey = candidate.profileID.uuidString.lowercased()
                    let nextSortOrder = (nextSortOrderByProfile[profileKey] ?? 0) + 1
                    nextSortOrderByProfile[profileKey] = nextSortOrder
                    let jsonData = try JSONEncoder().encode(candidate.fields)
                    guard let json = String(data: jsonData, encoding: .utf8) else { continue }

                    sqlite3_reset(insertStatement)
                    sqlite3_clear_bindings(insertStatement)
                    bind(candidate.id.uuidString, to: 1, in: insertStatement)
                    bind(candidate.profileID.uuidString, to: 2, in: insertStatement)
                    bind(candidate.uniqueKey, to: 3, in: insertStatement)
                    bind(candidate.fields["CALL"] ?? "", to: 4, in: insertStatement)
                    bind(candidate.fields["QSO_DATE"] ?? "", to: 5, in: insertStatement)
                    bind(candidate.fields["TIME_ON"] ?? candidate.fields["TIME_OFF"] ?? "", to: 6, in: insertStatement)
                    bind(QSOIdentity.resolvedBand(candidate.fields), to: 7, in: insertStatement)
                    bind(QSOIdentity.effectiveMode(candidate.fields), to: 8, in: insertStatement)
                    bind(json, to: 9, in: insertStatement)
                    sqlite3_bind_int64(insertStatement, 10, sqlite3_int64(nextSortOrder))
                    sqlite3_bind_double(insertStatement, 11, candidate.createdAt)
                    sqlite3_bind_double(insertStatement, 12, candidate.updatedAt)
                    try stepDone(insertStatement)

                    recoveredByProfile[candidate.profileID, default: []].append(PersistedQSO(
                        id: candidate.id,
                        index: nextSortOrder,
                        fields: candidate.fields
                    ))
                }

                let now = Date().timeIntervalSince1970
                for (profileID, records) in recoveredByProfile {
                    try updateFieldCatalog(profileID: profileID, headers: [], records: records, timestamp: now)
                }
                try insertAudit(
                    action: "legacy-near-duplicate-cleanup-recovered",
                    detail: "Recovered \(candidates.count) QSO(s) with distinct UTC times from \(snapshot.id).",
                    profileID: nil
                )
                try execute("COMMIT;")
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }

            return QSORecoveryReport(
                recoveredCount: candidates.count,
                skippedExistingCount: skippedExisting,
                skippedNonLegacyCount: skippedNonLegacy,
                skippedUnknownProfileCount: skippedUnknownProfile
            )
        }
    }

    func integrityCheck() throws -> String {
        try queue.sync {
            let statement = try prepare("PRAGMA quick_check;")
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw currentError()
            }
            return text(statement, 0)
        }
    }

    func recordAudit(action: String, detail: String, profileID: UUID? = nil) throws {
        try queue.sync { try insertAudit(action: action, detail: detail, profileID: profileID) }
    }

    func recentAuditEvents(limit: Int = 30) throws -> [DatabaseAuditEvent] {
        try queue.sync {
            let statement = try prepare("""
                SELECT id, created_at, action, detail, station_profile_id
                FROM audit_log
                ORDER BY id DESC
                LIMIT ?;
                """)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(max(1, limit)))

            var events: [DatabaseAuditEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                events.append(DatabaseAuditEvent(
                    id: sqlite3_column_int64(statement, 0),
                    date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    action: text(statement, 2),
                    detail: text(statement, 3),
                    stationProfileID: UUID(uuidString: text(statement, 4))
                ))
            }
            return events
        }
    }

    func loadQSLJobs(profileID: UUID) throws -> [QSLQueueJob] {
        try queue.sync {
            let statement = try prepare("""
                SELECT id, station_profile_id, qso_id, provider, adif, state, attempts,
                       next_attempt_at, message, created_at, updated_at
                FROM qsl_jobs
                WHERE station_profile_id = ?
                ORDER BY created_at DESC;
                """)
            defer { sqlite3_finalize(statement) }
            bind(profileID.uuidString, to: 1, in: statement)

            var jobs: [QSLQueueJob] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = UUID(uuidString: text(statement, 0)),
                      let stationProfileID = UUID(uuidString: text(statement, 1)),
                      let qsoID = UUID(uuidString: text(statement, 2)),
                      let provider = QSLProvider(rawValue: text(statement, 3)),
                      let state = QSLQueueState(rawValue: text(statement, 5)) else { continue }
                jobs.append(QSLQueueJob(
                    id: id,
                    stationProfileID: stationProfileID,
                    qsoID: qsoID,
                    provider: provider,
                    adif: text(statement, 4),
                    state: state,
                    attempts: Int(sqlite3_column_int(statement, 6)),
                    nextAttemptAt: optionalDate(statement, 7),
                    message: text(statement, 8),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10))
                ))
            }
            return jobs
        }
    }

    func saveQSLJob(_ job: QSLQueueJob) throws {
        try queue.sync {
            let statement = try prepare("""
                INSERT INTO qsl_jobs (
                    id, station_profile_id, qso_id, provider, adif, state, attempts,
                    next_attempt_at, message, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(station_profile_id, qso_id, provider) DO UPDATE SET
                    adif = excluded.adif,
                    state = excluded.state,
                    attempts = excluded.attempts,
                    next_attempt_at = excluded.next_attempt_at,
                    message = excluded.message,
                    updated_at = excluded.updated_at;
                """)
            defer { sqlite3_finalize(statement) }
            bind(job.id.uuidString, to: 1, in: statement)
            bind(job.stationProfileID.uuidString, to: 2, in: statement)
            bind(job.qsoID.uuidString, to: 3, in: statement)
            bind(job.provider.rawValue, to: 4, in: statement)
            bind(job.adif, to: 5, in: statement)
            bind(job.state.rawValue, to: 6, in: statement)
            sqlite3_bind_int(statement, 7, Int32(job.attempts))
            bind(job.nextAttemptAt, to: 8, in: statement)
            bind(job.message, to: 9, in: statement)
            sqlite3_bind_double(statement, 10, job.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 11, job.updatedAt.timeIntervalSince1970)
            try stepDone(statement)
        }
    }

    func saveQSLJobs(_ jobs: [QSLQueueJob]) throws {
        guard !jobs.isEmpty else { return }
        try queue.sync {
            try execute("BEGIN IMMEDIATE TRANSACTION;")
            do {
                let statement = try prepare("""
                    INSERT INTO qsl_jobs (
                        id, station_profile_id, qso_id, provider, adif, state, attempts,
                        next_attempt_at, message, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(station_profile_id, qso_id, provider) DO UPDATE SET
                        adif = excluded.adif,
                        state = excluded.state,
                        attempts = excluded.attempts,
                        next_attempt_at = excluded.next_attempt_at,
                        message = excluded.message,
                        updated_at = excluded.updated_at;
                    """)
                defer { sqlite3_finalize(statement) }
                for job in jobs {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(job.id.uuidString, to: 1, in: statement)
                    bind(job.stationProfileID.uuidString, to: 2, in: statement)
                    bind(job.qsoID.uuidString, to: 3, in: statement)
                    bind(job.provider.rawValue, to: 4, in: statement)
                    bind(job.adif, to: 5, in: statement)
                    bind(job.state.rawValue, to: 6, in: statement)
                    sqlite3_bind_int(statement, 7, Int32(job.attempts))
                    bind(job.nextAttemptAt, to: 8, in: statement)
                    bind(job.message, to: 9, in: statement)
                    sqlite3_bind_double(statement, 10, job.createdAt.timeIntervalSince1970)
                    sqlite3_bind_double(statement, 11, job.updatedAt.timeIntervalSince1970)
                    try stepDone(statement)
                }
                try execute("COMMIT;")
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
        }
    }

    func deleteQSLJobs(profileID: UUID, states: Set<QSLQueueState>) throws {
        guard !states.isEmpty else { return }
        try queue.sync {
            let placeholders = Array(repeating: "?", count: states.count).joined(separator: ",")
            let statement = try prepare("DELETE FROM qsl_jobs WHERE station_profile_id = ? AND state IN (\(placeholders));")
            defer { sqlite3_finalize(statement) }
            bind(profileID.uuidString, to: 1, in: statement)
            for (offset, state) in states.sorted(by: { $0.rawValue < $1.rawValue }).enumerated() {
                bind(state.rawValue, to: Int32(offset + 2), in: statement)
            }
            try stepDone(statement)
        }
    }

    func loadAwardClaims(profileID: UUID) throws -> [AwardClaim] {
        try queue.sync {
            let statement = try prepare("""
                SELECT award_id, stage, submitted_at, granted_at, note, updated_at
                FROM award_claims
                WHERE station_profile_id = ?
                ORDER BY award_id;
                """)
            defer { sqlite3_finalize(statement) }
            bind(profileID.uuidString, to: 1, in: statement)
            var claims: [AwardClaim] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let stage = AwardLifecycleStage(rawValue: text(statement, 1)) else { continue }
                claims.append(AwardClaim(
                    stationProfileID: profileID,
                    awardID: text(statement, 0),
                    stage: stage,
                    submittedAt: optionalDate(statement, 2),
                    grantedAt: optionalDate(statement, 3),
                    note: text(statement, 4),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
                ))
            }
            return claims
        }
    }

    func saveAwardClaim(_ claim: AwardClaim) throws {
        try queue.sync {
            let statement = try prepare("""
                INSERT INTO award_claims (
                    id, station_profile_id, award_id, stage, submitted_at, granted_at, note, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(station_profile_id, award_id) DO UPDATE SET
                    stage = excluded.stage,
                    submitted_at = excluded.submitted_at,
                    granted_at = excluded.granted_at,
                    note = excluded.note,
                    updated_at = excluded.updated_at;
                """)
            defer { sqlite3_finalize(statement) }
            bind(claim.id, to: 1, in: statement)
            bind(claim.stationProfileID.uuidString, to: 2, in: statement)
            bind(claim.awardID, to: 3, in: statement)
            bind(claim.stage.rawValue, to: 4, in: statement)
            bind(claim.submittedAt, to: 5, in: statement)
            bind(claim.grantedAt, to: 6, in: statement)
            bind(claim.note, to: 7, in: statement)
            sqlite3_bind_double(statement, 8, claim.updatedAt.timeIntervalSince1970)
            try stepDone(statement)
            try insertAudit(action: "award-stage", detail: "\(claim.awardID): \(claim.stage.rawValue)", profileID: claim.stationProfileID)
        }
    }

    private func openDatabase() throws {
        guard db == nil else { return }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database."
            if let handle { sqlite3_close_v2(handle) }
            throw LogbookDatabaseError.sqlite(message: message)
        }
        db = handle
        sqlite3_busy_timeout(handle, 5_000)
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=FULL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    private func closeDatabase() {
        guard let db else { return }
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        sqlite3_close_v2(db)
        self.db = nil
    }

    private func initializeSchema() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS station_profiles (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                callsign TEXT NOT NULL,
                qth TEXT NOT NULL DEFAULT '',
                grid TEXT NOT NULL DEFAULT '',
                latitude TEXT NOT NULL DEFAULT '',
                longitude TEXT NOT NULL DEFAULT '',
                dxcc_code TEXT NOT NULL DEFAULT '',
                country TEXT NOT NULL DEFAULT '',
                cq_zone TEXT NOT NULL DEFAULT '',
                itu_zone TEXT NOT NULL DEFAULT '',
                radio_model TEXT NOT NULL DEFAULT '',
                power_watts INTEGER NOT NULL DEFAULT 100,
                antenna_description TEXT NOT NULL DEFAULT '',
                antenna_height_meters INTEGER NOT NULL DEFAULT 10,
                valid_from REAL,
                valid_to REAL,
                lotw_station_location TEXT NOT NULL DEFAULT '',
                eqsl_qth_nickname TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS qsos (
                id TEXT PRIMARY KEY,
                station_profile_id TEXT NOT NULL,
                unique_key TEXT NOT NULL,
                call TEXT NOT NULL DEFAULT '',
                qso_date TEXT NOT NULL DEFAULT '',
                time_on TEXT NOT NULL DEFAULT '',
                band TEXT NOT NULL DEFAULT '',
                mode TEXT NOT NULL DEFAULT '',
                fields_json TEXT NOT NULL,
                sort_order INTEGER NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY(station_profile_id) REFERENCES station_profiles(id) ON DELETE RESTRICT
            );

            CREATE INDEX IF NOT EXISTS idx_qsos_station_sort
                ON qsos(station_profile_id, sort_order);
            CREATE INDEX IF NOT EXISTS idx_qsos_station_unique_key
                ON qsos(station_profile_id, unique_key);
            CREATE INDEX IF NOT EXISTS idx_qsos_call_date
                ON qsos(call, qso_date, time_on);

            CREATE TABLE IF NOT EXISTS qso_field_catalog (
                station_profile_id TEXT NOT NULL,
                field_name TEXT NOT NULL,
                is_database_only INTEGER NOT NULL DEFAULT 0,
                first_seen_at REAL NOT NULL,
                last_seen_at REAL NOT NULL,
                PRIMARY KEY(station_profile_id, field_name),
                FOREIGN KEY(station_profile_id) REFERENCES station_profiles(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS audit_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at REAL NOT NULL,
                action TEXT NOT NULL,
                detail TEXT NOT NULL,
                station_profile_id TEXT
            );

            CREATE TABLE IF NOT EXISTS qsl_jobs (
                id TEXT PRIMARY KEY,
                station_profile_id TEXT NOT NULL,
                qso_id TEXT NOT NULL,
                provider TEXT NOT NULL,
                adif TEXT NOT NULL,
                state TEXT NOT NULL,
                attempts INTEGER NOT NULL DEFAULT 0,
                next_attempt_at REAL,
                message TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                UNIQUE(station_profile_id, qso_id, provider),
                FOREIGN KEY(station_profile_id) REFERENCES station_profiles(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_qsl_jobs_station_state
                ON qsl_jobs(station_profile_id, state, next_attempt_at);

            CREATE TABLE IF NOT EXISTS award_claims (
                id TEXT PRIMARY KEY,
                station_profile_id TEXT NOT NULL,
                award_id TEXT NOT NULL,
                stage TEXT NOT NULL,
                submitted_at REAL,
                granted_at REAL,
                note TEXT NOT NULL DEFAULT '',
                updated_at REAL NOT NULL,
                UNIQUE(station_profile_id, award_id),
                FOREIGN KEY(station_profile_id) REFERENCES station_profiles(id) ON DELETE CASCADE
            );
            """)
        try setMetadataValue("3", for: "schema.version")
    }

    private func updateFieldCatalog(
        profileID: UUID,
        headers: [String],
        records: [PersistedQSO],
        timestamp: TimeInterval
    ) throws {
        let fields = Set(headers.map(TableColumnPolicy.normalized)).union(
            records.flatMap { $0.fields.keys.map(TableColumnPolicy.normalized) }
        ).filter { !$0.isEmpty }
        guard !fields.isEmpty else { return }

        let statement = try prepare("""
            INSERT INTO qso_field_catalog (
                station_profile_id, field_name, is_database_only, first_seen_at, last_seen_at
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(station_profile_id, field_name) DO UPDATE SET
                is_database_only = excluded.is_database_only,
                last_seen_at = excluded.last_seen_at;
            """)
        defer { sqlite3_finalize(statement) }

        for field in fields {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(profileID.uuidString, to: 1, in: statement)
            bind(field, to: 2, in: statement)
            sqlite3_bind_int(statement, 3, TableColumnPolicy.isDatabaseOnly(field) ? 1 : 0)
            sqlite3_bind_double(statement, 4, timestamp)
            sqlite3_bind_double(statement, 5, timestamp)
            try stepDone(statement)
        }
    }

    private func qsoCountInternal(profileID: UUID?) throws -> Int {
        let sql = profileID == nil
            ? "SELECT COUNT(*) FROM qsos;"
            : "SELECT COUNT(*) FROM qsos WHERE station_profile_id = ?;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        if let profileID { bind(profileID.uuidString, to: 1, in: statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw currentError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func metadataValue(for key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM metadata WHERE key = ?;")
        defer { sqlite3_finalize(statement) }
        bind(key, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(statement, 0)
    }

    private func setMetadataValue(_ value: String, for key: String) throws {
        let statement = try prepare("""
            INSERT INTO metadata(key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value;
            """)
        defer { sqlite3_finalize(statement) }
        bind(key, to: 1, in: statement)
        bind(value, to: 2, in: statement)
        try stepDone(statement)
    }

    private func insertAudit(action: String, detail: String, profileID: UUID?) throws {
        let statement = try prepare("""
            INSERT INTO audit_log(created_at, action, detail, station_profile_id)
            VALUES (?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
        bind(action, to: 2, in: statement)
        bind(detail, to: 3, in: statement)
        if let profileID {
            bind(profileID.uuidString, to: 4, in: statement)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        try stepDone(statement)
    }

    private func backupDatabase(to destinationURL: URL) throws {
        guard let sourceDB = db else { throw LogbookDatabaseError.unavailable("Database is closed.") }
        var destinationDB: OpaquePointer?
        guard sqlite3_open_v2(destinationURL.path, &destinationDB, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let destinationDB else {
            throw LogbookDatabaseError.sqlite(message: "Unable to create backup database.")
        }
        defer { sqlite3_close_v2(destinationDB) }

        guard let backup = sqlite3_backup_init(destinationDB, "main", sourceDB, "main") else {
            throw LogbookDatabaseError.sqlite(message: String(cString: sqlite3_errmsg(destinationDB)))
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard (stepResult == SQLITE_DONE || stepResult == SQLITE_OK), finishResult == SQLITE_OK else {
            throw LogbookDatabaseError.sqlite(message: String(cString: sqlite3_errmsg(destinationDB)))
        }
    }

    private func restoreOpenDatabase(from sourceURL: URL) throws {
        guard let destinationDB = db else {
            throw LogbookDatabaseError.unavailable("Database is closed.")
        }

        var sourceDB: OpaquePointer?
        guard sqlite3_open_v2(sourceURL.path, &sourceDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let sourceDB else {
            if let sourceDB { sqlite3_close_v2(sourceDB) }
            throw LogbookDatabaseError.invalidBackup
        }
        defer { sqlite3_close_v2(sourceDB) }

        guard let restore = sqlite3_backup_init(destinationDB, "main", sourceDB, "main") else {
            throw currentError()
        }
        let stepResult = sqlite3_backup_step(restore, -1)
        let finishResult = sqlite3_backup_finish(restore)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw currentError()
        }
        sqlite3_wal_checkpoint_v2(destinationDB, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
    }

    private func validateDatabase(at url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open backup."
            if let handle { sqlite3_close_v2(handle) }
            throw LogbookDatabaseError.sqlite(message: "Backup validation failed: \(message)")
        }
        defer { sqlite3_close_v2(handle) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA quick_check;", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LogbookDatabaseError.sqlite(message: "Backup validation query failed: \(String(cString: sqlite3_errmsg(handle)))")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let result = sqlite3_column_text(statement, 0) else {
            throw LogbookDatabaseError.sqlite(message: "Backup integrity check failed: \(String(cString: sqlite3_errmsg(handle)))")
        }
        let checkResult = String(cString: result)
        guard checkResult.lowercased() == "ok" else {
            throw LogbookDatabaseError.sqlite(message: "Backup integrity check returned: \(checkResult)")
        }
    }

    private func validateOpenDatabase() throws {
        let statement = try prepare("PRAGMA quick_check;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw currentError()
        }
        let result = text(statement, 0)
        guard result.lowercased() == "ok" else {
            throw LogbookDatabaseError.sqlite(message: "Restored database integrity check returned: \(result)")
        }
    }

    private func backupSnapshot(for url: URL) throws -> BackupSnapshot {
        let manifestURL = url.appendingPathExtension("json")
        let manifest = (try? Data(contentsOf: manifestURL)).flatMap {
            try? JSONDecoder().decode(BackupManifest.self, from: $0)
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
        let createdAt = manifest?.createdAt ?? values.creationDate ?? Date.distantPast
        return BackupSnapshot(
            id: url.lastPathComponent,
            url: url,
            createdAt: createdAt,
            reason: manifest?.reason ?? "Versioned backup",
            sizeBytes: Int64(values.fileSize ?? 0)
        )
    }

    private func pruneBackups(retainCount: Int) throws {
        let snapshots = listBackupsInternal()
        guard snapshots.count > retainCount else { return }
        for snapshot in snapshots.dropFirst(retainCount) {
            try? FileManager.default.removeItem(at: snapshot.url)
            try? FileManager.default.removeItem(at: snapshot.url.appendingPathExtension("json"))
        }
    }

    private func listBackupsInternal() -> [BackupSnapshot] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: backupDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "sqlite" }
            .compactMap { try? backupSnapshot(for: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db else { throw LogbookDatabaseError.unavailable("Database is closed.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw currentError()
        }
        return statement
    }

    private func prepare(_ sql: String, in handle: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LogbookDatabaseError.sqlite(message: String(cString: sqlite3_errmsg(handle)))
        }
        return statement
    }

    private func decodedFields(_ statement: OpaquePointer, column: Int32) -> [String: String]? {
        guard let jsonText = sqlite3_column_text(statement, column) else { return nil }
        let data = Data(bytes: jsonText, count: Int(sqlite3_column_bytes(statement, column)))
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private func scopedIdentity(profileID: String, key: String) -> String {
        "\(profileID.lowercased())|\(key)"
    }

    private func execute(_ sql: String) throws {
        guard let db else { throw LogbookDatabaseError.unavailable("Database is closed.") }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, sql, nil, nil, &errorPointer)
        guard status == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorPointer)
            throw LogbookDatabaseError.sqlite(message: message)
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() }
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func bind(_ value: Date?, to index: Int32, in statement: OpaquePointer) {
        if let value {
            sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func optionalDate(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private func currentError() -> LogbookDatabaseError {
        guard let db else { return .unavailable("Database is closed.") }
        return .sqlite(message: String(cString: sqlite3_errmsg(db)))
    }

    private static func uniqueKey(fields: [String: String]) -> String {
        QSOIdentity.exactKey(fields: fields)
    }

    private static func fileSafeReason(_ value: String) -> String {
        let clean = value.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let collapsed = String(clean).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return String(collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(40)).isEmpty
            ? "snapshot"
            : String(collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(40))
    }
}
