//
//  UploadFieldSwitchesRegression.swift
//  YAAM
//
//  The upload allowlist of patch 61, through its own API: QSLUploadStatus.uploadFields, the two Data Safety switches
//  (UploadFieldOptions) and the per-service destinations (QSLUploadDestination). It needs the patch to build.
//  Run from the repository root:
//    swiftc -parse-as-library Tests/UploadFieldSwitchesRegression.swift YAAM/QSLSyncAll.swift YAAM/QSLHub.swift \
//      YAAM/ADIFParser.swift YAAM/FormURLEncoding.swift YAAM/QSOMetadataFormatter.swift YAAM/OperatorModels.swift \
//      YAAM/AmateurBandSettings.swift YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift \
//      YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift -o ufs && ./ufs
//  No network, no preferences written: the switches are given as UploadFieldOptions values. The data is invented.
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
struct UploadFieldSwitchesRegression {
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

    static func main() {
        let off = UploadFieldOptions(shareNameAndQTH: false, shareContactDetails: false)
        let nameOnly = UploadFieldOptions(shareNameAndQTH: true, shareContactDetails: false)
        let contactOnly = UploadFieldOptions(shareNameAndQTH: false, shareContactDetails: true)
        let both = UploadFieldOptions(shareNameAndQTH: true, shareContactDetails: true)
        let logbooks: [QSLUploadDestination] = [.qrz, .eqsl, .clubLog, .hrdlog, .hamqth, .wavelog]

        let contact = ["EMAIL", "ADDRESS", "WEB", "AGE", "BIOGRAPHY", "PUBLIC_KEY", "SILENT_KEY", "LAT", "LON", "NOTES",
                       "MY_STREET", "MY_POSTAL_CODE", "MY_LAT", "MY_LON", "GRIDSQUARE_EXT", "MY_GRIDSQUARE_EXT", "QSLMSG_RCVD", "QSL_VIA"]
        let intl = ["NAME_INTL", "QTH_INTL", "ADDRESS_INTL", "NOTES_INTL", "COMMENT_INTL", "MY_STREET_INTL"]
        let foreign = ["APP_LOTW_FOO", "APP_QRZLOG_STATUS", "FOO_BAR", "APP_YAAM_X", "QSL_MEDIA_PATH", "QRZ_URL"]
        var record: [String: String] = ["CALL": "K0ABC", "QSO_DATE": "20261017", "TIME_ON": "1200", "BAND": "20m",
                                        "MODE": "CW", "NAME": "Pau", "QTH": "Vilaprova"]
        for name in contact + intl + foreign { record[name] = "x" }

        // ---- the two switches
        for destination in logbooks {
            let named = QSLUploadStatus.uploadFields(record, for: destination, options: nameOnly)
            check("\(destination.rawValue): the name-and-QTH switch adds NAME and QTH, and no contact detail",
                  named["NAME"] == "Pau" && named["QTH"] == "Vilaprova" && contact.allSatisfy { named[$0] == nil })
            let detailed = QSLUploadStatus.uploadFields(record, for: destination, options: contactOnly)
            check("\(destination.rawValue): the contact switch adds the contact details and MY_STREET, MY_POSTAL_CODE, MY_LAT, MY_LON, not NAME or QTH",
                  contact.allSatisfy { detailed[$0] == "x" } && detailed["NAME"] == nil && detailed["QTH"] == nil)
            let closed = QSLUploadStatus.uploadFields(record, for: destination, options: off)
            check("\(destination.rawValue): with both off, none of them",
                  (contact + ["NAME", "QTH"]).allSatisfy { closed[$0] == nil } && closed["CALL"] == "K0ABC")
        }
        let lotw = QSLUploadStatus.uploadFields(record, for: .lotw, options: both)
        check("LoTW ignores the switches: with both on, no NAME, QTH or contact detail",
              (contact + ["NAME", "QTH"]).allSatisfy { lotw[$0] == nil } && lotw["CALL"] == "K0ABC",
              lotw.keys.sorted().joined(separator: ","))
        check("LoTW gets only its own list", Set(lotw.keys.map { $0.uppercased() }).isSubset(of: QSLUploadStatus.lotwFields))

        // ---- never sent, whatever the switches say
        for destination in QSLUploadDestination.allCases {
            let open = QSLUploadStatus.uploadFields(record, for: destination, options: both)
            check("\(destination.rawValue): no *_INTL field, with both switches on", intl.allSatisfy { open[$0] == nil })
            check("\(destination.rawValue): no other program's APP_ field, no non-ADIF name, no local-only field",
                  foreign.allSatisfy { open[$0] == nil })
        }
        check("a field name in lower case is matched the same way",
              QSLUploadStatus.uploadFields(["call": "K0ABC", "email": "email-here"], for: .qrz, options: off) == ["CALL": "K0ABC"])

        // ---- the lists themselves
        let allowedSets = QSLUploadStatus.uploadCoreFields.union(QSLUploadStatus.nameAndQTHFields)
            .union(QSLUploadStatus.contactDetailFields).union(QSLUploadStatus.lotwFields)
        check("no list holds an *_INTL or APP_ name",
              !allowedSets.contains { $0.hasSuffix("_INTL") || $0.hasPrefix("APP_") })
        check("the core list holds none of the personal names, and the LoTW list is inside the core list",
              QSLUploadStatus.uploadCoreFields.isDisjoint(with: QSLUploadStatus.nameAndQTHFields) &&
              QSLUploadStatus.uploadCoreFields.isDisjoint(with: QSLUploadStatus.contactDetailFields) &&
              QSLUploadStatus.lotwFields.isSubset(of: QSLUploadStatus.uploadCoreFields))
        var everyCore = Dictionary(uniqueKeysWithValues: QSLUploadStatus.uploadCoreFields.map { ($0, "x") })
        for key in ["GRIDSQUARE", "MY_GRIDSQUARE", "VUCC_GRIDS", "MY_VUCC_GRIDS"] { everyCore[key] = "BL10AB" }
        for destination in logbooks {
            let kept = QSLUploadStatus.uploadFields(everyCore, for: destination, options: off)
            let lost = QSLUploadStatus.uploadCoreFields.subtracting(kept.keys)
            check("\(destination.rawValue): every name of the core list passes (\(QSLUploadStatus.uploadCoreFields.count) names)",
                  lost.isEmpty, lost.sorted().joined(separator: ","))
        }
        var everyLoTW = Dictionary(uniqueKeysWithValues: QSLUploadStatus.lotwFields.map { ($0, "x") })
        everyLoTW["MY_GRIDSQUARE"] = "BL10AB"
        everyLoTW["MY_VUCC_GRIDS"] = "BL10AB"
        check("LoTW: every name of its list passes",
              QSLUploadStatus.uploadFields(everyLoTW, for: .lotw, options: off).count == QSLUploadStatus.lotwFields.count)

        // ---- COMMENT, the default options and the destinations
        for destination in [QSLUploadDestination.wavelog, .hrdlog, .hamqth, .qrz] {
            let tagged = QSLUploadStatus.uploadFields(["CALL": "K0ABC", "COMMENT": "[RANK=1] nice chat"], for: destination, options: UploadFieldOptions(shareNameAndQTH: false, shareContactDetails: false, shareFreeText: true))
            let onlyTags = QSLUploadStatus.uploadFields(["CALL": "K0ABC", "COMMENT": "[RANK=1]"], for: destination, options: UploadFieldOptions(shareNameAndQTH: false, shareContactDetails: false, shareFreeText: true))
            check("\(destination.rawValue): COMMENT goes out without YAAM's tags, and not at all when only tags are left",
                  tagged["COMMENT"] == "nice chat" && onlyTags["COMMENT"] == nil)
        }
        check("the switches are off when nothing is saved", UploadFieldOptions.read(from: UserDefaults(suiteName: "yaam-upload-test-" + UUID().uuidString)!) == off)
        check("without options, uploadFields reads the saved switches (off here): NAME and EMAIL stay",
              QSLUploadStatus.uploadFields(record, for: .wavelog)["NAME"] == nil &&
              QSLUploadStatus.uploadFields(record, for: .wavelog)["EMAIL"] == nil)
        check("each QSL Hub service maps to its own destination",
              QSLProvider.allCases.allSatisfy { QSLUploadDestination($0).rawValue == $0.rawValue } &&
              QSLUploadDestination(.clubLog) == .clubLog)
        let lotwADIF = QSLUploadStatus.uploadADIF(record, for: .lotw, options: both)
        check("the QSL Hub's LoTW ADIF carries only the LoTW list, with both switches on",
              lotwADIF.contains("<CALL:5>K0ABC") && !lotwADIF.contains("NAME") && !lotwADIF.contains("EMAIL") &&
              !lotwADIF.contains("APP_"), lotwADIF)

        print("\nUploadFieldSwitchesRegression: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
