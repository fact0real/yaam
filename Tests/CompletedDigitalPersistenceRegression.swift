// swiftc -parse-as-library Tests/CompletedDigitalPersistenceRegression.swift YAAM/AppStateCompletedDigitalContact.swift YAAM/DigitalContactCompletion.swift YAAM/QSOIdentity.swift -o /tmp/yaam-digital-persistence && /tmp/yaam-digital-persistence
import Foundation
struct QSORecordModel: Identifiable, Equatable {
    var id = UUID(); var index: Int; var fields: [String:String]
    subscript(_ key: String) -> String { fields[key] ?? "" }
}
enum DXCCDatabase {
    struct Entity { var entityName = "United States"; var continent = "NA"; var cqZone = 5; var ituZone = 8 }
    static func resolve(callsign: String) -> Entity { Entity() }
}
@MainActor final class ZeroClickCloudUploadDaemon {
    static let shared = ZeroClickCloudUploadDaemon(); var dispatches = 0; var ownsWavelogPush = true
    func dispatch(record: QSORecordModel, stationID: String?, stationLocation: String?, qrzKeyOverride: String?) { dispatches += 1 }
}
@MainActor final class WavelogSyncEngine {
    static let shared = WavelogSyncEngine(); func autoPushSingleQSO(record: QSORecordModel) {}
}
@MainActor final class HRDLogClient {
    static let shared = HRDLogClient(); var autoUploadEnabled = false
    func uploadSingleQSO(record: QSORecordModel) async -> Bool { false }
}
@MainActor final class HamQTHUploadClient {
    static let shared = HamQTHUploadClient(); var autoUploadEnabled = false
    func uploadSingleQSO(record: QSORecordModel) async -> Bool { false }
}
@MainActor final class AppState {
    struct Profile { var lotwStationLocation = "Synthetic test station" }
    enum Sound { case success }
    var qsoRecords: [QSORecordModel] = [], tableHeaders = ["CALL"]
    var isOwnStationLogOpen = true, currentStationCallsign = "EP2AES"
    var activeStationProfileID: UUID? = UUID(), activeStationProfile: Profile? = Profile(), activeQRZAPIKey: String? = nil
    var failSave = false, saves = 0, queued = 0
    var stored: [QSORecordModel] = []
    func stationTaggedFields(_ fields: [String:String]) -> [String:String] { fields }
    func isSelfContact(_ fields: [String:String]) -> Bool { fields["CALL"] == currentStationCallsign }
    func persistCurrentWorkspace(reason: String) throws {
        if failSave { throw NSError(domain: "SyntheticDiskFailure", code: 1) }; stored = qsoRecords; saves += 1
    }
    func enqueueAutomaticQSL(for record: QSORecordModel) { precondition(stored.contains { $0.id == record.id }); queued += 1 }
    func appendLog(_ text: String) {}
    func refreshAwardProgress() {}; func updateMobileCompanionSnapshot() {}; func playActivitySound(_ sound: Sound) {}
}
@main struct CompletedDigitalPersistenceRegression {
    @MainActor static func main() {
        let state = AppState(), id = UUID()
        let value = DigitalContactCompletion(id: id, call: "W1AW", grid: "FN31", protocolName: "FT4", band: "20m", stationCall: "EP2AES", stationGrid: "LM45",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000), endedAt: Date(timeIntervalSince1970: 1_800_000_030), transmitHz: 14_081_500, receiveHz: nil, sentReport: "-03", receivedReport: "-12")
        state.failSave = true
        precondition(!state.logFT8StationQSO(value, radioName: "Rig 2"))
        precondition(state.qsoRecords.isEmpty && state.queued == 0 && ZeroClickCloudUploadDaemon.shared.dispatches == 0)
        state.failSave = false
        precondition(state.logFT8StationQSO(value, radioName: "Rig 2"))
        precondition(state.qsoRecords.count == 1 && state.stored == state.qsoRecords && state.queued == 1)
        precondition(state.qsoRecords[0]["RADIO"] == "Rig 2" && state.qsoRecords[0]["SUBMODE"] == "FT4")
        precondition(state.qsoRecords[0]["QSL_RCVD"].isEmpty)
        precondition(ZeroClickCloudUploadDaemon.shared.dispatches == 1, "Multi-Rig reaches the shared upload path after durable save")
        precondition(state.logFT8StationQSO(value, radioName: "Rig 2"))
        precondition(state.qsoRecords.count == 1 && state.queued == 1 && ZeroClickCloudUploadDaemon.shared.dispatches == 1)
        state.currentStationCallsign = "EP2AES/P"
        precondition(!state.logFT8StationQSO(value))
        precondition(state.qsoRecords.count == 1)
        print("PASS digital persistence: Multi-Rig upload routing, save-before-upload, disk-failure rollback, station boundary, identity and replay")
    }
}
