// Compile with the same QSL domain dependencies as Tests/QRZIncomingRecoveryRegression.swift, plus YAAM/UploadFileReader.swift.
import Foundation
struct QSORecordModel { var fields: [String:String] = [:]; var isConfirmed = false; subscript(_ key: String) -> String { fields[key] ?? "" } }
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



@main struct CloudUploadProviderRegression {
    static func main() {
        for raw in ["", " ", "OK", "<html>Login required</html>", "RESULT=FAIL&REASON=No+key", "RESULT=AUTH"] {
            precondition(!QSLUploadStatus.qrzReply(raw).accepted, "An HTTP 2xx body must contain explicit acceptance: \(raw)")
        }
        precondition(QSLUploadStatus.qrzReply("RESULT=OK&LOGID=123").accepted)
        let duplicate = QSLUploadStatus.qrzReply("RESULT=FAIL&REASON=duplicate")
        precondition(duplicate.accepted && duplicate.duplicate)
        precondition(CloudUploadNotice.outcome(accepted: 2, waiting: 0, rejected: 1) == .needsAttention)
        precondition(CloudUploadNotice.outcome(accepted: 2, waiting: 1, rejected: 0) == .waiting)
        precondition(CloudUploadNotice.outcome(accepted: 3, waiting: 0, rejected: 0) == .accepted)
        print("PASS provider result policy: empty/malformed QRZ 2xx cannot succeed; duplicate and partial outcomes are explicit")
    }
}
