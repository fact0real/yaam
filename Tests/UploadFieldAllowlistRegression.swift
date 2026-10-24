//
//  UploadFieldAllowlistRegression.swift
//  YAAM
//
//  Which fields of a QSO leave YAAM towards a service (patch 61). Each upload destination gets only the ADIF fields
//  of its allowlist: never the other station's personal data unless the operator switches it on in Data Safety (both
//  switches are off here, as in a new install), never an *_INTL field, another program's APP_ field or a name that is
//  not ADIF, and LoTW only what TQSL signs. COMMENT goes out without YAAM's [KEY=value] tags everywhere.
//  The QSL Hub part runs the app's own code (QSLSyncAll.review, which builds the ADIF a job sends); the builders that
//  do not build on their own (HRDLog, HamQTH, Wavelog, the Zero-Click daemon and the Data Safety page) are checked in
//  their source. It uses only what 1.37.36 already has, so it builds with and without the patch.
//  Run from the repository root:
//    swiftc -parse-as-library Tests/UploadFieldAllowlistRegression.swift YAAM/QSLSyncAll.swift YAAM/QSLHub.swift \
//      YAAM/ADIFParser.swift YAAM/FormURLEncoding.swift YAAM/QSOMetadataFormatter.swift YAAM/OperatorModels.swift \
//      YAAM/AmateurBandSettings.swift YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift \
//      YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift -o ufa && ./ufa
//  No network, no preferences written: nothing is uploaded. The data is invented.
//

import Foundation

// Stand-in for the QSO record of AppState.swift, which the band plan in OperatorModels.swift reads.
nonisolated struct QSORecordModel {
    var fields: [String: String] = [:]
    var isConfirmed = false
    subscript(key: String) -> String { fields[key] ?? "" }
}

// Stand-in for YAAM/TQSLCoordinator.swift, which runs the TQSL program; this test never uploads.
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

@main
@MainActor
struct UploadFieldAllowlistRegression {
    static var passed = 0
    static var failed = 0

