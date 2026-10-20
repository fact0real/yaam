// swiftc -D STANDALONE_ADIF -parse-as-library Tests/DigitalContactCompletionRegression.swift YAAM/DigitalContactCompletion.swift YAAM/ADIFParser.swift YAAM/QSOIdentity.swift YAAM/OperatorModels.swift YAAM/AmateurBandSettings.swift YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift YAAM/QSOMetadataFormatter.swift -o /tmp/yaam-digital-completion && /tmp/yaam-digital-completion
import Foundation
struct QSORecordModel { var fields: [String:String] = [:]; var isConfirmed = false; subscript(_ key: String) -> String { fields[key] ?? "" } }
@main struct DigitalContactCompletionRegression {
    static func main() {
        precondition(DigitalContactTracker.rfFrequency(dialHz: 14_074_000, audioHz: 1234) == 14_075_234)
        for audio in [Float.nan, .infinity, -1, 100_000] {
            precondition(DigitalContactTracker.rfFrequency(dialHz: 14_074_000, audioHz: audio) == nil)
        }
        precondition(DigitalContactTracker.rfFrequency(dialHz: .max, audioHz: 1000) == nil)
        let format = ISO8601DateFormatter()
        let start = format.date(from: "2026-10-20T23:59:50Z")!, end = format.date(from: "2026-10-21T00:00:20Z")!
        for proto in ["FT8", "FT4"] {
            var tracker = DigitalContactTracker()
            precondition(tracker.completion(call: "W1AW", at: end) == nil, "Do not invent an unknown start")
            tracker.observe(call: "W1AW", grid: "FN31", protocolName: proto, band: "20m", stationCall: "EP2AES", stationGrid: "LM45",
                at: start, transmitHz: 14_075_234, sentReport: -7)
            tracker.observe(call: "W1AW", grid: "", protocolName: proto, band: "20m", stationCall: "EP2AES", stationGrid: "LM45",
                at: end, receiveHz: 14_075_400, receivedReport: -11)
            let completed = tracker.completion(call: "W1AW", at: end)!, fields = completed.fields
            precondition(fields["MODE"] == (proto == "FT4" ? "MFSK" : "FT8"))
            precondition(fields["SUBMODE"] == (proto == "FT4" ? "FT4" : nil))
            precondition(fields["QSO_DATE"] == "20261020" && fields["QSO_DATE_OFF"] == "20261021")
            precondition(fields["TIME_ON"] == "235950" && fields["TIME_OFF"] == "000020")
            precondition(fields["RST_SENT"] == "-07" && fields["RST_RCVD"] == "-11")
            precondition(fields["FREQ"] == "14.075234" && fields["FREQ_RX"] == "14.075400")
            precondition(fields["GRIDSQUARE"] == "FN31" && fields["MY_GRIDSQUARE"] == "LM45")
            precondition(tracker.completion(call: "W1AW", at: end)?.id == completed.id, "Duplicate callbacks keep session identity")
            let adif = generateADIF(originalContent: "", records: [fields])
            let (_, parsed) = parseADIF(content: adif)
            precondition(parsed.count == 1 && parsed[0]["QSO_DATE_OFF"] == "20261021")
            precondition(parsed[0]["MODE"] == fields["MODE"])
            precondition(QSOIdentity.exactKey(fields: parsed[0]) == QSOIdentity.exactKey(fields: fields))
            tracker.reset(); precondition(tracker.completion(call: "W1AW", at: end) == nil)
            tracker.observe(call: "W2XYZ", grid: "", protocolName: proto, band: "40m", stationCall: "EP2AES/P", stationGrid: "", at: end)
            let unknown = tracker.completion(call: "W2XYZ", at: end)!.fields
            precondition(unknown["RST_SENT"] == nil && unknown["RST_RCVD"] == nil && unknown["FREQ"] == nil)
        }
        print("PASS FT8/FT4 completion: actual mode, UTC midnight, reports, precise RF, station/grid, ADIF round trip and stable replay identity")
    }
}
