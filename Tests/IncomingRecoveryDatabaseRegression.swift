// Uses a throwaway SQLite database. It never opens YAAM's real data directory or a service.
import Foundation
import SQLite3

struct QSORecordModel {
    var isConfirmed = false
    var id = UUID(); var index: Int; var fields: [String: String]
    var uniqueKey: String { QSOIdentity.exactKey(fields: fields) }
    subscript(_ key: String) -> String { fields[key] ?? "" }
}
actor TQSLCoordinator {
    static let shared = TQSLCoordinator()
    func execute(adifContent: String? = nil, adifFileURL: URL? = nil, stationLocation: String? = nil,
                 certificatePassword: String? = nil, customExecutablePath: String? = nil,
                 securityBookmark: Data? = nil, timeoutSeconds: TimeInterval = 45) async -> (success: Bool, message: String) {
        preconditionFailure("No live TQSL in persistence tests")
    }
}

@main struct IncomingRecoveryDatabaseRegression {
    @MainActor static func main() throws {
        func check(_ value: @autoclosure () throws -> Bool, _ message: String = "Check failed") rethrows {
            let result = try value(); precondition(result, message)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yaam-recovery-db-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try LogbookDatabase(baseDirectory: root.appendingPathComponent("Data"))
        let station = StationProfile(callsign: "EP2AES")
        let other = StationProfile(callsign: "EP2AES/P")
        try db.saveStationProfile(station); try db.saveStationProfile(other)
        let existing = PersistedQSO(id: UUID(), index: 1, fields: ["CALL": "K1ABC", "STATION_CALLSIGN": "EP2AES", "QSO_DATE": "20261020", "TIME_ON": "120000", "BAND": "20M", "MODE": "CW"])
        try db.saveWorkspace(profileID: station.id, headers: ["CALL"], records: [existing])
        var review = IncomingContactReview()
        review.call = "W1AW"; review.station = "EP2AES"; review.date = "20261020"; review.time = "1234"
        review.band = "20M"; review.mode = "FT8"; review.evidence = "Private operator reply"; review.verified = true
        var fields = review.fields
        fields["APP_YAAM_INCOMING_EVIDENCE"] = review.evidence
        let recovered = PersistedQSO(id: UUID(), index: 2, fields: fields)
        let jobs = QSLSyncAll.queueChanges(records: [(recovered.id, recovered.fields)], profileID: station.id,
            providers: QSLSyncAll.incomingRecoveryProviders, existingJobs: [])
        precondition(jobs.count == 3)
        let repeatedInput = QSLSyncAll.queueChanges(records: [(recovered.id, recovered.fields), (recovered.id, recovered.fields)],
            profileID: station.id, providers: QSLSyncAll.incomingRecoveryProviders, existingJobs: [])
        precondition(repeatedInput.count == 3, "One upload intent per contact and service even with duplicate input IDs")
        func sql(_ text: String) throws {
            var handle: OpaquePointer?
            guard sqlite3_open(db.databaseURL.path, &handle) == SQLITE_OK, let handle else { fatalError("Open test DB") }
            defer { sqlite3_close(handle) }
            guard sqlite3_exec(handle, text, nil, nil, nil) == SQLITE_OK else {
                throw NSError(domain: "TestSQL", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))])
            }
        }
        func commit(_ pending: [QSLQueueJob]) throws {
            try db.saveWorkspace(profileID: station.id, headers: ["CALL", "MODE"], records: [existing, recovered],
                                 replaceMissingRecords: false, pendingQSLJobs: pending, auditDetail: "Verified recovery")
        }
        func rejects(_ work: () throws -> Void) {
            do { try work(); preconditionFailure("Expected transaction failure") } catch {}
        }
        // Fail the second service after SQLite has already inserted the QSO and first outbox entry.
        try sql("CREATE TRIGGER fail_recovery_queue BEFORE INSERT ON qsl_jobs WHEN NEW.provider = 'qrz' BEGIN SELECT RAISE(ABORT, 'injected queue failure'); END;")
        rejects { try commit(jobs) }
        try check(db.loadWorkspace(profileID: station.id).records.map(\.id) == [existing.id])
        try check(db.loadWorkspace(profileID: station.id).headers == ["CALL"])
        try check(db.loadQSLJobs(profileID: station.id).isEmpty, "No orphaned upload when saving fails")
        try sql("DROP TRIGGER fail_recovery_queue;")
        // Even an audit failure at the end rolls back the local contact and all three jobs.
        try sql("CREATE TRIGGER fail_recovery_audit BEFORE INSERT ON audit_log WHEN NEW.action = 'incoming-recovery' BEGIN SELECT RAISE(ABORT, 'injected audit failure'); END;")
        rejects { try commit(jobs) }
        try check(db.loadWorkspace(profileID: station.id).records.count == 1)
        try check(db.loadQSLJobs(profileID: station.id).isEmpty)
        try sql("DROP TRIGGER fail_recovery_audit;")
        var foreign = jobs[0]; foreign.stationProfileID = other.id
        rejects { try commit([foreign]) }
        try check(db.loadWorkspace(profileID: station.id).records.count == 1)
        try commit(jobs)
        let reopened = try LogbookDatabase(baseDirectory: root.appendingPathComponent("Data"))
        try check(reopened.loadWorkspace(profileID: station.id).records.count == 2)
        let restoredJobs = try reopened.loadQSLJobs(profileID: station.id)
        precondition(Set(restoredJobs.map(\.provider)) == [.lotw, .qrz, .clubLog])
        precondition(restoredJobs.allSatisfy { !$0.adif.contains("EVIDENCE") && !$0.adif.contains(review.evidence) })
        try commit(jobs)
        try check(db.loadWorkspace(profileID: station.id).records.count == 2)
        try check(db.loadQSLJobs(profileID: station.id).count == 3, "Replay must not create extra contacts or jobs")
        var known = recovered.fields; known["APP_YAAM_QRZ_VERIFIED_PRESENT"] = "Y"
        let remaining = QSLSyncAll.queueChanges(records: [(recovered.id, known)], profileID: station.id,
            providers: QSLSyncAll.incomingRecoveryProviders, existingJobs: [])
        precondition(Set(remaining.map(\.provider)) == [.lotw, .clubLog], "An explicitly verified QRZ entry only needs the other services")
        precondition(known["QRZLOG_QSL_RCVD"] == nil && known["LOTW_QSL_RCVD"] == nil)
        var stopped = jobs
        for i in stopped.indices { stopped[i].state = stopped[i].provider == .lotw ? .succeeded : .blocked }
        let replay = QSLSyncAll.queueChanges(records: [(recovered.id, recovered.fields)], profileID: station.id,
            providers: QSLSyncAll.incomingRecoveryProviders, existingJobs: stopped)
        precondition(replay.isEmpty, "Recovery must preserve completed and stopped service states")
        print("Incoming SQLite recovery passed: atomic QSO/outbox/audit, rollback, ownership, restart, replay, privacy and known QRZ entry")
    }
}
