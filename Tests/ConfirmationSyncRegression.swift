import Foundation
@testable import YAAM

@main
struct ConfirmationSyncRegression {
    static func main() {
        testHTMLEncodedQRZResponse()
        testPercentEncodedQRZResponse()
        testThirtyMinuteOneToOneMatching()
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

    private static func fields(call: String, time: String, mode: String) -> [String: String] {
        [
            "CALL": call,
            "QSO_DATE": "20260820",
            "TIME_ON": time,
            "BAND": "20M",
            "MODE": mode
        ]
    }
}
