import Foundation
@testable import YAAM

@main
struct ConfirmationSyncRegression {
    static func main() {
        testHTMLEncodedQRZResponse()
        testPercentEncodedQRZResponse()
        testThirtyMinuteOneToOneMatching()
        testReportedLoTWAndQRZConfirmationsRemainIndependent()
        testPaperDirectRequiresExplicitProvenance()
        testIncrementalReplayWindow()
        testCheckpointInvalidationAfterLateImport()
        print("Confirmation sync regression tests passed.")
    }

    private static func testHTMLEncodedQRZResponse() {
        let adif = "&lt;QSO_DATE:8&gt;20260820&lt;TIME_ON:6&gt;101500&lt;CALL:6&gt;EP2AES&lt;BAND:3&gt;20M&lt;MODE:3&gt;FT8&lt;APP_QRZLOG_LOGID:3:N&gt;123&lt;EOR&gt;"
        let response = ConfirmationDownloadService.parseQRZResponse("RESULT=OK&COUNT=1&ADIF=\(adif)")
        precondition(response.result == "OK")
        precondition(response.count == 1)
        let (_, records) = parseADIF(content: response.adif)
        precondition(records.count == 1)
        precondition(records[0]["CALL"] == "EP2AES")
        precondition(records[0]["APP_QRZLOG_LOGID"] == "123")
    }

