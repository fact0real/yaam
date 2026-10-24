// Run with Tests/run-incoming-recovery-regressions.sh; no live accounts or database are used.
import Foundation

struct QSORecordModel: Identifiable, Equatable {
    var isConfirmed = false
    var id = UUID(); var index: Int; var fields: [String:String]
    subscript(_ key: String) -> String { fields[key] ?? "" }
}
@MainActor final class AppState {
    var qsoRecords: [QSORecordModel] = []; var tableHeaders = ["CALL"]
    var activeStationProfileID: UUID? = UUID()
    var qslQueueJobs: [QSLQueueJob] = []
    var qslHubStatus = ""
    var isProcessingQSLQueue = false, isLoading = false, isSyncingAPI = false, isUnifiedSyncRunning = false, isCloudSyncRunning = false
    var persistedJobs: [QSLQueueJob] = []
    func retainQRZIncomingRecovery(_ request: QRZIncomingConfirmation) {}
    var currentStationCallsign = "EP2AES"; var isOwnStationLogOpen = true
    var rejectSave = false; var saveCount = 0
    func isSelfContact(_ fields: [String:String]) -> Bool { fields["CALL"] == currentStationCallsign }
    func persistIncomingRecovery(jobs: [QSLQueueJob]) throws {
        if rejectSave { throw NSError(domain: "TestDiskFailure", code: 1) }; saveCount += 1; persistedJobs = jobs
    }
    func refreshAwardProgress() {}
    func updateMobileCompanionSnapshot() {}
}
@MainActor final class QSLSyncEngine { static let shared = QSLSyncEngine(); var isSyncing = false }
@MainActor final class ZeroClickCloudUploadDaemon {
    static let shared = ZeroClickCloudUploadDaemon(); var isUploading = false; var isFlushingQueue = false
}
actor TQSLCoordinator {
    static let shared = TQSLCoordinator()
    func execute(
        adifContent: String? = nil,
        adifFileURL: URL? = nil,
        stationLocation: String? = nil,
        certificatePassword: String? = nil,
        customExecutablePath: String? = nil,
        securityBookmark: Data? = nil,
        timeoutSeconds: TimeInterval = 45.0
    ) async -> (success: Bool, message: String) { (false, "TQSL is not run in this test") }
}


@main struct QRZIncomingRecoveryRegression {
    @MainActor static func main() throws {
        let state = AppState()
        let request = QRZIncomingConfirmation(callsign: "W1AW", qsoDate: "20261020", requestedAt: "", rawSummary: "", qsoID: "42")
        var review = IncomingContactReview()
        review.call = "W1AW"; review.date = "20261020"; review.time = "1234"; review.band = "20M"
        review.mode = "FT8"; review.station = "EP2AES"; review.evidence = "Notebook compared with operator reply"
        func rejects(_ work: () throws -> Void) {
            do { try work(); preconditionFailure("Expected rejection") } catch {}
        }
        rejects { _ = try state.saveIncomingReview(review, request: request) }
        precondition(state.qsoRecords.isEmpty && state.saveCount == 0)
        review.verified = true
        state.isProcessingQSLQueue = true
        rejects { _ = try state.saveIncomingReview(review, request: request) }
        state.isProcessingQSLQueue = false
        QSLSyncEngine.shared.isSyncing = true
        rejects { _ = try state.saveIncomingReview(review, request: request) }
        QSLSyncEngine.shared.isSyncing = false
        ZeroClickCloudUploadDaemon.shared.isUploading = true
        rejects { _ = try state.saveIncomingReview(review, request: request) }
        ZeroClickCloudUploadDaemon.shared.isUploading = false
        precondition(state.qsoRecords.isEmpty && state.qslQueueJobs.isEmpty)
        let saved = try state.saveIncomingReview(review, request: request)
        precondition(state.qsoRecords.count == 1 && state.saveCount == 1)
        precondition(Set(state.persistedJobs.map(\.provider)) == [.lotw, .qrz, .clubLog])
        precondition(state.qslQueueJobs.count == 3)
        precondition(state.incomingRecoveryRecord(request)?.id == saved.id)
        precondition(saved["TIME_ON"] == "1234" && saved["APP_YAAM_INCOMING_REQUEST"] == "42")
        precondition(saved["QSL_RCVD"].isEmpty && saved["LOTW_QSL_RCVD"].isEmpty && saved["RST_SENT"].isEmpty)
        for provider in [QSLProvider.lotw, .qrz, .clubLog] {
            let adif = QSLUploadStatus.uploadADIF(saved.fields, for: provider)
            precondition(!adif.contains("EVIDENCE") && !adif.contains(review.evidence), "Review notes stay local")
        }
        let replay = try state.saveIncomingReview(review, request: request)
        precondition(replay.id == saved.id && state.qsoRecords.count == 1)
        // Existing confirmation/upload evidence survives linking an exact local record.
        state.qsoRecords[0].fields["QRZ_QSL_RCVD"] = "Y"
        state.qsoRecords[0].fields["QRZCOM_QSO_UPLOAD_STATUS"] = "Y"
        let linked = try state.saveIncomingReview(review, request: request)
        precondition(linked["QRZ_QSL_RCVD"] == "Y" && linked["QRZCOM_QSO_UPLOAD_STATUS"] == "Y")
        review.mode = "SSB"
        rejects { _ = try state.saveIncomingReview(review, request: request) }
        precondition(state.qsoRecords.count == 1, "A mismatched call/date candidate must not create another QSO implicitly")
        review.separateContact = true
        rejects { _ = try state.saveIncomingReview(review, request: request) }
        let separateRequest = QRZIncomingConfirmation(callsign: "W1AW", qsoDate: "20261020", requestedAt: "", rawSummary: "", qsoID: "43")
        state.rejectSave = true
        let old = state.qsoRecords, headers = state.tableHeaders
        let oldJobs = state.qslQueueJobs
        rejects { _ = try state.saveIncomingReview(review, request: separateRequest) }
        precondition(state.qslQueueJobs == oldJobs)
        precondition(state.qsoRecords == old && state.tableHeaders == headers, "Save failure must roll back visible state")
        state.rejectSave = false
        _ = try state.saveIncomingReview(review, request: separateRequest)
        precondition(state.qsoRecords.count == 2)
        precondition(state.qslQueueJobs.count == 6)
        review.mode = "FT8"; review.separateContact = false
        let manual = QRZIncomingConfirmation(callsign: "W1AW", qsoDate: "", requestedAt: "", rawSummary: "Manual recovery", qsoID: "manual:1")
        _ = try state.saveIncomingReview(review, request: manual)
        precondition(state.incomingRecoveryRecord(manual)?.id == saved.id && state.incomingRecoveryRecord(request)?.id == saved.id)
        review.mode = "SSB"; review.separateContact = true
        state.isOwnStationLogOpen = false
        rejects { _ = try state.saveIncomingReview(review, request: request) }
        state.isOwnStationLogOpen = true; review.station = "EP2AES/P"
        rejects { _ = try state.saveIncomingReview(review, request: request) }
        review.station = "EP2AES"; review.call = "EP2AES"
        rejects { _ = try state.saveIncomingReview(review, request: request) }
        review.call = "W1AW"
        state.qsoRecords.append(state.qsoRecords.last!)
        rejects { _ = try state.saveIncomingReview(review, request: request) }
        print("QRZ Incoming recovery regression passed: verification, candidates, duplicate replay, provenance, confirmation preservation, station checks and rollback")
    }
}
