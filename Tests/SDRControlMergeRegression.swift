import Foundation
@testable import YAAM

@main
enum SDRControlMergeRegression {
    static func main() {
        let originalID = UUID()
        let sparse = QSORecordModel(
            id: originalID,
            index: 1,
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

        // Test Enrichment & Rank Shielding
        var enrichedCoarse = roundedSDRFields(call: "EP2AES", time: "183000", frequency: "14.074")
        enrichedCoarse["RANK_DXCC"] = "#120"
        enrichedCoarse["RANK_QSO"] = "#34"
        enrichedCoarse["RANK_BAND"] = "#15"
        enrichedCoarse["EMAIL"] = "ep2aes@example.com"
        enrichedCoarse["APP_YAAM_ENRICHED"] = "Y"
        enrichedCoarse["LOTW_QSL_RCVD"] = "Y"
        enrichedCoarse["LOTW_QSLRDATE"] = "20260901"

        var rawIncomingSDR = roundedSDRFields(call: "EP2AES", time: "183014", frequency: "14.074123")
        rawIncomingSDR["RANK_DXCC"] = ""
        rawIncomingSDR["RANK_QSO"] = ""
        rawIncomingSDR["RANK_BAND"] = ""
        rawIncomingSDR["EMAIL"] = ""
        rawIncomingSDR["APP_YAAM_ENRICHED"] = ""
        rawIncomingSDR["LOTW_QSL_RCVD"] = "N"

        let enrichedMerged = SDRControlMergeEngine.merge(
            localRecords: [QSORecordModel(index: 1, fields: enrichedCoarse)],
            incomingFields: [rawIncomingSDR],
            allowRoundedSDRMatches: true
        )
        precondition(enrichedMerged.records.count == 1)
        precondition(enrichedMerged.records[0]["RANK_DXCC"] == "#120")
        precondition(enrichedMerged.records[0]["RANK_QSO"] == "#34")
        precondition(enrichedMerged.records[0]["RANK_BAND"] == "#15")
        precondition(enrichedMerged.records[0]["EMAIL"] == "ep2aes@example.com")
        precondition(enrichedMerged.records[0]["APP_YAAM_ENRICHED"] == "Y")
        precondition(enrichedMerged.records[0]["LOTW_QSL_RCVD"] == "Y")
        precondition(enrichedMerged.records[0]["TIME_ON"] == "183014")
        precondition(enrichedMerged.records[0]["FREQ"] == "14.074123")

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
