//
//  ImportUploadStatusRegression.swift
//  YAAM
//
//  An import of a QSO that is already in the log only raises its upload status: an incoming Y replaces an empty or
//  pending value (N, R, Q, I or M) and brings its date, and a Y already there is never replaced. This holds for the
//  four ADIF upload-status fields, YAAM's own Club Log field and QRZCOM_QSO_DOWNLOAD_STATUS, whichever record wins
//  the merge. V, C and CONFIRMED count as Y, as in the QSL Hub.
//  Run from the repository root:
//    swiftc -parse-as-library Tests/ImportUploadStatusRegression.swift YAAM/ImportReview.swift YAAM/QSOIdentity.swift \
//      YAAM/QSOMetadataFormatter.swift YAAM/OperatorModels.swift YAAM/AmateurBandSettings.swift \
//      YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift \
//      YAAM/CountryNameNormalizer.swift -o ius && ./ius
//  ImportReview.swift reads the QSO record and the log source format of other files, and the band plan (the last six
//  files) cleans comments; small stand-ins for the record and the format are below. SDRControlMergeEngine and the import's apply step are checked in their source.
//

import Foundation

// Stand-in for the QSO record of AppState.swift.
nonisolated struct QSORecordModel: Identifiable {
    var id = UUID()
    var fields: [String: String] = [:]
    var isConfirmed = false
    subscript(key: String) -> String { fields[key] ?? "" }
}

// Stand-in for the log source format of LogFileReader.swift; the import review only stores it.
nonisolated enum LogSourceFormat: String, Codable, Sendable {
    case adif
}

@main
struct ImportUploadStatusRegression {
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

