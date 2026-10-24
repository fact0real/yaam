// Inert dependencies for the real roster/store. Never start AppState, radios, or accounts.
import Foundation
import Combine

// Only the AppState shell is inert; its graylist adapter below is the production source.
struct FilterCriteria {}
@MainActor final class AppState {
    let qslGraylist: QSLGraylistStore
    var activeStationProfileID: UUID?
    var isMasterMode = true
    var loadedWorkspaceProfileID: UUID?
    var qsoRecords: [QSORecordModel] = []
    var filterCriteria = FilterCriteria()
    var searchText = ""
    var logSearchMode = LogSearchMode.quick
    var selectedRecordIDs = Set<UUID>()
    var selectedTab = 5
    init(defaults: UserDefaults) { qslGraylist = QSLGraylistStore(defaults: defaults) }
}

nonisolated struct GeoCoordinate: Equatable, Sendable { var latitude = 0.0; var longitude = 0.0 }
nonisolated enum MaidenheadGridEngine {
    struct Box { let center = GeoCoordinate() }
    static func boundingBox(for: String) -> Box? { nil }
}
nonisolated enum GeodesicMath {
    static func distanceKm(from: GeoCoordinate, to: GeoCoordinate) -> Double { 0 }
    static func initialBearing(from: GeoCoordinate, to: GeoCoordinate) -> Double { 0 }
}
nonisolated public struct DXCCEntityInfo: Equatable, Sendable { var entityName = "Testland" }
nonisolated enum DXCCDatabase {
    static func resolve(callsign: String) -> DXCCEntityInfo { DXCCEntityInfo() }
}
@MainActor final class DigitalAudioAlertEngine {
    static let shared = DigitalAudioAlertEngine()
    func announceDirectedToMe(caller: String, snr: Int32, band: String) {}
    func announceNewDXCC(callsign: String, country: String, band: String) {}
    func announceNewBand(callsign: String, country: String, band: String) {}
    func announceNewGrid(callsign: String, grid: String, band: String) {}
}
@MainActor final class TacticalBandAdvisor {
    static let shared = TacticalBandAdvisor()
    func recordDecodes(_ decodes: [WSJTXLiveDecode], onBand: String) {}
}
nonisolated public struct WSJTXLiveDecode: Equatable, Sendable {
    var id = UUID()
    var callerCallsign: String
    var targetCallsign = "CQ"
    var grid = ""
    var message = "CQ"
    var snr: Int32 = -10
    var deltaFrequencyHz: UInt32 = 1000
    var mode = "FT8"
    var isCQ = true
    var receivedAt = Date()
    var port = 2237
    var sliceLabel = "VFO A"
}
