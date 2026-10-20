// swiftc -parse-as-library Tests/QRZIncomingRecoveryRegression.swift YAAM/AppStateIncomingReview.swift YAAM/IncomingContactReview.swift YAAM/QSOIdentity.swift YAAM/QSLSyncAll.swift YAAM/QSLHub.swift YAAM/ADIFParser.swift YAAM/FormURLEncoding.swift YAAM/QSOMetadataFormatter.swift YAAM/OperatorModels.swift YAAM/AmateurBandSettings.swift YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift -o /tmp/yaam-incoming-recovery && /tmp/yaam-incoming-recovery
import Foundation

struct QRZIncomingConfirmation {
    var callsign = "W1AW"; var qsoDate = "20261020"; var qsoID = "42"; var id = "W1AW|20261020"
}
struct QSORecordModel: Identifiable, Equatable {
    var isConfirmed = false
    var id = UUID(); var index: Int; var fields: [String:String]
    subscript(_ key: String) -> String { fields[key] ?? "" }
}
@MainActor final class AppState {
    var qsoRecords: [QSORecordModel] = []; var tableHeaders = ["CALL"]
    var currentStationCallsign = "EP2AES"; var isOwnStationLogOpen = true
    var rejectSave = false; var saveCount = 0
    func isSelfContact(_ fields: [String:String]) -> Bool { fields["CALL"] == currentStationCallsign }
    func persistCurrentWorkspace(reason: String) throws {
        if rejectSave { throw NSError(domain: "TestDiskFailure", code: 1) }; saveCount += 1
    }
    func refreshAwardProgress() {}
    func updateMobileCompanionSnapshot() {}
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
        let state = AppState(), request = QRZIncomingConfirmation()
        var review = IncomingContactReview()
        review.call = "W1AW"; review.date = "20261020"; review.time = "1234"; review.band = "20M"
        review.mode = "FT8"; review.station = "EP2AES"; review.evidence = "Notebook compared with operator reply"
        func rejects(_ work: () throws -> Void) {
            do { try work(); preconditionFailure("Expected rejection") } catch {}
        }
        rejects { _ = try state.saveIncomingReview(review, request: request) }
        precondition(state.qsoRecords.isEmpty && state.saveCount == 0)
        review.verified = true
        let saved = try state.saveIncomingReview(review, request: request)
        precondition(state.qsoRecords.count == 1 && state.saveCount == 1)
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
        state.rejectSave = true
        let old = state.qsoRecords, headers = state.tableHeaders
        rejects { _ = try state.saveIncomingReview(review, request: request) }
        precondition(state.qsoRecords == old && state.tableHeaders == headers, "Save failure must roll back visible state")
        state.rejectSave = false
        _ = try state.saveIncomingReview(review, request: request)
        precondition(state.qsoRecords.count == 2)
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