    static func main() {
        let statusFields: [(status: String, date: String)] = [
            ("LOTW_QSL_SENT", "LOTW_QSLSDATE"), ("EQSL_QSL_SENT", "EQSL_QSLSDATE"),
            ("QRZCOM_QSO_UPLOAD_STATUS", "QRZCOM_QSO_UPLOAD_DATE"), ("CLUBLOG_QSO_UPLOAD_STATUS", "CLUBLOG_QSO_UPLOAD_DATE"),
            ("APP_YAAM_CLUBLOG_SENT", "APP_YAAM_CLUBLOG_SENT_DATE"),
        ]
        let qso = ["CALL": "EP2AES", "QSO_DATE": "20261008", "TIME_ON": "0900", "BAND": "17m", "MODE": "SSB"]

        // ---- a pending value in the log, a Y in the import: the Y and its date come in
        var raisedMisses: [String] = []
        for (status, date) in statusFields {
            for pending in ["N", "R", "Q", "I", "M"] {
                let local = qso.merging([status: pending, date: "20261001"]) { $1 }
                let incoming = qso.merging([status: "Y", date: "20261005"]) { $1 }
                let merged = ImportReviewAnalyzer.mergeUpdate(incoming: incoming, into: local)
                if merged[status] != "Y" || merged[date] != "20261005" { raisedMisses.append("\(status)=\(pending)") }
            }
        }
        check("an imported Y replaces N, R, Q, I or M in each of the five upload-status fields, with its date",
              raisedMisses.isEmpty, raisedMisses.prefix(6).joined(separator: ", "))
        var downloadMisses: [String] = []
        for pending in ["N", "I"] {
            let local = qso.merging(["QRZCOM_QSO_DOWNLOAD_STATUS": pending, "QRZCOM_QSO_DOWNLOAD_DATE": "20261001"]) { $1 }
            let incoming = qso.merging(["QRZCOM_QSO_DOWNLOAD_STATUS": "Y", "QRZCOM_QSO_DOWNLOAD_DATE": "20261005"]) { $1 }
            let merged = ImportReviewAnalyzer.mergeUpdate(incoming: incoming, into: local)
            if merged["QRZCOM_QSO_DOWNLOAD_STATUS"] != "Y" || merged["QRZCOM_QSO_DOWNLOAD_DATE"] != "20261005" { downloadMisses.append(pending) }
            let back = ImportReviewAnalyzer.mergeUpdate(incoming: local, into: incoming)
            if back["QRZCOM_QSO_DOWNLOAD_STATUS"] != "Y" { downloadMisses.append("\(pending) over Y") }
        }
        check("QRZCOM_QSO_DOWNLOAD_STATUS goes up from N or I to Y with its date, and a Y stays", downloadMisses.isEmpty,
              downloadMisses.joined(separator: ", "))
        var legacyMisses: [String] = []
        for incomingValue in ["V", "C", "CONFIRMED"] {
            let local = qso.merging(["LOTW_QSL_SENT": "N"]) { $1 }
            let incoming = qso.merging(["LOTW_QSL_SENT": incomingValue, "LOTW_QSLSDATE": "20261005"]) { $1 }
            let merged = ImportReviewAnalyzer.mergeUpdate(incoming: incoming, into: local)
            if merged["LOTW_QSL_SENT"] != incomingValue || merged["LOTW_QSLSDATE"] != "20261005" { legacyMisses.append(incomingValue) }
        }
        check("an imported V, C or CONFIRMED (read as sent, as in the QSL Hub) replaces N too", legacyMisses.isEmpty,
              legacyMisses.joined(separator: ", "))

        // ---- a Y in the log is never replaced
        var keptMisses: [String] = []
        for (status, date) in statusFields {
            for sent in ["Y", "V", "C", "CONFIRMED", " Y ", "y"] {
                for other in ["N", "M", "I", "", "Y"] {
                    let local = qso.merging([status: sent, date: "20260920"]) { $1 }
                    let incoming = qso.merging([status: other, date: "20261005"]) { $1 }
                    let merged = ImportReviewAnalyzer.mergeUpdate(incoming: incoming, into: local)
                    if merged[status] != sent || merged[date] != "20260920" { keptMisses.append("\(status)=\(sent)<-\(other.isEmpty ? "empty" : other)") }
                }
            }
        }
        check("a Y in the log (or V, C, CONFIRMED, with spaces, in lower case) is kept, with its date, whatever the import says (a later Y too)",
              keptMisses.isEmpty, keptMisses.prefix(6).joined(separator: ", "))

        // ---- whichever record wins a merge (SDRControlMergeEngine merges the loser into the winner)
        let withY = qso.merging(["LOTW_QSL_SENT": "Y", "LOTW_QSLSDATE": "20261002"]) { $1 }
        let withN = qso.merging(["LOTW_QSL_SENT": "N"]) { $1 }
        check("a Y from either record survives the merge, in both orders",
              ImportReviewAnalyzer.mergeUpdate(incoming: withY, into: withN)["LOTW_QSL_SENT"] == "Y" &&
              ImportReviewAnalyzer.mergeUpdate(incoming: withN, into: withY)["LOTW_QSL_SENT"] == "Y")
        check("an empty status is filled from the import, as before",
              ImportReviewAnalyzer.mergeUpdate(incoming: withY, into: qso)["LOTW_QSL_SENT"] == "Y")
        let lowerCase = ImportReviewAnalyzer.mergeUpdate(
            incoming: ["clublog_qso_upload_status": "Y", "clublog_qso_upload_date": "20261003"],
            into: qso.merging(["CLUBLOG_QSO_UPLOAD_STATUS": "N", "CLUBLOG_QSO_UPLOAD_DATE": "20261001"]) { $1 })
        check("field names in lower case are read too, with the date",
              lowerCase["CLUBLOG_QSO_UPLOAD_STATUS"] == "Y" && lowerCase["CLUBLOG_QSO_UPLOAD_DATE"] == "20261003")

        // ---- APP_QRZLOG_STATUS (QRZ's status, which Sync reads) only goes up too
        let uploadedQRZ = qso.merging(["APP_QRZLOG_STATUS": "UPLOADED"]) { $1 }
        let confirmedQRZ = qso.merging(["APP_QRZLOG_STATUS": "CONFIRMED"]) { $1 }
        let qrzReview = ImportReviewAnalyzer.analyze(
            sourceName: "other.adi", sourceURL: URL(fileURLWithPath: "other.adi"), sourceFormat: .adif,
            destinationProfileID: nil, headers: [], incoming: [confirmedQRZ], existing: [QSORecordModel(fields: uploadedQRZ)]
        ).items.first
        let errorQRZ = qso.merging(["APP_QRZLOG_STATUS": "ERROR"]) { $1 }
        let errorReview = ImportReviewAnalyzer.analyze(
            sourceName: "other.adi", sourceURL: URL(fileURLWithPath: "other.adi"), sourceFormat: .adif,
            destinationProfileID: nil, headers: [], incoming: [uploadedQRZ], existing: [QSORecordModel(fields: errorQRZ)]
        ).items.first
        check("APP_QRZLOG_STATUS UPLOADED goes up to CONFIRMED, and the review offers it as an update",
              ImportReviewAnalyzer.mergeUpdate(incoming: confirmedQRZ, into: uploadedQRZ)["APP_QRZLOG_STATUS"] == "CONFIRMED" &&
              qrzReview?.kind == .confirmationUpdate)
        check("APP_QRZLOG_STATUS ERROR (pending) goes up to UPLOADED, and the review offers it as an update",
              ImportReviewAnalyzer.mergeUpdate(incoming: uploadedQRZ, into: errorQRZ)["APP_QRZLOG_STATUS"] == "UPLOADED" &&
              errorReview?.kind == .confirmationUpdate)
        check("APP_QRZLOG_STATUS CONFIRMED is never lowered to UPLOADED or ERROR, UPLOADED never to ERROR, and Y (read as confirmed) never to UPLOADED",
              ImportReviewAnalyzer.mergeUpdate(incoming: uploadedQRZ, into: confirmedQRZ)["APP_QRZLOG_STATUS"] == "CONFIRMED" &&
              ImportReviewAnalyzer.mergeUpdate(incoming: errorQRZ, into: confirmedQRZ)["APP_QRZLOG_STATUS"] == "CONFIRMED" &&
              ImportReviewAnalyzer.mergeUpdate(incoming: errorQRZ, into: uploadedQRZ)["APP_QRZLOG_STATUS"] == "UPLOADED" &&
              ImportReviewAnalyzer.mergeUpdate(incoming: uploadedQRZ, into: qso.merging(["APP_QRZLOG_STATUS": "y"]) { $1 })["APP_QRZLOG_STATUS"] == "y")

        // ---- the import review offers such a record as an update, not as a duplicate (the log's record already has
        // a date, so only the status differs)
        let existing = [QSORecordModel(fields: withN.merging(["LOTW_QSLSDATE": "20261001"]) { $1 })]
        func review(_ incoming: [String: String]) -> ImportReviewItem? {
            ImportReviewAnalyzer.analyze(
                sourceName: "other.adi",
                sourceURL: URL(fileURLWithPath: "other.adi"),
                sourceFormat: .adif,
                destinationProfileID: nil,
                headers: Array(incoming.keys),
                incoming: [incoming],
                existing: existing
            ).items.first
        }
        let update = review(withY)
        check("a QSO in the log that comes in with LOTW_QSL_SENT N to Y is an update, selected",
              update?.kind == .confirmationUpdate && update?.isSelected == true, "\(String(describing: update?.kind))")
        let same = review(withN)
        let updateC = review(withN.merging(["LOTW_QSL_SENT": "C"]) { $1 })
        check("a QSO in the log that comes in with LOTW_QSL_SENT N to C is an update too",
              updateC?.kind == .confirmationUpdate && updateC?.isSelected == true, "\(String(describing: updateC?.kind))")
        check("the same QSO with nothing new is a duplicate, not selected",
              same?.kind == .duplicate && same?.isSelected == false, "\(String(describing: same?.kind))")
        let down = review(qso.merging(["LOTW_QSL_SENT": "N"]) { $1 })
        let fromYLog = ImportReviewAnalyzer.analyze(
            sourceName: "other.adi", sourceURL: URL(fileURLWithPath: "other.adi"), sourceFormat: .adif,
            destinationProfileID: nil, headers: [], incoming: [qso.merging(["LOTW_QSL_SENT": "N"]) { $1 }],
            existing: [QSORecordModel(fields: withY)]
        ).items.first
        check("an import that would lower Y to N brings nothing: a duplicate",
              fromYLog?.kind == .duplicate && down?.kind == .duplicate, "\(String(describing: fromYLog?.kind))")

        // ---- in the app (source): the other merges go through mergeUpdate
        let merge = source("YAAM/SDRControlMergeEngine.swift")
        check("SDR-Control's merge of two records goes through mergeUpdate, so it keeps a Y the same way",
              merge.contains("var merged = ImportReviewAnalyzer.mergeUpdate(incoming: loser, into: winner)"))
        let persistence = source("YAAM/AppStatePersistence.swift")
        check("the import's update step goes through mergeUpdate",
              persistence.contains("ImportReviewAnalyzer.mergeUpdate("))
        check("the duplicate review, the cloud sync merge and the eQSL downloads go through mergeUpdate too",
              source("YAAM/DuplicateReview.swift").contains("ImportReviewAnalyzer.mergeUpdate(") &&
              source("YAAM/ConnectivityServices.swift").contains("ImportReviewAnalyzer.mergeUpdate(") &&
              source("YAAM/QSLSyncEngine.swift").contains("ImportReviewAnalyzer.mergeUpdate(") &&
              source("YAAM/AppStateQSLHub.swift").contains("ImportReviewAnalyzer.mergeUpdate("))

        print("\(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
