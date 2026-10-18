// Stand-ins only for side effects around two production AppState methods, inserted by the runner.
import Foundation

nonisolated struct QSORecordModel {
    var id = UUID()
    var index = 0
    var fields: [String: String] = [:]
    var isConfirmed = false
    var uniqueKey: String { fields["CALL", default: ""] + fields["FREQ", default: ""] }
    subscript(key: String) -> String { fields[key] ?? "" }
}
nonisolated struct PersistedQSO { var id: UUID; var index: Int; var fields: [String: String] }
nonisolated struct FakeDatabase {
    func saveWorkspace(profileID: UUID, headers: [String], records: [PersistedQSO], allowEmptyReplacement: Bool, replaceMissingRecords: Bool) throws {}
}
nonisolated enum YAAMPersistenceError: Error { case workspaceNotLoaded }
struct FakeSession {
    var isActive = true
    var contestID = "LAB"
    var nextSerial = 1
    var sentExchange = "001"
    var operatorCallsign = ""
    var displayName = "LAB"
}
struct FakeProfile { var lotwStationLocation = "" }
final class ZeroClickCloudUploadDaemon {
    static let shared = ZeroClickCloudUploadDaemon()
    var ownsWavelogPush = true
    var uploads = 0
    func dispatch(record: QSORecordModel, stationID: String?, stationLocation: String?, qrzKeyOverride: String?) { uploads += 1 }
}
final class WavelogSyncEngine {
    static let shared = WavelogSyncEngine()
    func autoPushSingleQSO(record: QSORecordModel) { preconditionFailure("Unexpected direct upload") }
}
final class HRDLogClient {
    static let shared = HRDLogClient()
    var autoUploadEnabled = false
    func uploadSingleQSO(record: QSORecordModel) async -> Bool { preconditionFailure("Unexpected upload") }
}
final class HamQTHUploadClient {
    static let shared = HamQTHUploadClient()
    var autoUploadEnabled = false
    func uploadSingleQSO(record: QSORecordModel) async -> Bool { preconditionFailure("Unexpected upload") }
}
@MainActor final class AppState {
    var isMasterMode = false
    var logbookDatabase: FakeDatabase?
    var activeStationProfileID: UUID? = UUID()
    var activeStationProfile: FakeProfile? = FakeProfile()
    var activeQRZAPIKey = ""
    var loadedWorkspaceProfileID: UUID?
    var databaseStatus = ""
    var tableHeaders: [String] = []
    var qsoRecords: [QSORecordModel] = []
    var workspaceSaveQueue = DispatchQueue(label: "yaam-test-save")
    var loadedFileURL: URL?
    var loadedFileOriginalContent: String?
    var currentContestSession: FakeSession? = FakeSession()
    var currentStationCallsign = "K0ABC"
    var contestStatus = ""
    var messages: [String] = []
    enum Sound { case success }
    func appendLog(_ message: String) { messages.append(message) }
    func isValidOperatorCallsign(_ call: String) -> Bool { true }
    func stationTaggedFields(_ fields: [String: String]) -> [String: String] { fields }
    func isSelfContact(_ fields: [String: String]) -> Bool { false }
    func persistQuickLog(_ record: QSORecordModel) {}
    func advanceContestSerial() { currentContestSession?.nextSerial += 1 }
    func playActivitySound(_ sound: Sound) {}
    // ACTUAL_METHODS
}