    static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            passed += 1
            print("PASS \(name)")
        } else {
            failed += 1
            print("FAIL \(name)" + (detail.isEmpty ? "" : "   [\(detail)]"))
        }
    }

    static func source(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }

    /// The names of the fields in an ADIF record, in upper case.
    static func names(_ adif: String) -> Set<String> {
        var result = Set<String>()
        var rest = Substring(adif)
        while let open = rest.firstIndex(of: "<") {
            guard let close = rest[open...].firstIndex(of: ">") else { break }
            let tag = rest[rest.index(after: open)..<close]
            let name = tag.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
            if !name.isEmpty, name.uppercased() != "EOR", name.uppercased() != "EOH" { result.insert(name.uppercased()) }
            rest = rest[rest.index(after: close)...]
        }
        return result
    }

    /// The ADIF the QSL Hub sends for one job of `provider`, built by QSLSyncAll.review as the queue does.
    static func sentADIF(_ provider: QSLProvider, _ fields: [String: String]) -> String {
        let job = QSLQueueJob(stationProfileID: UUID(), qsoID: UUID(), provider: provider, adif: "<CALL:5>K0ABC<EOR>")
        if case .send(let adif) = QSLSyncAll.review(job, currentFields: fields) { return adif }
        return ""
    }

    static func main() {
        // One invented QSO carrying the QSO fields, the other station's personal data, this station's own street,
        // another program's APP_ field, a name that is not ADIF, an *_INTL field and a YAAM local-only field.
        let qsoFields: [String: String] = [
            "CALL": "K0ABC", "QSO_DATE": "20261017", "TIME_ON": "1200", "BAND": "20m", "MODE": "SSB",
            "FREQ": "14.250", "RST_SENT": "59", "RST_RCVD": "57", "GRIDSQUARE": "BL10", "STATE": "HI", "CNTY": "HI,HONOLULU",
            "DXCC": "110", "STATION_CALLSIGN": "EB0LAB", "MY_GRIDSQUARE": "LG89",
        ]
        let personal: [String: String] = [
            "NAME": "Pau", "QTH": "Vilaprova", "EMAIL": "email-here", "ADDRESS": "Street 0", "WEB": "web-here",
            "AGE": "40", "LAT": "latitude-here", "LON": "longitude-here", "NOTES": "met at a field day",
        ]
        let otherNames: [String: String] = [
            "NAME_INTL": "Pàu", "APP_LOTW_FOO": "x", "FOO_BAR": "x", "APP_YAAM_X": "x", "MY_STREET": "Street 0",
        ]
        var record = qsoFields.merging(personal) { $1 }.merging(otherNames) { $1 }
        record["COMMENT"] = "[RANK=1] nice chat"

        // ---- the QSL Hub: QRZ, eQSL and Club Log get the QSO fields, never the personal data
        for provider in [QSLProvider.qrz, .eqsl, .clubLog] {
            let adif = sentADIF(provider, record)
            let sent = names(adif)
            check("\(provider.rawValue): the QSO fields are sent; free text stays private by default",
                  Set(qsoFields.keys).isSubset(of: sent) && !adif.contains("COMMENT"), adif)
            let leaked = sent.intersection(personal.keys)
            check("\(provider.rawValue): the other station's name, QTH and contact details are not sent (both switches off)",
                  !adif.isEmpty && leaked.isEmpty && !adif.contains("email-here") && !adif.contains("Vilaprova"),
                  leaked.sorted().joined(separator: ","))
            let others = sent.intersection(otherNames.keys)
            check("\(provider.rawValue): no *_INTL, no other program's APP_ field, no non-ADIF name and no MY_STREET",
                  !adif.isEmpty && others.isEmpty, others.sorted().joined(separator: ","))
        }

        // ---- LoTW: only what TQSL signs or compares with the station location
        let lotw = sentADIF(.lotw, record)
        let lotwSent = names(lotw)
        check("LoTW: the file for TQSL has the call, date, time, band, mode, frequency and the station's own fields",
              ["CALL", "QSO_DATE", "TIME_ON", "BAND", "MODE", "FREQ", "STATION_CALLSIGN", "MY_GRIDSQUARE"].allSatisfy { lotwSent.contains($0) },
              lotw)
        let lotwExtra = lotwSent.intersection(["RST_SENT", "RST_RCVD", "GRIDSQUARE", "STATE", "CNTY", "DXCC", "COMMENT",
                                               "NAME", "QTH", "EMAIL", "ADDRESS", "LAT", "LON", "NOTES", "MY_STREET",
                                               "APP_LOTW_FOO", "FOO_BAR", "NAME_INTL"])
        check("LoTW: nothing else goes into that file: no report, other station's location, comment or personal data",
              !lotw.isEmpty && lotwExtra.isEmpty, lotwExtra.sorted().joined(separator: ","))

        // ---- the old local-only filter is unchanged (a local export still keeps EMAIL)
        check("serviceFields and isLocalOnly are unchanged: APP_YAAM_ and QSL_MEDIA_PATH are local-only, EMAIL is not",
              QSLUploadStatus.isLocalOnly("APP_YAAM_X") && QSLUploadStatus.isLocalOnly("QSL_MEDIA_PATH") &&
              !QSLUploadStatus.isLocalOnly("EMAIL") && QSLUploadStatus.serviceFields(record)["EMAIL"] == "email-here" &&
              QSLUploadStatus.serviceFields(record)["APP_YAAM_X"] == nil)

        // ---- the builders that do not build on their own, in their source
        let syncAll = source("YAAM/QSLSyncAll.swift")
        let hub = source("YAAM/AppStateQSLHub.swift")
        let wavelog = source("YAAM/WavelogClient.swift")
        let wavelogSync = source("YAAM/WavelogSyncEngine.swift")
        let appState = source("YAAM/AppState.swift")
        let hrdlog = source("YAAM/HRDLogClient.swift")
        let hamqth = source("YAAM/HamQTHUploadClient.swift")
        let daemon = source("YAAM/ZeroClickCloudUploadDaemon.swift")
        let safety = source("YAAM/DataSafetySettingsView.swift")
        let queued = QSLSyncAll.queueChanges(records: [(id: UUID(), fields: record)], profileID: UUID(),
                                             providers: Set(QSLProvider.allCases), existingJobs: [])
        check("the QSL Hub queues and sends each service's own filtered ADIF",
              hub.contains("let changedJobs = QSLSyncAll.queueChanges(") &&
              queued.count == QSLProvider.allCases.count &&
              queued.allSatisfy { $0.adif == sentADIF($0.provider, record) })
        check("Wavelog, one QSO: formatSingleADIF starts from uploadFields for .wavelog",
              wavelog.contains("var normalizedFields = QSLUploadStatus.uploadFields(record.fields, for: .wavelog)") &&
              !wavelog.contains("serviceFields("))
        check("Wavelog, full sync: the whole-log ADIF starts from uploadFields for .wavelog",
              wavelogSync.contains("let dicts = uploadRecords.map { QSLUploadStatus.uploadFields($0.fields, for: .wavelog) }") &&
              !wavelogSync.contains("serviceFields("))
        check("HRDLog and HamQTH: toADIFRecordString takes the destination and starts from uploadFields",
              appState.contains("func toADIFRecordString(for destination: QSLUploadDestination) -> String {") &&
              appState.contains("var exportFields = QSLUploadStatus.uploadFields(fields, for: destination)") &&
              !appState.contains("QSLUploadStatus.serviceFields(fields)"))
        check("HRDLog sends its single QSO and its batch for .hrdlog, HamQTH for .hamqth",
              hrdlog.components(separatedBy: "toADIFRecordString(for: .hrdlog)").count == 3 &&
              hamqth.components(separatedBy: "toADIFRecordString(for: .hamqth)").count == 3 &&
              !hrdlog.contains("toADIFRecordString()") && !hamqth.contains("toADIFRecordString()"))
        check("the Zero-Click daemon builds each service's ADIF for that service, from uploadFields",
              daemon.contains("let adif = buildSingleQSOADIF(record, for: .qrz)") &&
              daemon.contains("let adif = buildSingleQSOADIF(record, for: .clubLog)") &&
              daemon.contains("let adif = buildSingleQSOADIF(record, for: .eqsl)") &&
              daemon.contains("let adifContent = buildSingleQSOADIF(record, for: .lotw)") &&
              daemon.contains("var normalizedFields = QSLUploadStatus.uploadFields(record.fields, for: destination)") &&
              !daemon.contains("buildSingleQSOADIF(record)"))
        check("Data Safety has the two switches, off until the operator switches them on, under the keys uploads read",
              safety.contains("@AppStorage(\"uploadShareNameAndQTH\") private var uploadShareNameAndQTH = false") &&
              safety.contains("@AppStorage(\"uploadShareContactDetails\") private var uploadShareContactDetails = false") &&
              syncAll.contains("defaults.bool(forKey: \"uploadShareNameAndQTH\")") &&
              syncAll.contains("defaults.bool(forKey: \"uploadShareContactDetails\")"))

        print("\nUploadFieldAllowlistRegression: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
