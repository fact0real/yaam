// swiftc -parse-as-library Tests/QuickLogReuseRegression.swift YAAM/QuickLogReusePolicy.swift YAAM/OperatorModels.swift YAAM/AmateurBandSettings.swift YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift -o /tmp/yaam-quicklog-reuse && /tmp/yaam-quicklog-reuse
import Foundation
struct QSORecordModel { var fields: [String:String] = [:]; var isConfirmed = false; subscript(_ key: String) -> String { fields[key] ?? "" } }
@main struct QuickLogReuseRegression {
    static func main() {
        let source = ["CALL":"W1AW", "FREQ":"14.074", "BAND":"20m", "MODE":"FT8", "RST_SENT":"-05", "QSO_DATE":"20200101", "TIME_ON":"120000", "QSL_RCVD":"Y", "LOTW_QSL_SENT":"Y", "STX":"99", "CONTEST_ID":"OLD"]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = QuickLogReusePolicy.newDraft(from: source, now: now)
        precondition(draft.callsign == "W1AW" && draft.startedAt == now && draft.endedAt == now)
        precondition(draft.mode == "FT8" && draft.rstSent == "-05")
        precondition(draft.receivedExchange.isEmpty && draft.sentSerial.isEmpty && draft.receivedSerial.isEmpty)
        precondition(draft.source.contains("new draft"))
        precondition(source["QSO_DATE"] == "20200101" && source["QSL_RCVD"] == "Y")
        let blank = QuickLogReusePolicy.newDraft(from: [:], now: now)
        precondition(blank.frequencyMHz.isEmpty && blank.mode.isEmpty && blank.rstSent.isEmpty)
        print("PASS Quick Log reuse: explicit new draft, fresh timestamps, no identity/status/contest leakage, original unchanged")
    }
}
