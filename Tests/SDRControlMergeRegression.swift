import Foundation

struct QSORecordModel: Sendable {
    let id: UUID
    var index: Int
    var fields: [String: String]

    init(index: Int, id: UUID = UUID(), fields: [String: String]) {
        self.index = index
        self.id = id
        self.fields = fields
    }

    subscript(_ key: String) -> String {
        fields[key] ?? fields[key.uppercased()] ?? ""
    }

    var uniqueKey: String {
        QSOIdentity.exactKey(fields: fields)
    }
}

struct MergeSummary: Sendable {
    let added: Int
    let updated: Int
    let skipped: Int
}

enum ImportReviewAnalyzer {
    private static let confirmationFields = Set([
        "QSL_RCVD", "LOTW_QSL_RCVD", "QRZLOG_QSL_RCVD", "EQSL_QSL_RCVD"
    ])

    static func mergeUpdate(
        incoming: [String: String],
        into existing: [String: String]
    ) -> [String: String] {
        var merged = existing
        for (key, value) in incoming {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if (merged[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !trimmed.isEmpty {
                merged[key] = value
            } else if confirmationFields.contains(key),
                      ["Y", "YES", "TRUE", "1", "C", "CONFIRMED", "RECEIVED"].contains(trimmed.uppercased()) {
                merged[key] = value
            }
        }
        return merged
    }
}

@main
enum SDRControlMergeRegression {
    static func main() {
        let originalID = UUID()
        let sparse = QSORecordModel(
            index: 1,
            id: originalID,
            fields: exactFields(name: "", email: "", confirmed: false)
        )
        let rich = QSORecordModel(
            index: 2,
            fields: exactFields(name: "Alice Example", email: "alice@example.test", confirmed: true)
        )

        let consolidated = SDRControlMergeEngine.merge(
            localRecords: [sparse, rich],
            incomingFields: []
        )
        precondition(consolidated.records.count == 1)
        precondition(consolidated.removedDuplicates == 1)
        precondition(consolidated.records[0].id == originalID)
        precondition(consolidated.records[0]["NAME"] == "Alice Example")
        precondition(consolidated.records[0]["EMAIL"] == "alice@example.test")
        precondition(consolidated.records[0]["LOTW_QSL_RCVD"] == "Y")

        var complementary = exactFields(name: "", email: "second@example.test", confirmed: false)
        complementary["GRIDSQUARE"] = "JN61WL"
        let incomingOnly = SDRControlMergeEngine.merge(
            localRecords: [],
            incomingFields: [
                exactFields(name: "Second Operator", email: "", confirmed: true),
                complementary
            ]
        )
        precondition(incomingOnly.records.count == 1)
        precondition(incomingOnly.summary.added == 1)
        precondition(incomingOnly.summary.updated == 1)
        precondition(incomingOnly.records[0]["NAME"] == "Second Operator")
        precondition(incomingOnly.records[0]["EMAIL"] == "second@example.test")
        precondition(incomingOnly.records[0]["GRIDSQUARE"] == "JN61WL")

        var later = exactFields(name: "Later QSO", email: "", confirmed: false)
        later["TIME_ON"] = "120500"
        let distinctTimes = SDRControlMergeEngine.merge(
            localRecords: [],
            incomingFields: [exactFields(name: "First QSO", email: "", confirmed: false), later]
        )
        precondition(distinctTimes.records.count == 2)
        precondition(distinctTimes.summary.added == 2)

        var coarse = roundedSDRFields(time: "210500", frequency: "21.0766")
        coarse["LOTW_QSL_RCVD"] = "Y"
        coarse["LOTW_QSLRDATE"] = "20260823"
        var precise = roundedSDRFields(time: "210514", frequency: "21.076626")
        precise["LOTW_QSL_RCVD"] = "N"
        precise["GRIDSQUARE"] = "PM95"

        let roundedPair = SDRControlMergeEngine.merge(
            localRecords: [],
            incomingFields: [coarse, precise],
            allowRoundedSDRMatches: true
        )
        precondition(roundedPair.records.count == 1)
        precondition(roundedPair.summary.added == 1)
        precondition(roundedPair.summary.updated == 1)
        precondition(roundedPair.records[0]["TIME_ON"] == "210514")
        precondition(roundedPair.records[0]["FREQ"] == "21.076626")
        precondition(roundedPair.records[0]["LOTW_QSL_RCVD"] == "Y")
        precondition(roundedPair.records[0]["LOTW_QSLRDATE"] == "20260823")
        precondition(roundedPair.records[0]["GRIDSQUARE"] == "PM95")

        let reverseRoundedPair = SDRControlMergeEngine.merge(
            localRecords: [],
            incomingFields: [precise, coarse],
            allowRoundedSDRMatches: true
        )
        precondition(reverseRoundedPair.records.count == 1)
        precondition(reverseRoundedPair.records[0]["TIME_ON"] == "210514")
        precondition(reverseRoundedPair.records[0]["FREQ"] == "21.076626")
        precondition(reverseRoundedPair.records[0]["LOTW_QSL_RCVD"] == "Y")

        let existingRoundedPairs = [
            ("JA3JKK", "210500", "210514"),
            ("JF2DJV", "210200", "210214"),
            ("JA0UUA", "210000", "210044"),
            ("JR8AMF", "205600", "205644")
        ].flatMap { callsign, roundedTime, preciseTime in
            [
                QSORecordModel(
                    index: 0,
                    fields: roundedSDRFields(
                        call: callsign,
                        time: roundedTime,
                        frequency: "21.0766"
                    )
                ),
                QSORecordModel(
                    index: 0,
                    fields: roundedSDRFields(
                        call: callsign,
                        time: preciseTime,
                        frequency: "21.076626"
                    )
                )
            ]
        }
        let cleanedExistingPairs = SDRControlMergeEngine.merge(
            localRecords: existingRoundedPairs,
            incomingFields: [],
            allowRoundedSDRMatches: true
        )
        precondition(cleanedExistingPairs.records.count == 4)
        precondition(cleanedExistingPairs.removedDuplicates == 4)
        precondition(cleanedExistingPairs.records.allSatisfy { record in
            record["TIME_ON"].hasSuffix("14") || record["TIME_ON"].hasSuffix("44")
        })
        precondition(cleanedExistingPairs.records.allSatisfy { $0["FREQ"] == "21.076626" })

        let exactOnlyPair = SDRControlMergeEngine.merge(
            localRecords: [],
            incomingFields: [coarse, precise]
        )
        precondition(exactOnlyPair.records.count == 2)

        var anotherRealQSO = precise
        anotherRealQSO["TIME_ON"] = "210544"
        let twoRealQSOs = SDRControlMergeEngine.merge(
            localRecords: [],
            incomingFields: [precise, anotherRealQSO],
            allowRoundedSDRMatches: true
        )
        precondition(twoRealQSOs.records.count == 2)

        var nextMinute = coarse
        nextMinute["TIME_ON"] = "210600"
        let differentMinutes = SDRControlMergeEngine.merge(
            localRecords: [],
            incomingFields: [precise, nextMinute],
            allowRoundedSDRMatches: true
        )
        precondition(differentMinutes.records.count == 2)

        print("SDR-Control duplicate merge regression passed.")
    }

    private static func exactFields(
        name: String,
        email: String,
        confirmed: Bool
    ) -> [String: String] {
        [
            "CALL": "IZ0ZZZ",
            "QSO_DATE": "20260823",
            "TIME_ON": "120000",
            "BAND": "20M",
            "MODE": "MFSK",
            "SUBMODE": "FT8",
            "FREQ": "14.074",
            "NAME": name,
            "EMAIL": email,
            "LOTW_QSL_RCVD": confirmed ? "Y" : "N"
        ]
    }

    private static func roundedSDRFields(
        call: String = "JA3JKK",
        time: String,
        frequency: String
    ) -> [String: String] {
        [
            "CALL": call,
            "QSO_DATE": "20260620",
            "TIME_ON": time,
            "BAND": "15M",
            "MODE": "MFSK",
            "SUBMODE": "FT8",
            "FREQ": frequency,
            "NAME": "Tsukasa Egami",
            "RST_SENT": "-10",
            "RST_RCVD": "-01"
        ]
    }
}