    private static func testPercentEncodedQRZResponse() {
        let adif = "<QSO_DATE:8>20260820<TIME_ON:6>101500<CALL:6>EP2AES<BAND:3>20M<MODE:3>FT8<APP_QRZLOG_LOGID:3:N>124<EOR>"
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "ADIF", value: adif)]
        let encoded = components.percentEncodedQuery ?? ""
        let response = ConfirmationDownloadService.parseQRZResponse("RESULT=OK&COUNT=1&\(encoded)")
        let (_, records) = parseADIF(content: response.adif)
        precondition(records.count == 1)
        precondition(records[0]["APP_QRZLOG_LOGID"] == "124")
    }

    private static func testThirtyMinuteOneToOneMatching() {
        let local = [
            QSORecordModel(index: 1, fields: fields(call: "K9OM", time: "100000", mode: "MFSK")),
            QSORecordModel(index: 2, fields: fields(call: "K9OM", time: "102500", mode: "MFSK")),
            QSORecordModel(index: 3, fields: fields(call: "W1AW", time: "100000", mode: "SSB"))
        ]
        let qrz = [
            fields(call: "K9OM", time: "102400", mode: "FT8"),
            fields(call: "K9OM", time: "100100", mode: "FT8"),
            fields(call: "W1AW", time: "103001", mode: "SSB")
        ]

        let result = ConfirmationMergeEngine.merge(localRecords: local, lotwRecords: [], qrzRecords: qrz)
        precondition(result.qrzMatched == 2)
        precondition(result.qrzUnmatched == 1)
        precondition(result.qrzChanged == 2)
        precondition(result.records[0]["QRZLOG_QSL_RCVD"] == "Y")
        precondition(result.records[1]["QRZLOG_QSL_RCVD"] == "Y")
        precondition(result.records[2]["QRZLOG_QSL_RCVD"].isEmpty)
    }

    private static func testReportedLoTWAndQRZConfirmationsRemainIndependent() {
        let local = [
            QSORecordModel(
                index: 1,
                fields: fields(
                    call: "SM6CWP",
                    date: "20260822",
                    time: "113714",
                    band: "15M",
                    mode: "FT8"
                )
            ),
            QSORecordModel(
                index: 2,
                fields: fields(
                    call: "SP5IDR",
                    date: "20260822",
                    time: "111014",
                    band: "15M",
                    mode: "FT8"
                )
            )
        ]
        let lotw = [
            fields(
                call: "SM6CWP",
                date: "20260822",
                time: "113700",
                band: "15M",
                mode: "FT8",
                extra: ["QSLRDATE": "20260822"]
            )
        ]
        let qrz = [
            fields(
                call: "SP5IDR",
                date: "20260822",
                time: "111000",
                band: "15M",
                mode: "FT8",
                extra: [
                    "APP_QRZLOG_QSLDATE": "20260822",
                    "APP_QRZLOG_STATUS": "C"
                ]
            )
        ]

        let result = ConfirmationMergeEngine.merge(
            localRecords: local,
            lotwRecords: lotw,
            qrzRecords: qrz
        )

        precondition(result.lotwMatched == 1)
        precondition(result.qrzMatched == 1)
        precondition(result.lotwChanged == 1)
        precondition(result.qrzChanged == 1)
        precondition(result.records[0]["LOTW_QSL_RCVD"] == "Y")
        precondition(result.records[0]["QRZLOG_QSL_RCVD"].isEmpty)
        precondition(result.records[0]["QSL_RCVD"] == "Y")
        precondition(result.records[1]["LOTW_QSL_RCVD"].isEmpty)
        precondition(result.records[1]["QRZLOG_QSL_RCVD"] == "Y")
        precondition(result.records[1]["QSL_RCVD"] == "Y")
    }

    private static func testPaperDirectRequiresExplicitProvenance() {
        let lotwOnly = QSORecordModel(
            index: 1,
            fields: fields(
                call: "SM6CWP",
                time: "113714",
                mode: "FT8",
                extra: ["QSL_RCVD": "Y", "LOTW_QSL_RCVD": "Y"]
            )
        )
        let qrzOnly = QSORecordModel(
            index: 2,
            fields: fields(
                call: "SP5IDR",
                time: "111014",
                mode: "FT8",
                extra: ["QSL_RCVD": "Y", "QRZLOG_QSL_RCVD": "Y"]
            )
        )
        let direct = QSORecordModel(
            index: 3,
            fields: fields(
                call: "W1AW",
                time: "120000",
                mode: "SSB",
                extra: ["QSL_RCVD": "Y", "QSL_RCVD_VIA": "D"]
            )
        )
        let bureau = QSORecordModel(
            index: 4,
            fields: fields(
                call: "K1JT",
                time: "121500",
                mode: "FT8",
                extra: ["QSL_RCVD": "Y", "QSL_RCVD_VIA": "B"]
            )
        )
        let explicitPaper = QSORecordModel(
            index: 5,
            fields: fields(
                call: "N0CALL",
                time: "123000",
                mode: "CW",
                extra: ["QSL_RCVD": "Y", "APP_YAAM_QSL_SOURCE": "Paper card"]
            )
        )
        let unconfirmedDirect = QSORecordModel(
            index: 6,
            fields: fields(
                call: "N1CALL",
                time: "124500",
                mode: "CW",
                extra: ["QSL_RCVD": "N", "QSL_RCVD_VIA": "D"]
            )
        )

        precondition(!StatisticsConfirmationSourceClassifier.isPaperOrDirectConfirmed(lotwOnly))
        precondition(!StatisticsConfirmationSourceClassifier.isPaperOrDirectConfirmed(qrzOnly))
        precondition(StatisticsConfirmationSourceClassifier.isPaperOrDirectConfirmed(direct))
        precondition(StatisticsConfirmationSourceClassifier.isPaperOrDirectConfirmed(bureau))
        precondition(StatisticsConfirmationSourceClassifier.isPaperOrDirectConfirmed(explicitPaper))
        precondition(!StatisticsConfirmationSourceClassifier.isPaperOrDirectConfirmed(unconfirmedDirect))
    }

    private static func testIncrementalReplayWindow() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let checkpoint = formatter.date(from: "2026-08-23 12:00:00")!
        let replayDate = ConfirmationSyncPolicy.replayDate(checkpoint)!
        precondition(formatter.string(from: replayDate) == "2026-08-09 12:00:00")
        precondition(
            ConfirmationSyncPolicy.replayLoTWCursor("2026-08-23 12:00:00")
                == "2026-08-09 12:00:00"
        )
    }

    private static func testCheckpointInvalidationAfterLateImport() {
        let profileID = UUID()
        let checkpoint = ConfirmationSyncCheckpoint(
            baselineCompleted: true,
            lotwCursor: "2026-08-23 12:00:00",
            lastSuccess: Date()
        )
        ConfirmationSyncCheckpointStore.save(checkpoint, profileID: profileID, source: .lotw)
        ConfirmationSyncCheckpointStore.save(checkpoint, profileID: profileID, source: .qrz)

        precondition(ConfirmationSyncCheckpointStore.load(profileID: profileID, source: .lotw).baselineCompleted)
        precondition(ConfirmationSyncCheckpointStore.load(profileID: profileID, source: .qrz).baselineCompleted)

        ConfirmationSyncCheckpointStore.invalidate(profileID: profileID)

        precondition(!ConfirmationSyncCheckpointStore.load(profileID: profileID, source: .lotw).baselineCompleted)
        precondition(!ConfirmationSyncCheckpointStore.load(profileID: profileID, source: .qrz).baselineCompleted)
    }

    private static func fields(
        call: String,
        date: String = "20260820",
        time: String,
        band: String = "20M",
        mode: String,
        extra: [String: String] = [:]
    ) -> [String: String] {
        var result = [
            "CALL": call,
            "QSO_DATE": date,
            "TIME_ON": time,
            "BAND": band,
            "MODE": mode
        ]
        result.merge(extra) { _, new in new }
        return result
    }
}
